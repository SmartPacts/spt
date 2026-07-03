;; ===========================================================================
;; smartpacts-gas-station — sponsors gas for SPT end-user actions ONLY (gasless UX).
;; Shareholders need no KDA to vote or claim dividends.
;;
;; Sponsored (per-function allowlist, NOT a namespace-wide prefix):
;;   - free.smartpacts-shares.cast-vote               (chain-local vote on EVERY chain — ADR-006;
;;                                             cast-vote-xchain was DELETED with ADR-006)
;;   - free.smartpacts-shares.claim-dividends         (permissionless dividend claim)
;; NOT sponsored: every admin op (fund-dividends, proposals, withdraw-revenue,
;;   sale admin, init/init-supply) — the operator pays its own gas.
;;
;; Pattern: KIP gas-payer-v1. Reviewed prior art (ADR-002): CryptoPascal31
;;   otc-deal-locker, kadena-io kadenaswap, eckoDAO/kaddex gas-station + gas-guards.
;; Architecture: ADR-002. Deployed + funded PER CHAIN (voters/claimers are everywhere).
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
  (defconst ADMIN-KS "n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.spt-admin")   ; shared admin keyset (defined by smartpacts-shares)
  ;; Set true and redeploy to permanently freeze upgrades (sponsorship still works).
  (defconst FROZEN-MODULE false)

  ;; Drain-attack ceilings. SPIKE-3 measured claim-dividends ~= 289 gas; cast-vote is
  ;; a similar small INSERT. 1500 = ~5x headroom, far under the 150k tx ceiling.
  ;; Implicit per-tx KDA cap = MAX-GAS-PRICE * MAX-GAS-LIMIT = 0.0015 KDA (ADR-002 §4).
  (defconst MAX-GAS-PRICE:decimal 0.000001)
  (defconst MAX-GAS-LIMIT:integer 1500)
  (defconst MAX-TX-CALLS:integer 1)      ; one allowlisted top-level call per sponsored tx
  (defconst MAX-TX-COST:decimal (* MAX-GAS-PRICE (dec MAX-GAS-LIMIT)))  ; 0.0015 KDA per tx

  ;; ---- F-03/F-04 on-chain AGGREGATE bound (ADR-002 §4a, re-classified 2026-07-01) ----
  ;; A per-EPOCH self-imposed sponsorship cap. Every sponsored tx (exec AND cont) charges
  ;; its max cost (MAX-TX-COST) against EPOCH-CAP before the station releases KDA. When the
  ;; epoch's cap is exhausted, sponsorship pauses until the epoch rolls over on BLOCK-TIME.
  ;; Reset is time-based ONLY — an attacker cannot "pay to reset"; a drain burst is bounded
  ;; to EPOCH-CAP KDA and only delays legit gasless users until the next epoch (bounded,
  ;; self-healing). This is the CODE bound that closes BOTH F-04 (whole-balance grief-drain)
  ;; AND F-03 (cont funds ANY defpact — a cont still charges the cap, so it cannot exceed it).
  ;; Sized for legit vote/claim volume + headroom; maintainer-tunable via redeploy.
  (defconst EPOCH-CAP:decimal 0.15)      ; KDA sponsored per epoch (= 100 txs at MAX-TX-COST)
  (defconst EPOCH-LEN:integer 86400)     ; epoch length: 24h (seconds)
  (defconst METER-KEY "meter")
  (defconst EPOCH-ZERO:time (time "1970-01-01T00:00:00Z"))

  ;; Per-function allowlist. Each sponsored exec-code string must start with exactly
  ;; one of these (trailing space = whole-token boundary, so a prefix cannot match a
  ;; longer function name). Longest first as a safety belt for prefix containment.
  ;; NOTE: hard-codes the `free` namespace — a mainnet n_<hash> deploy needs these
  ;; updated + a redeploy (ADR-002 known migration cost).
  (defconst SPONSORED-PREFIXES:[string]
    [ "(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.cast-vote "
      "(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.claim-dividends " ])

  ;; ========================================================================
  ;; AGGREGATE-BOUND METER (F-03/F-04)
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
  ;; + ceiling enforce has passed (pact-traps: a weak-body cap composed under a
  ;; real-checked parent is a safe internal token). Required by the station guard.
  (defcap ALLOW_GAS () @doc "internal gas-buy permission token" true)

  (defcap METER ()
    @doc "Internal permission token for charging the per-epoch aggregate meter. Weak body is \
         \nSAFE: composed ONLY by GAS_PAYER (after its tx-type/allowlist/ceiling checks), never \
         \nby a public fn — so charge-epoch runs ONLY on a genuine sponsored gas buy. Without \
         \nthis gate, charge-epoch would be a public defun any actor could call to exhaust the \
         \nepoch cap at ~0 cost and deny gasless service (auditor Finding 2)."
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
  ;; GAS CEILINGS (inlined from eckoDAO gas-guards — ADR-002 YAGNI: no external dep)
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
  ;; AGGREGATE BOUND — charge the per-epoch cap (F-03/F-04)
  ;; ========================================================================
  (defun charge-epoch:bool ()
    @doc "Charge one tx's max cost against the per-epoch sponsorship cap, rolling the epoch \
         \nover on BLOCK-TIME. Fails closed (no gas paid) once EPOCH-CAP is reached for the \
         \ncurrent epoch. Called by GAS_PAYER before ALLOW_GAS, so it bounds BOTH exec and \
         \ncont sponsorship — closing F-04 (whole-balance drain) and F-03 (arbitrary-defpact \
         \ncont) with one bound. The reset is time-only, so no attacker can pay to reset it. \
         \nGated by (require METER) — composed ONLY by GAS_PAYER — so no external actor can call \
         \nthis directly to exhaust the cap and deny gasless service (auditor Finding 2 fix). \
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
    ;; always present + correctly typed on the gas-payer path (canonical kadenaswap/
    ;; kaddex assumption); a missing/ill-typed key aborts the tx (fail-closed: no gas paid).
    (let ((tx-type:string (read-msg "tx-type")))
      (enforce (or (= "exec" tx-type) (= "cont" tx-type)) "tx-type must be exec or cont")
      ;; exec carries exec-code we can allowlist; a cont (e.g. a transfer-crosschain or
      ;; report-tally-xchain step 1) has no exec-code — bound it by the gas ceilings only.
      ;; F-03 (ADR-002 §5): the cont leg funds the cont of ANY defpact — an attacker can
      ;; self-pay step 0 of any defpact then name the station on the cont. Re-derived
      ;; 2026-07-01: this CANNOT be allowlisted by code (a cont carries no exec-code, and
      ;; pact-id proves no identity — unsafe per pact-traps), so we do NOT gate on pact-id.
      ;; Instead the arbitrary-cont drain is bounded — together with F-04 — by the per-epoch
      ;; aggregate cap (charge-epoch, below): a cont still charges the cap, so it cannot
      ;; drain past EPOCH-CAP. F-03 is therefore BOUNDED, not accepted.
      (if (= "exec" tx-type)
        (let ((codes:[string] (read-msg "exec-code")))
          (enforce (= MAX-TX-CALLS (length codes))
            "gas station funds exactly one allowlisted call per tx")
          (enforce-allowlisted-call (at 0 codes)))
        true))
    (enforce-below-or-at-gas-price MAX-GAS-PRICE)
    (enforce-below-or-at-gas-limit MAX-GAS-LIMIT)
    ;; F-03/F-04 on-chain aggregate bound: charge the per-epoch cap (fails closed when
    ;; exhausted) BEFORE releasing station KDA. Applies to exec AND cont. METER is composed
    ;; here (and nowhere else) so charge-epoch runs ONLY on a genuine sponsored gas buy —
    ;; it is not externally callable (auditor Finding 2).
    (compose-capability (METER))
    (charge-epoch)
    (compose-capability (ALLOW_GAS)))

  ;; ========================================================================
  ;; INIT (per chain): create the station's coin account
  ;; ========================================================================
  (defun init ()
    @doc "Create the station coin account on this chain. Admin tops it up out-of-band. \
         \nGuard = sanctioned gas buy OR admin keyset (admin can fund/recover the station). \
         \nAlso seeds the per-epoch aggregate-bound meter (F-03/F-04)."
    (coin.create-account GAS_STATION (create-gas-payer-guard))
    (insert meter METER-KEY { "epoch-start": EPOCH-ZERO, "spent": 0.0 }))

  (defun get-epoch-spent:decimal ()
    @doc "Read-only: KDA the station has sponsored in the current epoch (ops/monitoring)."
    (at 'spent (read meter METER-KEY)))
)

(create-table meter)

(if (read-msg 'upgrade)
  ["upgrade"]
  [ (init) ])
