;; ===========================================================================
;; MAINNET RELEASE CANDIDATE — NOT DEPLOYED. FOR REVIEW.
;;
;; This file is the lineage a mainnet deployment would use. No mainnet
;; deployment exists; nothing here implies one is scheduled. The candidate
;; becomes final only at the pre-mainnet freeze, after a full re-audit.
;;
;; It is the SAME system as the live testnet06 deployment (../testnet06/),
;; minus test-event lifecycle machinery — the exact differences are listed in
;; docs/TESTNET-VS-MAINNET.md and are mechanically checkable:
;;   cd scripts && node compare-lineages.mjs
;; ===========================================================================
;; ===========================================================================
;; smartpacts-gas-station — sponsors gas for SPT end-user actions ONLY (gasless UX).
;; Shareholders need no KDA to vote or claim dividends.
;;
;; Sponsored (per-function allowlist, NOT a namespace-wide prefix):
;;   - smartpacts-shares.cast-vote          (chain-local vote on EVERY chain)
;;   - smartpacts-shares.claim-dividends    (permissionless dividend claim)
;; NOT sponsored: every admin op (fund-dividends, proposals, withdraw-revenue,
;;   sale admin, init/init-supply) — the operator pays its own gas.
;;
;; Pattern: KIP gas-payer-v1. Deployed + funded PER CHAIN (voters/claimers are
;; everywhere).
;; ===========================================================================
(namespace (read-msg 'ns))

(module smartpacts-gas-station GOVERNANCE
  @doc "Gas station: pays coin.GAS for an allowlist of SPT end-user functions. \
       \nDrain defense: exec-code allowlist + single-call + gas-price/limit ceilings."

  (implements gas-payer-v1)
  (use coin)

  ;; ========================================================================
  ;; CONSTANTS
  ;; ========================================================================
  ;; The admin keyset name is DERIVED from the deploy transaction's namespace —
  ;; no per-network source edit, no substitution step at deploy time.
  (defconst ADMIN-KS (format "{}.spt-admin" [(read-msg 'ns)]))
  ;; Set true and redeploy to permanently freeze upgrades (sponsorship still works).
  (defconst FROZEN-MODULE false)

  ;; Drain-attack ceilings. A sponsored claim-dividends measures ~289 gas; cast-vote
  ;; is a similar small insert. 1500 = ~5x headroom, far under the 150k tx ceiling.
  ;; Implicit per-tx KDA cap = MAX-GAS-PRICE * MAX-GAS-LIMIT = 0.0015 KDA.
  (defconst MAX-GAS-PRICE:decimal 0.000001)
  (defconst MAX-GAS-LIMIT:integer 1500)
  (defconst MAX-TX-CALLS:integer 1)      ; one allowlisted top-level call per sponsored tx
  (defconst MAX-TX-COST:decimal (* MAX-GAS-PRICE (dec MAX-GAS-LIMIT)))  ; 0.0015 KDA per tx

  ;; ---- On-chain AGGREGATE sponsorship bound ----
  ;; A per-EPOCH self-imposed sponsorship cap. Every sponsored tx (exec AND cont) charges
  ;; its max cost (MAX-TX-COST) against EPOCH-CAP before the station releases KDA. When the
  ;; epoch's cap is exhausted, sponsorship pauses until the epoch rolls over on BLOCK-TIME.
  ;; Reset is time-based ONLY — an attacker cannot "pay to reset"; a drain burst is bounded
  ;; to EPOCH-CAP KDA and only delays legit gasless users until the next epoch (bounded,
  ;; self-healing). This one bound covers BOTH the whole-balance grief-drain AND the
  ;; arbitrary-defpact cont (a cont still charges the cap, so it cannot exceed it).
  ;; Sized for legit vote/claim volume + headroom; maintainer-tunable via redeploy.
  (defconst EPOCH-CAP:decimal 0.15)      ; KDA sponsored per epoch (= 100 txs at MAX-TX-COST)
  (defconst EPOCH-LEN:integer 86400)     ; epoch length: 24h (seconds)
  (defconst METER-KEY "meter")
  (defconst EPOCH-ZERO:time (time "1970-01-01T00:00:00Z"))

  ;; Per-function allowlist. Each sponsored exec-code string must start with exactly
  ;; one of these (trailing space = whole-token boundary, so a prefix cannot match a
  ;; longer function name). Longest first as a safety belt for prefix containment.
  ;; NOTE: the namespace is hard-coded in each prefix — deploying under a different
  ;; namespace requires updating these + a redeploy.
  (defconst SPONSORED-PREFIXES:[string]
    ;; Derived from the deploy transaction's namespace — no per-network source edit.
    [ (format "({}.smartpacts-shares.cast-vote " [(read-msg 'ns)])
      (format "({}.smartpacts-shares.claim-dividends " [(read-msg 'ns)]) ])

  ;; ========================================================================
  ;; AGGREGATE-BOUND METER
  ;; ========================================================================
  (defschema meter-row
    epoch-start:time             ; block-time this epoch's counting began
    spent:decimal)               ; KDA sponsored so far this epoch
  (deftable meter:{meter-row})

  ;; ========================================================================
  ;; GOVERNANCE / FREEZE
  ;; ========================================================================
  (defcap GOVERNANCE ()
    @doc "Upgrade gate. FROZEN-MODULE=true permanently blocks upgrades."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset ADMIN-KS))

  ;; ========================================================================
  ;; STATION ACCOUNT (user-guard backed principal)
  ;; ========================================================================
  ;; Two ways to satisfy the station guard (Pact 5 has no `guard-any`; we express
  ;; the OR inside one user-guard predicate via enforce-one):
  ;;   (a) gas-payer path — both (coin.GAS) (in scope during a gas buy) and (ALLOW_GAS)
  ;;       (composed by GAS_PAYER only after every check passes) are held; OR
  ;;   (b) admin keyset — so the operator can fund/recover the station out-of-band.
  ;; Anonymous, unmanaged internal token (KIP gas-payer-v1 pattern). NOT public
  ;; authorization: it is composed ONLY by GAS_PAYER, and only after every allowlist
  ;; + ceiling enforce has passed (a weak-body cap composed under a real-checked
  ;; parent is a safe internal token). Required by the station guard.
  (defcap ALLOW_GAS () @doc "internal gas-buy permission token" true)

  (defcap METER ()
    @doc "Internal permission token for charging the per-epoch aggregate meter. Weak body is \
         \nSAFE: composed ONLY by GAS_PAYER (after its tx-type/allowlist/ceiling checks), never \
         \nby a public fn — so charge-epoch runs ONLY on a genuine sponsored gas buy. Without \
         \nthis gate, charge-epoch would be a public defun any actor could call to exhaust the \
         \nepoch cap at ~0 cost and deny gasless service."
    true)

  (defun gas-payer-pred:bool ()
    @doc "Releases the station's KDA inside a sanctioned gas buy."
    (require-capability (GAS))
    (require-capability (ALLOW_GAS)))

  (defun station-guard-pred:bool ()
    @doc "Station coin-account predicate: sanctioned gas buy OR admin keyset."
    (enforce-one "station guard: neither gas-payer nor admin satisfied"
      [ (gas-payer-pred)
        (enforce-keyset ADMIN-KS) ]))

  ;; gas-payer-v1 requires this exact name; it returns the guard a successful
  ;; GAS_PAYER acquisition will satisfy (the gas-payer leg of station-guard-pred).
  (defun create-gas-payer-guard:guard ()
    (create-user-guard (station-guard-pred)))

  ;; Principal bound to the user-guard (consistent with every other internal SPT account).
  (defconst GAS_STATION:string
    (create-principal (create-user-guard (station-guard-pred))))

  ;; ========================================================================
  ;; GAS CEILINGS (inlined — no external dependency)
  ;; ========================================================================
  (defun enforce-below-or-at-gas-price:bool (gas-price:decimal)
    (enforce (<= (at 'gas-price (chain-data)) gas-price)
      (format "Gas price must be <= {}" [gas-price])))

  (defun enforce-below-or-at-gas-limit:bool (gas-limit:integer)
    (enforce (<= (at 'gas-limit (chain-data)) gas-limit)
      (format "Gas limit must be <= {}" [gas-limit])))

  ;; ========================================================================
  ;; ALLOWLIST
  ;; ========================================================================
  (defun allowlisted?:bool (code:string)
    @doc "True iff CODE starts with exactly one sponsored function-call prefix."
    (contains true
      (map (lambda (p:string) (= p (take (length p) code))) SPONSORED-PREFIXES)))

  (defun enforce-allowlisted-call:bool (code:string)
    (enforce (allowlisted? code)
      "Not a sponsored call — gas station funds only SPT vote/claim functions"))

  ;; ========================================================================
  ;; AGGREGATE BOUND — charge the per-epoch cap
  ;; ========================================================================
  (defun charge-epoch:bool ()
    @doc "Charge one tx's max cost against the per-epoch sponsorship cap, rolling the epoch \
         \nover on BLOCK-TIME. Fails closed (no gas paid) once EPOCH-CAP is reached for the \
         \ncurrent epoch. Called by GAS_PAYER before ALLOW_GAS, so it bounds BOTH exec and \
         \ncont sponsorship — one bound covers the whole-balance drain and the arbitrary- \
         \ndefpact cont. The reset is time-only, so no attacker can pay to reset it. \
         \nGated by (require METER) — composed ONLY by GAS_PAYER — so no external actor can call \
         \nthis directly to exhaust the cap and deny gasless service. \
         \nWrites the meter — deliberately NOT inside an enforce (read-only mode forbids DML)."
    (require-capability (METER))
    (let ((now (at 'block-time (chain-data))))
      (with-default-read meter METER-KEY
        { "epoch-start": EPOCH-ZERO, "spent": 0.0 }
        { "epoch-start" := es, "spent" := sp }
        (let* ((rolled (>= (diff-time now es) (dec EPOCH-LEN)))
               (base   (if rolled 0.0 sp))
               (start  (if rolled now es))
               (spent* (+ base MAX-TX-COST)))
          (enforce (<= spent* EPOCH-CAP)
            "gas station epoch cap reached — sponsorship paused until the next epoch")
          (write meter METER-KEY { "epoch-start": start, "spent": spent* })
          true))))

  ;; ========================================================================
  ;; GAS_PAYER — the sponsorship policy (gas-payer-v1)
  ;; ========================================================================
  (defcap GAS_PAYER:bool (user:string limit:integer price:decimal)
    @doc "Sponsor gas iff: an exec of exactly one allowlisted SPT call (or a cont \
         \nadvancing a defpact), within the gas-price/limit ceilings. NOTE: the cap \
         \nargs (user/limit/price) are attacker-controllable and are NOT used as auth \
         \n— the ceilings are checked against the protocol-trusted chain-data envelope."
    ;; tx-type / exec-code are injected by Chainweb from the REAL parsed payload (not
    ;; from tx `data`), so the allowlist binds the actually-executed code. Both are
    ;; always present + correctly typed on the gas-payer path; a missing/ill-typed
    ;; key aborts the tx (fail-closed: no gas paid).
    (let ((tx-type:string (read-msg "tx-type")))
      (enforce (or (= "exec" tx-type) (= "cont" tx-type)) "tx-type must be exec or cont")
      ;; exec carries exec-code we can allowlist; a cont (e.g. a transfer-crosschain or
      ;; report-tally-xchain step 1) has no exec-code — bound it by the gas ceilings only.
      ;; The cont leg funds the cont of ANY defpact — an attacker can self-pay step 0 of
      ;; any defpact then name the station on the cont. This CANNOT be allowlisted by
      ;; code (a cont carries no exec-code, and pact-id proves no identity), so we do
      ;; NOT gate on pact-id. Instead the arbitrary-cont drain is bounded by the
      ;; per-epoch aggregate cap (charge-epoch, below): a cont still charges the cap,
      ;; so it cannot drain past EPOCH-CAP.
      (if (= "exec" tx-type)
        (let ((codes:[string] (read-msg "exec-code")))
          (enforce (= MAX-TX-CALLS (length codes))
            "gas station funds exactly one allowlisted call per tx")
          (enforce-allowlisted-call (at 0 codes)))
        true))
    (enforce-below-or-at-gas-price MAX-GAS-PRICE)
    (enforce-below-or-at-gas-limit MAX-GAS-LIMIT)
    ;; Aggregate bound: charge the per-epoch cap (fails closed when exhausted)
    ;; BEFORE releasing station KDA. Applies to exec AND cont. METER is composed
    ;; here (and nowhere else) so charge-epoch runs ONLY on a genuine sponsored
    ;; gas buy — it is not externally callable.
    (compose-capability (METER))
    (charge-epoch)
    (compose-capability (ALLOW_GAS)))

  ;; ========================================================================
  ;; INIT (per chain): create the station's coin account
  ;; ========================================================================
  (defun init ()
    @doc "Create the station coin account on this chain. Admin tops it up out-of-band. \
         \nGuard = sanctioned gas buy OR admin keyset (admin can fund/recover the station). \
         \nAlso seeds the per-epoch aggregate-bound meter."
    (coin.create-account GAS_STATION (create-gas-payer-guard))
    (insert meter METER-KEY { "epoch-start": EPOCH-ZERO, "spent": 0.0 }))

  (defun get-epoch-spent:decimal ()
    @doc "Read-only: KDA the station has sponsored in the current epoch (ops/monitoring)."
    (at 'spent (read meter METER-KEY)))
)

;; Deploy footer. On a FRESH deploy create the meter table and the station
;; coin account; on an UPGRADE (tx data upgrade: true) skip both — re-running
;; create-table for an existing table aborts the whole tx.
(if (read-msg 'upgrade)
  ["upgrade"]
  [ (create-table meter)
    (init) ])
