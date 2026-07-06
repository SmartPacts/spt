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
;; smartpacts-shares — Smart Pacts Token (SPT)
;; Equity share token: fungible-v2 + fungible-xchain-v1, inlined float-base
;; dividends (MasterChef accumulator, per-leg checkpoint), live chain-local
;; governance, capability-guarded internal accounts, pre-committed tranche
;; time-locks (founder/treasury/liquidity), on-chain revenue routing.
;; ===========================================================================
(namespace (read-msg 'ns))
(define-keyset (read-msg 'spt-admin-name) (read-keyset 'spt-admin))

(module smartpacts-shares GOVERNANCE
  @doc "SPT equity token: fungible-v2 + fungible-xchain-v1 with float-base dividends, \
       \ncapability-guarded reserve/revenue/dividend accounts, and pre-committed tranche \
       \ntime-locks (founder/treasury/liquidity)."

  (implements fungible-v2)
  (implements fungible-xchain-v1)

  ;; ========================================================================
  ;; SCHEMAS / TABLES
  ;; ========================================================================
  (defschema spt-account
    @doc "SPT holder account + inlined dividend accounting (MasterChef). Governance is LIVE: \
         \nvote weight = current balance; a transfer releases the moved shares' vote from the \
         \ntally (see debit). No per-account voting field is needed — recorded votes live in \
         \nthe account-votes table keyed by (account,chain,proposal)."
    balance:decimal
    guard:guard
    reward-debt:decimal          ; rps already accounted for this account
    pending-dividends:decimal)   ; crystallized at last checkpoint
  (deftable accounts:{spt-account})

  ;; ========================================================================
  ;; GOVERNANCE STATE (live-vote, chain-local)
  ;; ========================================================================
  (defschema proposal
    @doc "A governance proposal. CHAIN-LOCAL voting: admin replicates the SAME \
         \nproposal (identical id/created-at/duration => identical close-at) to EVERY chain; \
         \neach chain tallies its own shares' votes and freezes at close-at. The canonical \
         \nfinal result is aggregated on the hub post-close (final-aggs)."
    title:string
    description:string
    created-at:time
    close-at:time
    status:string                ; "active" | "closed" | "cancelled"
    active-slot:integer)         ; its slot in the active-proposal index (0 = not indexed)
  (deftable proposals:{proposal})

  ;; account-votes: how many of an account's shares are CURRENTLY voting on a proposal, + dir.
  ;; Key = (hash [chain account proposal]). Adjusted live: cast-vote sets it to current balance;
  ;; a debit releases min(debited, voted) from it (and the tally). Chain-bound so cross-chain
  ;; votes from the same account on different chains are distinct rows.
  (defschema account-vote weight:decimal direction:bool)
  (deftable account-votes:{account-vote})

  ;; vote-delegates: an OPTIONAL dedicated voting key per account, so the
  ;; transfer key can live in cold storage. Registered/replaced/cleared ONLY by the
  ;; account's MAIN guard; consumed ONLY by the VOTE cap (main guard OR vote key).
  ;; Per-chain rows, like votes (chain-local governance).
  (defschema vote-delegate guard:guard active:bool)
  (deftable vote-delegates:{vote-delegate})     ; key = account

  ;; THIS chain's running tally per proposal (every chain tallies its own shares).
  ;; Kept in sync live with every cast-vote, re-vote, and transfer-release,
  ;; so get-results is O(1). Frozen at close-at; aggregated post-close via final-aggs.
  (defschema tally yes:decimal no:decimal)
  (deftable tallies:{tally})

  ;; active-proposal index: the small set the transfer release-loop iterates. Admin-created
  ;; (create-proposal), so its size is governance cadence — NEVER attacker-inflatable.
  (defschema prop-idx id:string)
  (deftable prop-index:{prop-idx})     ; key = integer index as string
  (defschema prop-count-row n:integer)
  (deftable prop-count:{prop-count-row})

  ;; post-close on-chain aggregation (hub rows): one frozen per-chain report
  ;; per (proposal, chain) — idempotent by insert — plus the running hub aggregate.
  ;; The canonical final result is COMPLETE only when all 20 chains have reported.
  (defschema final-report yes:decimal no:decimal)
  (deftable final-reports:{final-report})   ; key = (hash [proposal chain])
  (defschema final-agg yes:decimal no:decimal reported:integer)
  (deftable final-aggs:{final-agg})         ; key = proposal id

  (defschema state-schema
    @doc "Singleton dividend + supply state for THIS chain. reward-per-share is the GLOBAL \
         \nreward-per-share materialized on this chain: the sum of the rates of every dividend \
         \nround already applied here, IDENTICAL on every chain once all effective rounds are \
         \napplied. It is NOT a per-chain accumulator — the declared-round list is the source \
         \nof truth and this field is its O(1) materialization."
    reward-per-share:decimal     ; = Σ rate of applied rounds (global)
    circulating-supply:decimal   ; participating balances on this chain (rps denominator)
    ipo-reserve-account:string   ; excluded principal (smartpacts-ipo reserve), stored at init
    rounds-applied:integer       ; how many declared rounds have been folded into rps here
    total-distributed:decimal    ; KDA moved revenue->pool on this chain (solvency bookkeeping)
    ;; EXACT SOLVENCY (O(1)): the chain's true unclaimed liability is
    ;;   L = sum-pending + rps*circulating - sum-debt
    ;; = Σ over non-excluded accounts of (pending + balance*(rps - reward-debt)).
    ;; circulating*rps ALONE under-counts L: when a share leaves a chain its earned
    ;; dividend stays claimable here as crystallized pending, but circulating drops.
    ;; These two counters, maintained on every debit/credit/claim, make fund-dividends
    ;; enforce pool >= L exactly — so "funded" is a hard guarantee every claim is payable.
    sum-pending:decimal          ; Σ pending-dividends over non-excluded accounts (crystallized owed)
    sum-debt:decimal)            ; Σ (balance * reward-debt) over non-excluded accounts
  (deftable state:{state-schema})

  ;; DIVIDEND ROUNDS. A round is DECLARED once by admin and replicated to EVERY chain
  ;; with identical params (rate + effective-at) — exactly like create-proposal
  ;; replicates an identical close-at. The GLOBAL reward-per-share is Σ rate over all
  ;; rounds whose effective-at <= now; because every chain holds the same round list and
  ;; reads the same consensus block-time, that value is identical everywhere BY
  ;; CONSTRUCTION — no per-chain drift, so a share moving between chains is never
  ;; mis-paid. Rounds are indexed 1..n (like the active-proposal index) so apply-round
  ;; can fold them in order without scanning. Immutable once declared.
  (defschema dividend-round rate:decimal effective-at:time)
  (deftable dividend-rounds:{dividend-round})   ; key = round id (integer as string)
  (defschema round-count-row n:integer)
  (deftable round-count:{round-count-row})      ; singleton: how many rounds declared here
  ;; apply-round fold accumulator: the last consecutive-effective prefix index + its summed rate.
  (defschema apply-acc i:integer rate:decimal)

  (defschema tranche-lock
    @doc "One pre-committed, time-gated tranche: founder | treasury | liquidity. \
         \nThe SCHEDULE (cliff-end/vest-end) derives from SOURCE constants at init-supply — \
         \nnever admin data. The beneficiary (a k:/w: principal, squat-proof) is fixed at the \
         \ninit ceremony. release-tranche is permissionless: linear from cliff, floor-12, the \
         \nfinal claim tops to exactly total. Nothing can accelerate, delay, revoke, redirect."
    beneficiary:string
    guard:guard
    total:decimal
    released:decimal
    cliff-end:time
    vest-end:time)
  (deftable tranche-locks:{tranche-lock})

  (defschema init-schema initialized:bool)
  (deftable init-state:{init-schema})

  ;; ========================================================================
  ;; CONSTANTS
  ;; ========================================================================
  ;; Token identity — self-documentation readable via describe-module. No wallet
  ;; or explorer consumes these today; they exist so the deployed module names
  ;; itself forever, and as the natural hook if the ecosystem adopts a metadata
  ;; standard. Decimals are already discoverable via the fungible-v2 (precision)
  ;; function / MINIMUM-PRECISION (12).
  (defconst NAME:string "Smart Pacts Token")
  (defconst SYMBOL:string "SPT")
  (defconst TOTAL-SUPPLY 100000.0)
  ;; ---- Tranche allocation + release calendar ----
  ;; THE CALENDAR IS SOURCE, NOT DATA: init-supply stamps T = its block-time once; every
  ;; cliff/vest bound is T + these constants. After FROZEN-MODULE nothing can alter it.
  (defconst IPO-TRANCHE 20000.0)
  (defconst FOUNDER-TRANCHE 10000.0)
  (defconst TREASURY-TRANCHE 55000.0)
  (defconst LIQUIDITY-TRANCHE 15000.0)
  (defconst FOUNDER-CLIFF-DAYS 365)    (defconst FOUNDER-VEST-DAYS 1460)   ; 12mo cliff -> 4y
  (defconst TREASURY-CLIFF-DAYS 365)   (defconst TREASURY-VEST-DAYS 1825)  ; 12mo cliff -> 5y
  (defconst LIQUIDITY-CLIFF-DAYS 90)   (defconst LIQUIDITY-VEST-DAYS 730)  ; 3mo cliff -> 2y
  (defconst TRANCHE-FOUNDER "founder")
  (defconst TRANCHE-TREASURY "treasury")
  (defconst TRANCHE-LIQUIDITY "liquidity")
  (defconst MINIMUM-PRECISION 12)
  (defconst STATE-KEY "state")
  (defconst INIT-KEY "init")
  (defconst PROP-COUNT-KEY "pc")               ; active-proposal-index counter singleton key
  (defconst ROUND-COUNT-KEY "rc")              ; dividend-round counter singleton key
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))  ; sentinel (missing-proposal default)
  ;; The admin keyset name is DERIVED from the deploy transaction's namespace —
  ;; no per-network source edit, no substitution step at deploy time.
  (defconst ADMIN-KS (format "{}.spt-admin" [(read-msg 'ns)]))
  ;; Governance
  (defconst QUORUM 4000.0)                      ; 4% of total supply
  (defconst MIN-PROPOSAL-DURATION 259200)       ; 72 hours (seconds)
  (defconst MAX-PROPOSAL-DURATION 1209600)      ; 14 days (seconds)
  ;; Set true and redeploy to permanently freeze upgrades (operations continue).
  (defconst FROZEN-MODULE false)

  ;; ========================================================================
  ;; EVENTS
  ;; ========================================================================
  (defcap ROUND-DECLARED (id:string rate:decimal effective-at:time) @event true)
  (defcap ROUND-APPLIED (id:string chain:string rate:decimal) @event true)
  (defcap DIVIDEND-FUNDED (amount:decimal) @event true)   ; per-chain cash into the pool
  (defcap DIVIDEND-CLAIMED (account:string amount:decimal) @event true)
  (defcap REVENUE-RECEIVED (from:string amount:decimal) @event true)
  (defcap REVENUE-WITHDRAWN (to:string amount:decimal) @event true)
  ;; Tranche time-locks. TRANCHE-LOCKED (at init) is the public disclosure
  ;; anchor: it carries the full schedule of each tranche on-chain.
  (defcap TRANCHE-LOCKED (tranche:string beneficiary:string total:decimal cliff-end:time vest-end:time) @event true)
  (defcap TRANCHE-RELEASED (tranche:string beneficiary:string amount:decimal released-total:decimal) @event true)
  ;; Governance events
  (defcap PROPOSAL-CREATED (id:string title:string) @event true)
  ;; `key` = (create-principal guard): indexers can tell WHICH key was granted
  ;; (audit trail for stealth-registration detection).
  (defcap VOTE-KEY-SET (account:string key:string) @event true)
  (defcap VOTE-KEY-CLEARED (account:string) @event true)
  (defcap VOTE-CAST (voter:string proposal:string weight:decimal direction:bool) @event true)
  (defcap VOTE-RELEASED (voter:string proposal:string amount:decimal) @event true)
  (defcap PROPOSAL-CLOSED (id:string status:string) @event true)
  (defcap TALLY-REPORTED (proposal:string chain:string yes:decimal no:decimal) @event true)

  ;; ========================================================================
  ;; INTERNAL ACCOUNT GUARDS (capability-guarded; module-owned)
  ;; ========================================================================
  (defcap TREASURY-GUARD () @doc "guards the treasury SPT reserve (time-locked)" true)
  (defcap FUNDERS-GUARD () @doc "guards the founder SPT reserve (time-locked)" true)
  (defcap LIQUIDITY-GUARD () @doc "guards the market/liquidity SPT reserve (time-locked)" true)
  (defcap REVENUE-GUARD () @doc "guards the KDA revenue account" true)
  (defcap POOL-GUARD () @doc "guards the KDA dividend pool account" true)

  (defconst TREASURY-G  (create-capability-guard (TREASURY-GUARD)))
  (defconst FUNDERS-G   (create-capability-guard (FUNDERS-GUARD)))
  (defconst LIQUIDITY-G (create-capability-guard (LIQUIDITY-GUARD)))
  (defconst REVENUE-G   (create-capability-guard (REVENUE-GUARD)))
  (defconst POOL-G      (create-capability-guard (POOL-GUARD)))

  (defconst TREASURY-ACCOUNT  (create-principal TREASURY-G))
  (defconst FUNDERS-ACCOUNT   (create-principal FUNDERS-G))
  (defconst LIQUIDITY-ACCOUNT (create-principal LIQUIDITY-G))
  (defconst REVENUE-ACCOUNT   (create-principal REVENUE-G))
  (defconst POOL-ACCOUNT      (create-principal POOL-G))

  ;; ========================================================================
  ;; GOVERNANCE / ADMIN
  ;; ========================================================================
  (defcap GOVERNANCE ()
    @doc "Upgrade gate. FROZEN-MODULE=true permanently blocks upgrades."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset ADMIN-KS))

  (defcap ADMIN () @doc "admin operations gate" (enforce-keyset ADMIN-KS))

  (defcap VOTE-KEY-ADMIN (account:string)
    @doc "Owner gate for vote-key registration/clearing. A defcap — not a bare \
         \ndefun guard — so wallets can SCOPE the signature to exactly this action \
         \n(an unscoped signature could otherwise be spent on a stealth registration)."
    (enforce-guard (account-guard account)))

  (defcap ROTATE (account:string)
    @doc "Owner gate for guard rotation — a defcap so wallets can scope the \
         \nsignature to exactly this action (parity with VOTE-KEY-ADMIN)."
    (enforce-guard (account-guard account)))

  (defcap VOTE (voter:string)
    @doc "Authorizes a voter: the account's MAIN guard OR, if registered + active, the \
         \naccount's dedicated VOTING KEY (hot key votes, transfer key stays in the \
         \nvault). Reads are let-bound BEFORE the enforce-one (a table read inside an \
         \nenforce condition trips read-only mode on the node); the main guard is listed \
         \nFIRST, so a registration can never lock the owner out. Only cast-vote acquires \
         \nthis cap; every other privilege stays on the main guard."
    (let ((main (account-guard voter)))
      (with-default-read vote-delegates voter
        { "guard": main, "active": false }
        { "guard" := vg, "active" := act }
        (enforce-one "neither account guard nor registered vote key satisfied"
          [ (enforce-guard main)
            (if act (enforce-guard vg) (enforce false "no vote key registered")) ]))))

  ;; ========================================================================
  ;; TRANSFER CAPABILITIES (fungible-v2 + fungible-xchain-v1)
  ;; ========================================================================
  (defcap DEBIT (sender:string)
    @doc "Authorizes debiting sender — enforces sender's guard."
    (enforce-guard (account-guard sender)))

  (defcap CREDIT (receiver:string) @doc "internal credit token" true)

  (defcap TALLY ()
    @doc "Internal permission token for writing the proposal tally / account-votes. Weak body \
         \nis SAFE: composed ONLY under cast-vote (VOTE-gated) or under a debit/credit release \
         \n(DEBIT/CREDIT-gated under a real TRANSFER) — never by a public fn directly. Mirrors the \
         \nCREDIT-under-DEBIT internal-token pattern; require-capability ties every tally write to \
         \na vote or a share movement."
    true)

  (defcap AGGREGATE ()
    @doc "Internal permission token for recording a chain's FROZEN tally into the hub \
         \naggregate. Weak body is SAFE: acquired ONLY inside report-tally-hub (which reads the \
         \nREAL local tally in the same call) and report-tally-xchain step 1 (whose resume payload \
         \nis SPV-authenticated as produced by OUR step 0 reading the REAL source tally — yes/no/ \
         \nchain carry no user input). require-capability makes record-final-tally uncallable with \
         \nattacker-chosen numbers; the report paths themselves are deliberately permissionless."
    true)

  (defcap TRANSFER:bool (sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "sender and receiver must differ")
    (enforce (> amount 0.0) "transfer amount must be positive")
    (enforce-unit amount)
    (compose-capability (DEBIT sender))
    (compose-capability (CREDIT receiver)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    (let ((remainder (- managed requested)))
      (enforce (>= remainder 0.0)
        (format "TRANSFER exceeded: {} requested of {} managed" [requested managed]))
      remainder))

  (defcap TRANSFER_XCHAIN:bool (sender:string receiver:string amount:decimal target-chain:string)
    @managed amount TRANSFER_XCHAIN-mgr
    (enforce (> amount 0.0) "cross-chain amount must be positive")
    (enforce-unit amount)
    (enforce (!= "" target-chain) "empty target-chain")
    (enforce (!= (at 'chain-id (chain-data)) target-chain) "cannot xchain to same chain")
    (compose-capability (DEBIT sender)))

  (defun TRANSFER_XCHAIN-mgr:decimal (managed:decimal requested:decimal)
    (enforce (>= managed requested) "cross-chain transfer exceeds installed amount")
    0.0) ; one-shot

  (defcap TRANSFER_XCHAIN_RECD:bool
    (sender:string receiver:string amount:decimal source-chain:string)
    @event true)

  (defcap FUND-DIVIDENDS () @doc "admin: fund a dividend round" (enforce-keyset ADMIN-KS))

  ;; ========================================================================
  ;; HELPERS
  ;; ========================================================================
  (defun curr-time:time () (at 'block-time (chain-data)))
  (defun this-chain:string () (at 'chain-id (chain-data)))
  (defun account-guard:guard (account:string) (at 'guard (read accounts account)))
  (defun get-round-count:integer () (at 'n (read round-count ROUND-COUNT-KEY)))

  ;; get-rps = the GLOBAL reward-per-share right now: the already-folded rps PLUS the
  ;; rates of any DECLARED rounds that are effective-at <= now but not yet folded here.
  ;; PURE READ (no writes) — safe to call from debit/credit/claim. This is what makes rps
  ;; identical on every chain the instant a round is declared+effective, without requiring
  ;; apply-round to have run first: the value is derived from the (identically-replicated)
  ;; round list + consensus block-time, so drift is impossible. apply-round only MATERIALIZES
  ;; it for O(1) reads; correctness does not depend on apply-round having been called.
  (defun get-rps:decimal ()
    (with-read state STATE-KEY { "reward-per-share" := folded, "rounds-applied" := applied }
      (let* ((n (get-round-count))
             (now (curr-time))
             (pending (if (>= applied n) []
                        (filter (!= 0.0)
                          (map (lambda (i:integer)
                                 (with-read dividend-rounds (rkey i)
                                   { "rate" := rate, "effective-at" := eff }
                                   (if (<= eff now) rate 0.0)))
                               (enumerate (+ applied 1) n))))))
        (fold (+) folded pending))))
  (defun get-circulating:decimal () (at 'circulating-supply (read state STATE-KEY)))

  ;; Exact solvency: this chain's TRUE unclaimed dividend liability, O(1).
  ;;   L = sum-pending + rps*circulating - sum-debt
  ;;     = Σ over non-excluded accounts of (pending + balance*(rps - reward-debt)).
  ;; This is what fund-dividends must cover — circulating*rps alone under-counts it by
  ;; the crystallized pending of shares that have since left the chain.
  (defun dividend-liability:decimal ()
    (with-read state STATE-KEY
      { "sum-pending" := sp, "circulating-supply" := circ, "sum-debt" := sd }
      (+ sp (- (* (get-rps) circ) sd))))
  (defun get-ipo-reserve:string () (at 'ipo-reserve-account (read state STATE-KEY)))
  (defun get-prop-count:integer () (at 'n (read prop-count PROP-COUNT-KEY)))

  (defun precision:integer () MINIMUM-PRECISION)

  (defun enforce-unit:bool (amount:decimal)
    (enforce (= (floor amount MINIMUM-PRECISION) amount) "amount violates minimum precision"))

  (defun validate-account (account:string)
    (enforce (and (>= (length account) 3) (<= (length account) 256)) "account name length 3..256")
    (enforce (is-charset CHARSET_LATIN1 account) "account name has invalid characters"))

  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "Principal accounts (k:/w:/c:/…) must match their guard (coin pattern)."
    (if (is-principal account)
      (enforce (validate-principal guard account)
        (format "Reserved protocol guard violation: {}" [account]))
      true))

  (defun excluded?:bool (account:string)
    @doc "Treasury + founder reserve + liquidity reserve + (unsold) IPO reserve are NOT in \
         \nthe float: they neither accrue dividends nor count toward circulating-supply \
         \n(and governance rejects their votes)."
    (or (= account TREASURY-ACCOUNT)
      (or (= account FUNDERS-ACCOUNT)
        (or (= account LIQUIDITY-ACCOUNT)
            (= account (get-ipo-reserve))))))

  ;; ========================================================================
  ;; GOVERNANCE — LIVE VOTE, CHAIN-LOCAL
  ;; ------------------------------------------------------------------------
  ;; Vote weight = the voter's CURRENT shares. Re-vote updates in place. A transfer
  ;; RELEASES the voted portion of the moved shares from the tally (in debit, below),
  ;; so no share backs two live votes. Dust cannot suppress: receiving never removes
  ;; shares. Every chain runs this same machinery over its own replica of each
  ;; proposal; votes never cross chains.
  ;; ========================================================================
  (defun vkey:string (voter:string chain:string proposal:string)
    ;; STRUCTURED hash (not a ':'-joined string) — account names legally contain ':'
    ;; (k:/w:/c: principals), so a formatted key is ambiguous; hashing the list keeps
    ;; element boundaries so distinct triples never collide.
    (hash [voter chain proposal]))
  (defun pkey:string (i:integer) (int-to-str 10 i))
  (defun rkey:string (i:integer) (int-to-str 10 i))   ; dividend-round key
  (defun active-prop-indices:[integer] ()
    @doc "Indices [1..count] of the active-proposal index, or [] at count 0 (guards the \
         \n(enumerate 1 0) => [1 0] trap)."
    (let ((n (get-prop-count))) (if (= n 0) [] (enumerate 1 n))))

  (defun apply-tally:string (proposal:string dw:decimal direction:bool)
    @doc "Add dw (may be negative, for a release) to the proposal's yes/no tally. PRIVATE \
         \n(require TALLY): only cast-vote and the debit release path call it, so every tally \
         \nchange is tied to a vote or a share movement in the same tx (rolls back on abort)."
    (require-capability (TALLY))
    (with-read tallies proposal { "yes" := y, "no" := n }
      (if direction (update tallies proposal { "yes": (+ y dw) })
                    (update tallies proposal { "no":  (+ n dw) })))
    "tallied")

  (defun proposal-active?:bool (proposal:string)
    @doc "A proposal is active for TALLY purposes iff status==active AND the voting deadline has \
         \nnot passed. The close-at check FREEZES the tally at the deadline: once \
         \nvoting is closed, a later transfer no longer releases votes / mutates the tally, so \
         \nget-results returns the final tally even before the admin's close-proposal tx lands."
    (with-default-read proposals proposal { "status": "", "close-at": EPOCH }
      { "status" := st, "close-at" := cl }
      (and (= st "active") (< (curr-time) cl))))

  ;; ---- release a debited account's live votes proportionally out of the tally ----
  (defun release-votes-on-debit:string (account:string amount:decimal)
    @doc "On a debit of `amount` from `account`, release min(amount, voted) from each active \
         \nproposal this account is voting on (subtract from the account-vote AND the tally). \
         \nPRIVATE (require TALLY). Iterates only the ACTIVE-proposal index (admin-created, \
         \nbounded by governance cadence — NOT attacker-inflatable). CHAIN-LOCAL: proposals \
         \nare replicated to every chain, so this fires on EVERY chain — including the step-0 \
         \ndebit of transfer-crosschain, which is what makes a cross-chain double-count \
         \nimpossible: voted shares leave this chain's tally the moment they are debited."
    (require-capability (TALLY))
    (let ((chain (this-chain)))
      (map (lambda (i:integer)
             (let* ((p (at 'id (read prop-index (pkey i))))
                    (k (vkey account chain p)))
               (if (proposal-active? p)
                 (with-default-read account-votes k { "weight": 0.0, "direction": true }
                   { "weight" := w, "direction" := d }
                   (if (> w 0.0)
                     (let ((release (if (> amount w) w amount)))
                       (update account-votes k { "weight": (- w release) })
                       (apply-tally p (* -1.0 release) d)
                       (emit-event (VOTE-RELEASED account p release)))
                     "no-vote"))
                 "inactive")))
        (active-prop-indices)))
    "released")

  ;; ========================================================================
  ;; PROPOSALS (admin) + VOTING (public)
  ;; ========================================================================
  (defun create-proposal:string
    (id:string title:string description:string created-at:time duration-seconds:integer)
    (with-capability (ADMIN)
      ;; CHAIN-LOCAL voting: admin submits this SAME payload to EVERY chain.
      ;; created-at is EXPLICIT (not block-time) so close-at is identical on all chains —
      ;; the per-chain tally freeze (proposal-active?) is one shared timestamp, not a tx.
      (enforce (>= duration-seconds MIN-PROPOSAL-DURATION) "duration below 72h minimum")
      (enforce (<= duration-seconds MAX-PROPOSAL-DURATION) "duration above 14d maximum")
      (enforce (<= created-at (curr-time)) "created-at cannot be in the future")
      (let ((close-at (add-time created-at duration-seconds))
            (slot (+ (get-prop-count) 1)))
        ;; A replica announced after its own close-at is useless AND would be a suppression
        ;; hazard if it could still be zero-reported — reject it outright (fail closed; a
        ;; chain the admin missed keeps the aggregation incomplete, never wrong).
        (enforce (< (curr-time) close-at) "close-at already passed on this chain")
        ;; INSERT the proposal FIRST — it fails on a duplicate id, BEFORE any index write,
        ;; so a rejected duplicate never bumps the count / dirties the index. Then append
        ;; to the active index; the slot is stored on the proposal for O(1) swap-and-pop removal at
        ;; close/cancel, so the transfer release-loop only ever scans the CURRENTLY-active
        ;; set (bounded by 72h..14d duration + cadence), NOT the ever-growing history.
        (insert proposals id
          { "title": title, "description": description, "created-at": created-at
          , "close-at": close-at, "status": "active", "active-slot": slot })
        (insert tallies id { "yes": 0.0, "no": 0.0 })
        (write prop-index (pkey slot) { "id": id })
        (update prop-count PROP-COUNT-KEY { "n": slot }))
      (emit-event (PROPOSAL-CREATED id title))
      "proposal created"))

  (defun deindex-proposal:string (id:string slot:integer)
    @doc "Swap-and-pop the proposal at `slot` out of the active-proposal index (called by \
         \nclose/cancel). Moves the LAST active entry into `slot` (updating that moved \
         \nproposal's active-slot) and decrements the count — so the release-loop only ever \
         \niterates the live set. PRIVATE (require ADMIN — close/cancel are admin-gated)."
    (require-capability (ADMIN))
    (let ((n (get-prop-count)))
      (if (and (> n 0) (> slot 0))
        (let ((last-id (at 'id (read prop-index (pkey n)))))
          (if (!= slot n)                                  ; move last into the freed slot
            (let ((_ 0))
              (write prop-index (pkey slot) { "id": last-id })
              (update proposals last-id { "active-slot": slot }))
            "")
          (update prop-count PROP-COUNT-KEY { "n": (- n 1) })  ; pop the tail
          "deindexed")
        "empty")))

  ;; ---- dedicated voting key (hot key votes; transfer key stays cold) ----
  (defun set-vote-key:string (account:string guard:guard)
    @doc "Register/replace the account's dedicated voting guard. MAIN account guard only \
         \n(via VOTE-KEY-ADMIN — scope your signature to it) — the hot key can never \
         \nrotate itself. Per-chain (register where your shares live). The vote key can \
         \nONLY vote: transfers, rotation, dividends destination, and this registration \
         \nall remain with the main guard. Use a plain keyset (or keyset-ref) for the \
         \nvote key — a user guard whose predicate reads module tables can fail at vote time."
    (with-capability (VOTE-KEY-ADMIN account)
      (write vote-delegates account { "guard": guard, "active": true })
      (emit-event (VOTE-KEY-SET account (create-principal guard))))
    "vote key set")

  (defun clear-vote-key:string (account:string)
    @doc "Deactivate the account's voting key (MAIN guard via VOTE-KEY-ADMIN). Requires \
         \na prior registration; voting falls back to the main guard alone."
    (with-capability (VOTE-KEY-ADMIN account)
      (update vote-delegates account { "active": false })
      (emit-event (VOTE-KEY-CLEARED account)))
    "vote key cleared")

  (defun get-vote-key:object{vote-delegate} (account:string)
    @doc "Read-only: the account's vote-key registration ({guard, active}); inactive \
         \nmain-guard default when never registered."
    (with-default-read vote-delegates account
      { "guard": (account-guard account), "active": false }
      { "guard" := g, "active" := a }
      { "guard": g, "active": a }))

  (defun cast-vote:string (voter:string proposal:string direction:bool)
    @doc "LIVE vote on THIS chain (chain-local): weight = voter's CURRENT shares on \
         \nthis chain, into this chain's tally. Votable on every chain once the replica is \
         \nannounced. Re-vote updates in place. Excluded reserves cannot vote. Auth = main \
         \nguard OR the registered voting key (see VOTE)."
    (with-capability (VOTE voter)
      (with-read proposals proposal { "close-at" := cl, "status" := st }
        (enforce (= st "active") "proposal not active")
        (enforce (< (curr-time) cl) "voting closed")
        ;; Bind the read to a let FIRST — a table read inside an enforce
        ;; condition trips read-only mode on the node.
        (let ((is-excluded (excluded? voter)))
          (enforce (not is-excluded) "excluded reserve cannot vote"))
        (record-live-vote voter (this-chain) proposal direction (get-balance voter)))))

  (defun record-live-vote:string (voter:string chain:string proposal:string direction:bool weight:decimal)
    @doc "Shared vote-recording. Sets this (voter,chain,proposal) recorded vote to `weight` \
         \n(100% current shares), adjusting the tally by the delta from any prior vote (re-vote). \
         \nPRIVATE: the CALLER (cast-vote) authenticates the voter via VOTE = guard check. It \
         \nacquires TALLY itself for the writes. chain is always (this-chain)."
    (require-capability (VOTE voter))       ; caller must have authenticated the voter
    (enforce (> weight 0.0) "no voting weight")
    (enforce-unit weight)
    (with-default-read account-votes (vkey voter chain proposal)
      { "weight": 0.0, "direction": direction } { "weight" := oldw, "direction" := oldd }
      (with-capability (TALLY)
        (if (> oldw 0.0) (apply-tally proposal (* -1.0 oldw) oldd) "")   ; remove old (re-vote)
        (apply-tally proposal weight direction))                          ; add current
      (write account-votes (vkey voter chain proposal) { "weight": weight, "direction": direction }))
    (emit-event (VOTE-CAST voter proposal weight direction))
    "vote cast")

  (defun close-proposal:string (id:string)
    (with-capability (ADMIN)
      (with-read proposals id { "status" := st, "active-slot" := slot }
        (enforce (= st "active") "only active can close")
        (deindex-proposal id slot))                        ; remove from the release-loop set
      (update proposals id { "status": "closed", "active-slot": 0 })
      (emit-event (PROPOSAL-CLOSED id "closed"))
      "proposal closed"))

  (defun cancel-proposal:string (id:string)
    (with-capability (ADMIN)
      (with-read proposals id { "status" := st, "active-slot" := slot }
        (enforce (= st "active") "only active can cancel")
        (deindex-proposal id slot))
      (update proposals id { "status": "cancelled", "active-slot": 0 })
      (emit-event (PROPOSAL-CLOSED id "cancelled"))
      "proposal cancelled"))

  ;; ---- results (THIS chain's advisory running view — the canonical cross-chain
  ;; result is get-final-results on the hub after post-close reporting; per-chain
  ;; quorum-met/passed are meaningful only on the complete aggregate) ----
  (defschema results yes:decimal no:decimal participation:decimal quorum-met:bool passed:bool)
  (defun results-of:object{results} (yes:decimal no:decimal)
    (let ((participation (+ yes no)))
      { "yes": yes, "no": no, "participation": participation
      , "quorum-met": (>= participation QUORUM)
      , "passed": (and (>= participation QUORUM) (> yes no)) }))
  (defun get-results:object{results} (proposal:string)
    (with-read tallies proposal { "yes" := yes, "no" := no } (results-of yes no)))
  (defun get-vote:object{account-vote} (voter:string chain:string proposal:string)
    (read account-votes (vkey voter chain proposal)))
  (defun vote-weight:decimal (voter:string chain:string proposal:string)
    @doc "Recorded live vote weight for (voter,chain,proposal); 0 if none. Read-only."
    (with-default-read account-votes (vkey voter chain proposal)
      { "weight": 0.0 } { "weight" := w } w))
  (defun proposal-details:object{proposal} (id:string) (read proposals id))

  ;; ========================================================================
  ;; READS (fungible-v2 + getters)
  ;; ========================================================================
  (defun get-balance:decimal (account:string)
    (at 'balance (read accounts account)))

  (defun details:object{fungible-v2.account-details} (account:string)
    (with-read accounts account { "balance" := bal, "guard" := g }
      { "account": account, "balance": bal, "guard": g }))

  (defun get-guard:guard (account:string) (account-guard account))

  (defun pending-dividends-of:decimal (account:string)
    @doc "Live unclaimed dividends. Excluded accounts always 0."
    (if (excluded? account)
      0.0
      (with-default-read accounts account
        { "balance": 0.0, "reward-debt": 0.0, "pending-dividends": 0.0 }
        { "balance" := bal, "reward-debt" := rd, "pending-dividends" := pend }
        (+ pend (* bal (- (get-rps) rd))))))

  ;; ========================================================================
  ;; DEBIT / CREDIT (per-leg float checkpoint inlined)
  ;; ========================================================================
  (defun debit (account:string amount:decimal)
    (require-capability (DEBIT account))
    (enforce (> amount 0.0) "debit amount must be positive")
    (enforce-unit amount)
    (let ((rps (get-rps)))
      (with-read accounts account
        { "balance" := bal, "reward-debt" := rd, "pending-dividends" := pend }
        (enforce (<= amount bal) "insufficient funds")
        (if (excluded? account)
          ;; excluded reserves can never vote (governance rejects them) => no vote release.
          (update accounts account { "balance": (- bal amount) })
          (let ((new-pend (+ pend (* bal (- rps rd)))))
            ;; LIVE-VOTE: release the voted portion of the moved shares from the
            ;; tally BEFORE the balance drops, so no share backs two live votes on transfer.
            (with-capability (TALLY) (release-votes-on-debit account amount))
            (update accounts account
              { "balance": (- bal amount), "reward-debt": rps, "pending-dividends": new-pend })
            ;; Exact solvency counters (this account's contribution changes):
            ;;   sum-pending += new-pend - pend      = bal*(rps-rd)
            ;;   sum-debt    += (bal-amount)*rps - bal*rd   (reward-debt: rd->rps, balance: bal->bal-amount)
            (with-read state STATE-KEY
              { "circulating-supply" := circ, "sum-pending" := sp, "sum-debt" := sd }
              (update state STATE-KEY
                { "circulating-supply": (- circ amount)
                , "sum-pending": (+ sp (* bal (- rps rd)))
                , "sum-debt": (+ sd (- (* (- bal amount) rps) (* bal rd))) })))))))

  (defun credit (account:string guard:guard amount:decimal)
    (require-capability (CREDIT account))
    (enforce (> amount 0.0) "credit amount must be positive")
    (enforce-unit amount)
    (let ((rps (get-rps)))
      (with-default-read accounts account
        { "balance": -1.0, "guard": guard
        , "reward-debt": rps, "pending-dividends": 0.0 }
        { "balance" := bal, "guard" := retg, "reward-debt" := rd, "pending-dividends" := pend }
        (enforce (= retg guard) "account guards do not match")
        (let* ((is-new (= bal -1.0))
               (cur-bal (if is-new 0.0 bal)))
          (if is-new (enforce-reserved account guard) true)
          ;; LIVE-VOTE: credited shares are PLAIN (unvoted) — the receiver may vote them.
          ;; A credit never affects the receiver's existing recorded vote (dust cannot suppress).
          (if (excluded? account)
            (write accounts account
              { "balance": (+ cur-bal amount), "guard": retg
              , "reward-debt": rd, "pending-dividends": pend })
            (let ((new-pend (+ pend (* cur-bal (- rps rd)))))
              (write accounts account
                { "balance": (+ cur-bal amount), "guard": retg
                , "reward-debt": rps, "pending-dividends": new-pend })
              ;; Exact solvency counters (mirror of debit; cur-bal may be 0 for a new acct):
              ;;   sum-pending += cur-bal*(rps-rd)
              ;;   sum-debt    += (cur-bal+amount)*rps - cur-bal*rd
              (with-read state STATE-KEY
                { "circulating-supply" := circ, "sum-pending" := sp, "sum-debt" := sd }
                (update state STATE-KEY
                  { "circulating-supply": (+ circ amount)
                  , "sum-pending": (+ sp (* cur-bal (- rps rd)))
                  , "sum-debt": (+ sd (- (* (+ cur-bal amount) rps) (* cur-bal rd))) }))))))))

  ;; ========================================================================
  ;; fungible-v2 TRANSFER SURFACE
  ;; ========================================================================
  (defun transfer:string (sender:string receiver:string amount:decimal)
    (enforce (!= sender receiver) "sender and receiver must differ")
    (enforce (> amount 0.0) "transfer amount must be positive")
    (enforce-unit amount)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (with-read accounts receiver { "guard" := g }
        (credit receiver g amount)))
    "transfer ok")

  (defun transfer-create:string (sender:string receiver:string receiver-guard:guard amount:decimal)
    (enforce (!= sender receiver) "sender and receiver must differ")
    (enforce (> amount 0.0) "transfer amount must be positive")
    (enforce-unit amount)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (credit receiver receiver-guard amount))
    "transfer-create ok")

  (defun create-account:string (account:string guard:guard)
    (validate-account account)
    (enforce-reserved account guard)
    (insert accounts account
      { "balance": 0.0, "guard": guard
      , "reward-debt": (get-rps), "pending-dividends": 0.0 })
    "account created")

  (defun rotate:string (account:string new-guard:guard)
    (with-capability (ROTATE account)
      ;; A principal account (k:/w:/c:/…) must stay bound to its name — only a
      ;; vanity account may rotate freely, or a principal back to a matching guard.
      ;; Mirrors coin.rotate; without this the principal⟺guard invariant that
      ;; enforce-reserved establishes at create/first-credit could silently drift.
      (enforce (or (not (is-principal account)) (validate-principal new-guard account))
        "It is unsafe for principal accounts to rotate their guard")
      (update accounts account { "guard": new-guard })
      ;; Key-compromise hygiene: rotating the main guard REVOKES
      ;; any active vote key — recovery from a stolen key must not leave the thief's
      ;; delegate alive to keep re-voting the balance.
      (with-default-read vote-delegates account { "active": false } { "active" := act }
        (if act
          (let ((_ (update vote-delegates account { "active": false })))
            (emit-event (VOTE-KEY-CLEARED account))
            "vote key revoked")
          "no vote key")))
    "guard rotated")

  ;; ========================================================================
  ;; fungible-xchain-v1 — transfer-crosschain (2-step SPV defpact)
  ;; ========================================================================
  (defpact transfer-crosschain:string
    (sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (step
      (with-capability (TRANSFER_XCHAIN sender receiver amount target-chain)
        (validate-account sender)
        (validate-account receiver)
        (enforce (> amount 0.0) "cross-chain amount must be positive")
        (enforce-unit amount)
        (debit sender amount)
        (emit-event (TRANSFER sender "" amount))
        (yield
          { "receiver": receiver, "receiver-guard": receiver-guard
          , "amount": amount, "source-chain": (at 'chain-id (chain-data)) }
          target-chain)))
    (step
      (resume
        { "receiver" := receiver, "receiver-guard" := rg
        , "amount" := amount, "source-chain" := source-chain }
        (emit-event (TRANSFER "" receiver amount))
        (with-capability (CREDIT receiver)
          (credit receiver rg amount))
        (emit-event (TRANSFER_XCHAIN_RECD "" receiver amount source-chain))
        "cross-chain credit ok")))

  ;; ========================================================================
  ;; POST-CLOSE ON-CHAIN AGGREGATION. Votes NEVER cross chains — there is no
  ;; cross-chain vote defpact (every chain votes its own shares via cast-vote,
  ;; and the step-0 debit of a cross-chain transfer releases locally like any
  ;; debit). What DOES cross chains, once per (proposal, chain) and only AFTER
  ;; close-at (tally frozen => timing-independent), is each chain's FINAL tally:
  ;; report-tally-hub records chain 0's own numbers; report-tally-xchain (2-step
  ;; SPV defpact) carries chains 1-19's to the hub. Both are PERMISSIONLESS: the
  ;; payload is module-computed from the frozen tally (no user input), duplicates
  ;; die on the (proposal, chain) insert, and a chain whose replica was never
  ;; announced CANNOT report (fail closed — see create-proposal).
  ;; ========================================================================
  (defun enforce-reportable:time (proposal:string)
    @doc "The local tally is reportable iff the replica EXISTS here (missing replica = \
         \nread failure, so a lagging chain cannot be zero-reported), close-at has passed \
         \n(the tally is frozen and can never change again), and the proposal was not \
         \ncancelled (a cancelled proposal has no result). Returns close-at."
    (with-read proposals proposal { "close-at" := cl, "status" := st }
      (enforce (!= st "cancelled") "cancelled proposal has no result")
      (enforce (>= (curr-time) cl) "voting still open on this chain")
      cl))

  (defun record-final-tally:string (proposal:string chain:string yes:decimal no:decimal)
    @doc "Record one chain's frozen tally into the hub aggregate. PRIVATE (require \
         \nAGGREGATE): only report-tally-hub and report-tally-xchain step 1 reach here, \
         \nso yes/no/chain are always module-read values, never caller input. Idempotent: \
         \na duplicate (proposal, chain) report fails on the insert before the aggregate \
         \nis touched."
    (require-capability (AGGREGATE))
    (enforce-reportable proposal)            ; hub-side defense in depth
    (insert final-reports (hash [proposal chain]) { "yes": yes, "no": no })
    (with-default-read final-aggs proposal
      { "yes": 0.0, "no": 0.0, "reported": 0 }
      { "yes" := ay, "no" := an, "reported" := r }
      (write final-aggs proposal
        { "yes": (+ ay yes), "no": (+ an no), "reported": (+ r 1) }))
    (emit-event (TALLY-REPORTED proposal chain yes no))
    "reported")

  (defun report-tally-hub:string (proposal:string)
    @doc "Permissionless, hub-only: record chain 0's OWN frozen tally into the aggregate."
    (enforce (= (this-chain) "0") "hub tally reports locally; use report-tally-xchain off-hub")
    (enforce-reportable proposal)
    (with-read tallies proposal { "yes" := y, "no" := n }
      (with-capability (AGGREGATE)
        (record-final-tally proposal "0" y n))))

  (defpact report-tally-xchain:string (proposal:string)
    @doc "Permissionless 2-step SPV defpact: carry THIS (non-hub) chain's frozen tally \
         \nto the hub aggregate. Step 0 reads the REAL local tally after close-at; step 1 \
         \nrecords it on the hub."
    (step
      (let ((chain (this-chain)))
        (enforce (!= chain "0") "use report-tally-hub on the hub")
        (enforce-reportable proposal)
        (with-read tallies proposal { "yes" := y, "no" := n }
          (yield { "proposal": proposal, "chain": chain, "yes": y, "no": n } "0"))))
    (step
      (resume { "proposal" := p, "chain" := c, "yes" := y, "no" := n }
        (with-capability (AGGREGATE)
          (record-final-tally p c y n)))))

  ;; ---- canonical final result (hub) ----
  (defschema final-result
    yes:decimal no:decimal participation:decimal quorum-met:bool passed:bool
    complete:bool chains-reported:integer)
  (defun get-final-results:object{final-result} (proposal:string)
    @doc "The aggregated cross-chain result. `complete` (and therefore any possibility of \
         \n`passed` = true) requires ALL chains reported — a partial aggregate can never pass. \
         \nA proposal with no reports yet reads as zeros/incomplete."
    (with-default-read final-aggs proposal
      { "yes": 0.0, "no": 0.0, "reported": 0 }
      { "yes" := y, "no" := n, "reported" := r }
      (let ((total-chains (length coin.VALID_CHAIN_IDS))
            (participation (+ y n)))
        { "yes": y, "no": n, "participation": participation
        , "quorum-met": (>= participation QUORUM)
        , "passed": (and (= r total-chains)
                         (and (>= participation QUORUM) (> y n)))
        , "complete": (= r total-chains), "chains-reported": r })))

  ;; ========================================================================
  ;; INIT (supply creation + per-chain setup)
  ;; ========================================================================
  (defun enforce-not-initialized ()
    (with-default-read init-state INIT-KEY { "initialized": false } { "initialized" := i }
      (enforce (not i) "module already initialized")))

  (defun enforce-beneficiary (beneficiary:string guard:guard)
    @doc "A tranche beneficiary must be a k:/w: PRINCIPAL matching its guard: squat-proof \
         \n(enforce-reserved makes the name unforgeable, so releases can never be bricked) \
         \nand impossible to point at a module-internal c: account by ceremony mistake."
    (validate-account beneficiary)
    (let ((ptype (typeof-principal beneficiary)))
      (enforce (or (= ptype "k:") (= ptype "w:")) "beneficiary must be a k:/w: principal"))
    (enforce (validate-principal guard beneficiary) "beneficiary guard/principal mismatch"))

  (defun lock-tranche:string
    (tranche:string beneficiary:string guard:guard total:decimal t0:time cliff-days:integer vest-days:integer)
    @doc "PRIVATE (require ADMIN — init-supply only): record one tranche lock and \
         \nemit its full schedule as the on-chain disclosure anchor."
    (require-capability (ADMIN))
    (enforce-beneficiary beneficiary guard)
    (let ((cliff-end (add-time t0 (days cliff-days)))
          (vest-end  (add-time t0 (days vest-days))))
      (enforce (< cliff-end vest-end) "cliff must precede vest end")
      (insert tranche-locks tranche
        { "beneficiary": beneficiary, "guard": guard, "total": total
        , "released": 0.0, "cliff-end": cliff-end, "vest-end": vest-end })
      (emit-event (TRANCHE-LOCKED tranche beneficiary total cliff-end vest-end)))
    "tranche locked")

  (defun init-supply:string
    (ipo-reserve-account:string ipo-guard:guard
     founder:string founder-guard:guard
     treasury-ops:string treasury-ops-guard:guard
     liquidity-ops:string liquidity-ops-guard:guard)
    @doc "Chain 0 only, one-time: create state + KDA accounts, mint TOTAL-SUPPLY to the four \
         \nreserves (sum ENFORCED), and create the three tranche locks atomically — \
         \nT (the calendar origin) is THIS tx's block-time; there is no post-init admin window."
    (with-capability (ADMIN)
      (enforce (= (at 'chain-id (chain-data)) "0") "Supply init only on chain 0")
      (enforce-not-initialized)
      (enforce (= TOTAL-SUPPLY
                  (+ IPO-TRANCHE (+ FOUNDER-TRANCHE (+ TREASURY-TRANCHE LIQUIDITY-TRANCHE))))
        "tranche totals do not sum to TOTAL-SUPPLY")
      (insert state STATE-KEY
        { "reward-per-share": 0.0, "circulating-supply": 0.0
        , "ipo-reserve-account": ipo-reserve-account, "rounds-applied": 0
        , "total-distributed": 0.0, "sum-pending": 0.0, "sum-debt": 0.0 })
      (insert prop-count PROP-COUNT-KEY { "n": 0 })       ; active-proposal-index counter
      (insert round-count ROUND-COUNT-KEY { "n": 0 })     ; dividend-round counter
      (coin.create-account REVENUE-ACCOUNT REVENUE-G)
      (coin.create-account POOL-ACCOUNT POOL-G)
      ;; Mint TOTAL-SUPPLY to the (excluded) reserves — inlined (no exported mint surface).
      (with-capability (CREDIT TREASURY-ACCOUNT)  (credit TREASURY-ACCOUNT TREASURY-G TREASURY-TRANCHE))
      (with-capability (CREDIT FUNDERS-ACCOUNT)   (credit FUNDERS-ACCOUNT FUNDERS-G FOUNDER-TRANCHE))
      (with-capability (CREDIT LIQUIDITY-ACCOUNT) (credit LIQUIDITY-ACCOUNT LIQUIDITY-G LIQUIDITY-TRANCHE))
      (with-capability (CREDIT ipo-reserve-account) (credit ipo-reserve-account ipo-guard IPO-TRANCHE))
      ;; Pre-committed release calendar: rows + disclosure events, atomic with the mint.
      (let ((t0 (curr-time)))
        (lock-tranche TRANCHE-FOUNDER founder founder-guard FOUNDER-TRANCHE t0 FOUNDER-CLIFF-DAYS FOUNDER-VEST-DAYS)
        (lock-tranche TRANCHE-TREASURY treasury-ops treasury-ops-guard TREASURY-TRANCHE t0 TREASURY-CLIFF-DAYS TREASURY-VEST-DAYS)
        (lock-tranche TRANCHE-LIQUIDITY liquidity-ops liquidity-ops-guard LIQUIDITY-TRANCHE t0 LIQUIDITY-CLIFF-DAYS LIQUIDITY-VEST-DAYS))
      (insert init-state INIT-KEY { "initialized": true })
      "supply initialized"))

  (defun init:string (ipo-reserve-account:string)
    @doc "Non-chain-0, one-time: create state + KDA accounts. No minting."
    (with-capability (ADMIN)
      (enforce (!= (at 'chain-id (chain-data)) "0") "Use init-supply on chain 0")
      (enforce-not-initialized)
      (insert state STATE-KEY
        { "reward-per-share": 0.0, "circulating-supply": 0.0
        , "ipo-reserve-account": ipo-reserve-account, "rounds-applied": 0
        , "total-distributed": 0.0, "sum-pending": 0.0, "sum-debt": 0.0 })
      (insert prop-count PROP-COUNT-KEY { "n": 0 })       ; active-proposal-index counter
      (insert round-count ROUND-COUNT-KEY { "n": 0 })     ; dividend-round counter
      (coin.create-account REVENUE-ACCOUNT REVENUE-G)
      (coin.create-account POOL-ACCOUNT POOL-G)
      (insert init-state INIT-KEY { "initialized": true })
      "chain initialized"))

  ;; ========================================================================
  ;; DIVIDENDS — GLOBAL ACCRUAL via DECLARED ROUNDS
  ;; ------------------------------------------------------------------------
  ;; A round = a rate (KDA per share) effective at a timestamp, DECLARED once by
  ;; admin and replicated to EVERY chain with identical params (like create-proposal
  ;; replicates identical close-at). The global reward-per-share is Σ rate of effective
  ;; rounds — identical on every chain by construction, so cross-chain share movement is
  ;; never mis-paid. fund-dividends is decoupled: it only ensures a chain's POOL holds
  ;; the KDA to cover its own holders (pure solvency).
  ;; ========================================================================

  ;; declared rounds (chain 0 total, mirrored everywhere) that are effective by `now`
  ;; but not yet folded into this chain's rps.
  (defun outstanding-rate:decimal ()
    @doc "Σ rate of declared rounds effective-at <= now but not yet applied on THIS chain."
    (with-read state STATE-KEY { "reward-per-share" := _folded, "rounds-applied" := applied }
      (let ((n (get-round-count)) (now (curr-time)))
        (if (>= applied n) 0.0
          (fold (+) 0.0
            (map (lambda (i:integer)
                   (with-read dividend-rounds (rkey i) { "rate" := rate, "effective-at" := eff }
                     (if (<= eff now) rate 0.0)))
                 (enumerate (+ applied 1) n)))))))

  (defun declare-round:string (id:string rate:decimal effective-at:time)
    @doc "Admin: DECLARE a dividend round (rate KDA/share, effective at a timestamp), \
         \nreplicated to EVERY chain with these SAME params (id/rate/effective-at). The \
         \nglobal rps rises by `rate` once `effective-at` passes — identically on all \
         \nchains. INSERT by index so the sequence is gap-free and immutable; the id is \
         \nstored for the event/audit trail. Does NOT move KDA (that is fund-dividends). \
         \nA future effective-at is allowed on purpose (declare now, fund each chain to \
         \nliability during the window, rps rises on the date) — but effective-at MUST be \
         \n>= the previous round's, so the index order and time order agree: that makes a \
         \nround effective iff every lower-indexed round is (no gaps), which apply-round \
         \nrelies on to fold+advance the SAME set and never double-count a rate."
    (with-capability (ADMIN)
      (enforce (> rate 0.0) "rate must be positive")
      (enforce-unit rate)
      (let* ((prev (get-round-count))
             (slot (+ prev 1)))
        ;; MONOTONIC effective-at: bind the prior round's timestamp FIRST (a table read
        ;; inside an enforce condition trips read-only mode on the node), then reject an
        ;; out-of-order declaration.
        (if (> prev 0)
          (let ((prev-eff (at 'effective-at (read dividend-rounds (rkey prev)))))
            (enforce (>= effective-at prev-eff)
              "effective-at must be >= the previous round's (declare rounds in time order)"))
          true)
        ;; append the round at the next index; the id lives in the event (rounds are
        ;; index-addressed like the active-proposal index, so apply-round is O(newly-effective)).
        (insert dividend-rounds (rkey slot) { "rate": rate, "effective-at": effective-at })
        (update round-count ROUND-COUNT-KEY { "n": slot }))
      (emit-event (ROUND-DECLARED id rate effective-at))
      "round declared"))

  (defun apply-round:string (id:string)
    @doc "Permissionless: MATERIALIZE the now-effective declared rounds into this chain's \
         \nstored rps, so get-rps stays O(1). Idempotent + monotonic. SELF-CONSISTENT: it \
         \nfolds and advances over the SAME set — the consecutive-effective PREFIX of the \
         \nunapplied rounds — so it can never fold a rate it does not advance past (folding \
         \na wider set than it advances would double-count on the next call). A not-yet- \
         \neffective round stops the prefix; because declare-round enforces non-decreasing \
         \neffective-at, that prefix is exactly the set of effective unapplied rounds. \
         \n`id` is for the event only. No-op-rejects if none."
    (with-read state STATE-KEY { "reward-per-share" := folded, "rounds-applied" := applied }
      (let ((n (get-round-count)) (now (curr-time)))
        ;; guard the empty/descending range: nothing unapplied => reject (no-op) before enumerate.
        (enforce (< applied n) "no newly-effective rounds to apply")
        ;; one pass over unapplied rounds: extend the prefix (and sum its rate) only while
        ;; each next round is CONSECUTIVE and effective. acc = { "i": last-prefix-index, "rate": Σrate }.
        (let* ((acc (fold (lambda (a:object{apply-acc} k:integer)
                            (with-read dividend-rounds (rkey k) { "rate" := rate, "effective-at" := eff }
                              (if (and (= (at 'i a) (- k 1)) (<= eff now))
                                { "i": k, "rate": (+ (at 'rate a) rate) }
                                a)))
                          { "i": applied, "rate": 0.0 }
                          (enumerate (+ applied 1) n)))
               (new-applied (at 'i acc))
               (extra (at 'rate acc)))
          (enforce (> extra 0.0) "no newly-effective rounds to apply")
          (update state STATE-KEY
            { "reward-per-share": (+ folded extra)
            , "rounds-applied": new-applied })
          (emit-event (ROUND-APPLIED id (this-chain) extra))
          "round applied"))))

  (defun fund-dividends:string (pool-amount:decimal)
    @doc "Admin: move pool-amount KDA revenue->pool on THIS chain (pure SOLVENCY — the \
         \nrps is set by declare-round, not here). The chain's pool must be able to cover \
         \nits own holders' claims: pool + deposit >= floor12(dividend-liability). Fundable \
         \nwhen the chain has live float OR a payable stranded liability; only a dead chain \
         \n(neither) is refused. Timing of this call does NOT affect what anyone is OWED — \
         \nonly whether the cash is here; pre-funding ahead of a declared future round is \
         \nlegal, and a chain that grows after funding is topped up with another call."
    (with-capability (FUND-DIVIDENDS)
      (enforce (> pool-amount 0.0) "pool-amount must be positive")
      ;; Bind reads to lets FIRST — a read inside an enforce trips read-only mode on the node.
      (let* ((circ (get-circulating))
             (liability (dividend-liability))
             (fl (floor liability MINIMUM-PRECISION))
             (poolbal (coin.get-balance POOL-ACCOUNT)))
        ;; FUNDABILITY: a chain is fundable when it has live float (circ > 0 — includes
        ;; PRE-funding ahead of a declared future round, the declare-then-rebalance
        ;; pattern) OR a payable stranded liability (fl > 0 — every holder moved out
        ;; cross-chain/to reserves but their crystallized pending remains claimable
        ;; here). Only circ = 0 AND fl = 0 is rejected: a dead chain, where the no-exit
        ;; pool would strand the cash forever.
        (enforce (or (> circ 0.0) (> fl 0.0))
          "nothing fundable: no circulating float and no payable liability on this chain")
        ;; EXACT solvency: after this deposit the pool must cover the chain's TRUE
        ;; unclaimed liability = sum-pending + rps*circulating - sum-debt. This counts the
        ;; crystallized pending of shares that have LEFT the chain (which circulating*rps
        ;; misses), so "fund-dividends succeeded" is a hard guarantee that every claim on
        ;; this chain is payable. Funding timing never changes what is OWED (only whether the
        ;; cash is here); a chain that grows after funding is topped up with another call.
        ;; The bound is the liability FLOORED to coin precision: claims pay 12-decimal floors
        ;; (see claim-dividends), so total payable = Sigma floor(owed_i) <= floor(L) — any
        ;; 12-dp amount <= L is <= floor(L). The sub-1e-12 dust is unpayable by construction
        ;; and re-covered by the next funding once future accrual lifts it past 1e-12.
        (enforce (>= (+ poolbal pool-amount) fl)
          "pool underfunded: pool + deposit must cover this chain's dividend liability"))
      (with-capability (REVENUE-GUARD)
        (install-capability (coin.TRANSFER REVENUE-ACCOUNT POOL-ACCOUNT pool-amount))
        (coin.transfer REVENUE-ACCOUNT POOL-ACCOUNT pool-amount))
      (with-read state STATE-KEY { "total-distributed" := td }
        (update state STATE-KEY { "total-distributed": (+ td pool-amount) }))
      (emit-event (DIVIDEND-FUNDED pool-amount))
      "dividends funded"))

  (defun claim-dividends:decimal (account:string)
    @doc "Permissionless: pay account's accrued dividends in KDA to the holder's \
         \nGUARD-BOUND PRINCIPAL coin account. Paying the raw account name is unsafe: \
         \nanyone can pre-create a vanity coin account of the same name with a foreign \
         \nguard, and coin.credit's guard-equality check would then revert every claim \
         \n(permanent dividend lock-out). create-principal binds the recipient to the \
         \nholder's own guard, which a squatter cannot reproduce — so the claim cannot \
         \nbe blocked. For a k:/w:/c: holder the principal equals their account name."
    (let ((rps (get-rps)))
      (with-read accounts account
        { "balance" := bal, "guard" := g, "reward-debt" := rd, "pending-dividends" := pend }
        ;; The accrual product bal*(rps-rd) can carry up to 24 decimals, but coin refuses any
        ;; transfer finer than 12 — paying the raw value would revert EVERY claim whose owed
        ;; amount is sub-12-decimal, stranding a correctly-owed dividend forever. So pay the
        ;; 12-decimal FLOOR and carry the sub-precision remainder ("dust", < 1e-12) forward as
        ;; pending: nothing is lost, the next round's accrual sweeps it up, and the liability
        ;; identity stays exact (post-claim this account contributes exactly `dust` to L).
        (let* ((raw (if (excluded? account) 0.0 (+ pend (* bal (- rps rd)))))
               (payout (floor raw MINIMUM-PRECISION))
               (dust (- raw payout))
               (recipient (create-principal g)))
          (enforce (> payout 0.0) "nothing to claim")   ; excluded or dust-only => rejected
          (update accounts account { "reward-debt": rps, "pending-dividends": dust })
          ;; Exact solvency: claim pays out the floored liability. Counters:
          ;; sum-pending: pend -> dust (delta = dust - pend); sum-debt += bal*(rps-rd)
          ;; (reward-debt rd->rps, balance unchanged). Net dL = (dust-pend) - bal*(rps-rd)
          ;; = dust - raw = -payout, exactly what left the pool.
          (with-read state STATE-KEY { "sum-pending" := sp, "sum-debt" := sd }
            (update state STATE-KEY
              { "sum-pending": (+ (- sp pend) dust)
              , "sum-debt": (+ sd (* bal (- rps rd))) }))
          (with-capability (POOL-GUARD)
            (install-capability (coin.TRANSFER POOL-ACCOUNT recipient payout))
            (coin.transfer-create POOL-ACCOUNT recipient g payout))
          (emit-event (DIVIDEND-CLAIMED account payout))
          payout))))

  ;; ========================================================================
  ;; REVENUE
  ;; ========================================================================
  (defun receive-revenue:string (from:string amount:decimal)
    @doc "Permissionless: deposit KDA revenue into the module's revenue account."
    (enforce (> amount 0.0) "amount must be positive")
    (coin.transfer from REVENUE-ACCOUNT amount)
    (emit-event (REVENUE-RECEIVED from amount))
    "revenue received")

  (defun withdraw-revenue:string (to:string amount:decimal)
    @doc "Admin: move KDA from revenue to an external account (expenses/investment)."
    (with-capability (ADMIN)
      (enforce (> amount 0.0) "amount must be positive")
      (with-capability (REVENUE-GUARD)
        (install-capability (coin.TRANSFER REVENUE-ACCOUNT to amount))
        (coin.transfer REVENUE-ACCOUNT to amount))
      (emit-event (REVENUE-WITHDRAWN to amount))
      "revenue withdrawn"))

  ;; ========================================================================
  ;; TRANCHE TIME-LOCKS — founder / treasury / liquidity
  ;; Permissionless, pre-committed, linear-from-cliff releases on chain 0 (the
  ;; reserves live where the supply was minted). Released SPT enters the float
  ;; exactly like any credit: counted circulating, dividend-accruing from now
  ;; (no retroactivity — reward-debt = current rps), credited UNVOTED.
  ;; ========================================================================
  (defun tranche-vested:decimal (total:decimal cliff-end:time vest-end:time t:time)
    @doc "Release curve: 0 before cliff-end; linear cliff-end -> vest-end (floor-12 => \
         \nmonotonic, never over-releases); EXACTLY total at/after vest-end (explicit \
         \nbranch — the final claim tops up with no floor dust)."
    (if (< t cliff-end) 0.0
      (if (>= t vest-end) total
        (floor (/ (* total (diff-time t cliff-end)) (diff-time vest-end cliff-end))
               MINIMUM-PRECISION))))

  (defun get-tranche:object{tranche-lock} (tranche:string) (read tranche-locks tranche))

  (defun tranche-releasable:decimal (tranche:string)
    @doc "Read-only: what release-tranche would pay out right now."
    (with-read tranche-locks tranche
      { "total" := tot, "released" := rel, "cliff-end" := ce, "vest-end" := ve }
      (- (tranche-vested tot ce ve (curr-time)) rel)))

  (defun release-tranche:decimal (tranche:string)
    @doc "Permissionless: credit the accrued portion of a locked tranche to its \
         \nceremony-fixed beneficiary. Anyone may trigger; SPT can only land in the \
         \nbeneficiary account; nobody can accelerate, delay, revoke, or redirect."
    (with-read tranche-locks tranche
      { "beneficiary" := ben, "guard" := g, "total" := tot, "released" := rel
      , "cliff-end" := ce, "vest-end" := ve }
      (let ((amount (- (tranche-vested tot ce ve (curr-time)) rel)))
        (enforce (> amount 0.0) "nothing releasable")
        ;; Debit the tranche's own capability-guarded reserve. The reserve guard cap
        ;; must be acquired FIRST so DEBIT's enforce-guard on it is satisfied.
        ;; Dispatch is over the fixed three-row key space — the with-read above
        ;; already rejected anything else.
        (if (= tranche TRANCHE-TREASURY)
          (with-capability (TREASURY-GUARD)
            (with-capability (DEBIT TREASURY-ACCOUNT) (debit TREASURY-ACCOUNT amount)))
          (if (= tranche TRANCHE-FOUNDER)
            (with-capability (FUNDERS-GUARD)
              (with-capability (DEBIT FUNDERS-ACCOUNT) (debit FUNDERS-ACCOUNT amount)))
            (let ((known (enforce (= tranche TRANCHE-LIQUIDITY) "unknown tranche")))
              (with-capability (LIQUIDITY-GUARD)
                (with-capability (DEBIT LIQUIDITY-ACCOUNT) (debit LIQUIDITY-ACCOUNT amount))))))
        (with-capability (CREDIT ben) (credit ben g amount))
        (update tranche-locks tranche { "released": (+ rel amount) })
        (emit-event (TRANCHE-RELEASED tranche ben amount (+ rel amount)))
        amount)))
)

;; Deploy footer. On a FRESH deploy create every table; on an UPGRADE
;; (tx data upgrade: true) skip them — re-running create-table for an
;; existing table aborts the whole tx.
(if (read-msg 'upgrade)
  ["upgrade"]
  [ (create-table accounts)
    (create-table state)
    (create-table tranche-locks)    ; pre-committed tranche time-locks (3 rows, chain 0)
    (create-table init-state)
    (create-table proposals)        ; live-vote governance: per-chain replicas
    (create-table account-votes)    ; per-(chain,account,proposal) live recorded vote
    (create-table vote-delegates)   ; dedicated voting keys (hot key votes, cold key holds)
    (create-table tallies)          ; THIS chain's per-proposal running tally
    (create-table prop-index)       ; active-proposal index (debit release-loop scans it)
    (create-table prop-count)       ; active-proposal-index counter
    (create-table final-reports)    ; post-close per-(proposal,chain) frozen reports (hub)
    (create-table final-aggs)       ; post-close aggregated final result (hub)
    (create-table dividend-rounds)  ; declared dividend rounds (global rps source)
    (create-table round-count)      ; dividend-round counter
  ])
