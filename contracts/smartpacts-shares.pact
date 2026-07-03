;; ===========================================================================
;; smartpacts-shares — Smart Pacts Token (SPT)
;; Equity share token: fungible-v2 + fungible-xchain-v1, inlined FLOAT-base
;; dividends (MasterChef, per-leg checkpoint), capability-guarded internal
;; accounts, funders cliff-vesting, on-chain revenue routing.
;; Architecture: ADR-001. Mechanisms proven in pact/spike (SPIKE-1/2/3).
;; ===========================================================================
(namespace (read-msg 'ns))
(define-keyset (read-msg 'spt-admin-name) (read-keyset 'spt-admin))

(module smartpacts-shares GOVERNANCE
  @doc "SPT equity token: fungible-v2 + fungible-xchain-v1 with float-base dividends, \
       \ncapability-guarded treasury/funders/revenue/dividend accounts, and funders vesting."

  (implements fungible-v2)
  (implements fungible-xchain-v1)

  ;; ========================================================================
  ;; SCHEMAS / TABLES
  ;; ========================================================================
  (defschema spt-account
    @doc "SPT holder account + inlined dividend (MasterChef). Governance is LIVE (ADR-004): \
         \nvote weight = current balance; a transfer releases the moved shares' vote from the \
         \ntally (see debit). No per-account voting field is needed — recorded votes live in \
         \nthe account-votes table keyed by (account,chain,proposal)."
    balance:decimal
    guard:guard
    reward-debt:decimal          ; rps already accounted for this account
    pending-dividends:decimal)   ; crystallized at last checkpoint
  (deftable accounts:{spt-account})

  ;; ========================================================================
  ;; GOVERNANCE STATE (LIVE-VOTE — ADR-004; merged in from the former spt-governance)
  ;; ========================================================================
  (defschema proposal
    @doc "A governance proposal. CHAIN-LOCAL voting (ADR-006): admin replicates the SAME \
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

  ;; THIS chain's running tally per proposal (every chain tallies its own shares —
  ;; ADR-006). Kept in sync live with every cast-vote, re-vote, and transfer-release,
  ;; so get-results is O(1). Frozen at close-at; aggregated post-close via final-aggs.
  (defschema tally yes:decimal no:decimal)
  (deftable tallies:{tally})

  ;; active-proposal index: the small set the transfer release-loop iterates. Admin-created
  ;; (create-proposal), so its size is governance cadence — NEVER attacker-inflatable.
  (defschema prop-idx id:string)
  (deftable prop-index:{prop-idx})     ; key = integer index as string
  (defschema prop-count-row n:integer)
  (deftable prop-count:{prop-count-row})

  ;; post-close on-chain aggregation (ADR-006, hub rows): one frozen per-chain report
  ;; per (proposal, chain) — idempotent by insert — plus the running hub aggregate.
  ;; The canonical final result is COMPLETE only when all 20 chains have reported.
  (defschema final-report yes:decimal no:decimal)
  (deftable final-reports:{final-report})   ; key = (hash [proposal chain])
  (defschema final-agg yes:decimal no:decimal reported:integer)
  (deftable final-aggs:{final-agg})         ; key = proposal id

  (defschema state-schema
    @doc "Singleton dividend + supply state for THIS chain."
    reward-per-share:decimal     ; global accumulator (admin-synced across chains)
    circulating-supply:decimal   ; rps denominator = participating balances on this chain
    ipo-reserve-account:string   ; excluded principal (smartpacts-ipo reserve), stored at init
    total-distributed:decimal)
  (deftable state:{state-schema})

  (defschema funder-allocation
    @doc "Cliff-vesting allocation for one funder."
    guard:guard
    amount:decimal
    release-date:time
    released:bool)
  (deftable funder-allocations:{funder-allocation})

  (defschema init-schema initialized:bool)
  (deftable init-state:{init-schema})

  ;; ========================================================================
  ;; CONSTANTS
  ;; ========================================================================
  (defconst TOTAL-SUPPLY 100000.0)
  (defconst MINIMUM-PRECISION 12)
  (defconst STATE-KEY "state")
  (defconst INIT-KEY "init")
  (defconst PROP-COUNT-KEY "pc")               ; active-proposal-index counter singleton key
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))  ; sentinel (missing-proposal default)
  (defconst ADMIN-KS "n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.spt-admin")
  ;; Governance (ADR-004, merged from spt-governance)
  (defconst QUORUM 4000.0)                      ; 4% of total supply
  (defconst MIN-PROPOSAL-DURATION 259200)       ; 72 hours (seconds)
  (defconst MAX-PROPOSAL-DURATION 1209600)      ; 14 days (seconds)
  ;; Set true and redeploy to permanently freeze upgrades (operations continue).
  (defconst FROZEN-MODULE false)

  ;; ========================================================================
  ;; EVENTS
  ;; ========================================================================
  (defcap DIVIDEND-FUNDED (amount:decimal rps-increment:decimal) @event true)
  (defcap DIVIDEND-CLAIMED (account:string amount:decimal) @event true)
  (defcap REVENUE-RECEIVED (from:string amount:decimal) @event true)
  (defcap REVENUE-WITHDRAWN (to:string amount:decimal) @event true)
  (defcap ALLOCATION-CREATED (account:string amount:decimal release-date:time) @event true)
  (defcap ALLOCATION-RELEASED (account:string amount:decimal) @event true)
  ;; Governance events (ADR-004)
  (defcap PROPOSAL-CREATED (id:string title:string) @event true)
  (defcap VOTE-CAST (voter:string proposal:string weight:decimal direction:bool) @event true)
  (defcap VOTE-RELEASED (voter:string proposal:string amount:decimal) @event true)
  (defcap PROPOSAL-CLOSED (id:string status:string) @event true)
  (defcap TALLY-REPORTED (proposal:string chain:string yes:decimal no:decimal) @event true)

  ;; ========================================================================
  ;; INTERNAL ACCOUNT GUARDS (capability-guarded; module-owned)
  ;; ========================================================================
  (defcap TREASURY-GUARD () @doc "guards the treasury SPT account" true)
  (defcap FUNDERS-GUARD () @doc "guards the funders reserve SPT account" true)
  (defcap REVENUE-GUARD () @doc "guards the KDA revenue account" true)
  (defcap POOL-GUARD () @doc "guards the KDA dividend pool account" true)

  (defconst TREASURY-G (create-capability-guard (TREASURY-GUARD)))
  (defconst FUNDERS-G  (create-capability-guard (FUNDERS-GUARD)))
  (defconst REVENUE-G  (create-capability-guard (REVENUE-GUARD)))
  (defconst POOL-G     (create-capability-guard (POOL-GUARD)))

  (defconst TREASURY-ACCOUNT (create-principal TREASURY-G))
  (defconst FUNDERS-ACCOUNT  (create-principal FUNDERS-G))
  (defconst REVENUE-ACCOUNT  (create-principal REVENUE-G))
  (defconst POOL-ACCOUNT     (create-principal POOL-G))

  ;; ========================================================================
  ;; GOVERNANCE / ADMIN
  ;; ========================================================================
  (defcap GOVERNANCE ()
    @doc "Upgrade gate. FROZEN-MODULE=true permanently blocks upgrades."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset ADMIN-KS))

  (defcap ADMIN () @doc "admin operations gate" (enforce-keyset ADMIN-KS))

  (defcap VOTE (voter:string)
    @doc "Authorizes a voter — enforces the voter's account guard (cast-vote auth)."
    (enforce-guard (account-guard voter)))

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
    @doc "Internal permission token for recording a chain's FROZEN tally into the hub aggregate \
         \n(ADR-006). Weak body is SAFE: acquired ONLY inside report-tally-hub (which reads the \
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
  (defun get-rps:decimal () (at 'reward-per-share (read state STATE-KEY)))
  (defun get-circulating:decimal () (at 'circulating-supply (read state STATE-KEY)))
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
    @doc "Treasury + funders reserve + (unsold) IPO reserve are NOT in the float: \
         \nthey neither accrue dividends nor count toward circulating-supply."
    (or (= account TREASURY-ACCOUNT)
      (or (= account FUNDERS-ACCOUNT)
          (= account (get-ipo-reserve)))))

  ;; ========================================================================
  ;; GOVERNANCE — LIVE-VOTE (ADR-004; merged from spt-governance)
  ;; ------------------------------------------------------------------------
  ;; Vote weight = the voter's CURRENT shares. Re-vote updates in place. A transfer
  ;; RELEASES the voted portion of the moved shares from the tally (in debit, below),
  ;; so no share backs two live votes. Dust cannot suppress: receiving never removes
  ;; shares. Proven (dust, transfer-then-revote, re-vote, Σ votes ≤ circulating) in
  ;; pact/spike/vgrief/spike-live-vote.repl. CHAIN-LOCAL (ADR-006): every chain runs
  ;; this same machinery over its own replica of each proposal; votes never cross
  ;; chains (cross-chain accounting proven in spike-chain-local-vote.repl + devnet).
  ;; ========================================================================
  (defun vkey:string (voter:string chain:string proposal:string)
    ;; STRUCTURED hash (not a ':'-joined string) — account names legally contain ':'
    ;; (k:/w:/c: principals), so a formatted key is ambiguous; hashing the list keeps
    ;; element boundaries so distinct triples never collide.
    (hash [voter chain proposal]))
  (defun pkey:string (i:integer) (int-to-str 10 i))
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
         \nnot passed. The close-at check FREEZES the tally at the deadline (auditor F#1): once \
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
         \nbounded by governance cadence — NOT attacker-inflatable). CHAIN-LOCAL (ADR-006): \
         \nproposals are replicated to every chain, so this fires on EVERY chain — including \
         \nthe step-0 debit of transfer-crosschain, which is what closes the F#2 cross-chain \
         \ndouble-count: voted shares leave this chain's tally the moment they are debited."
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
      ;; CHAIN-LOCAL voting (ADR-006): admin submits this SAME payload to EVERY chain.
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
        ;; so a rejected duplicate never bumps the count / dirties the index (also robust to
        ;; the REPL's no-rollback-on-expect-failure artifact). Then append to the active
        ;; index; the slot is stored on the proposal for O(1) swap-and-pop removal at
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

  (defun cast-vote:string (voter:string proposal:string direction:bool)
    @doc "LIVE vote on THIS chain (ADR-006 chain-local): weight = voter's CURRENT shares on \
         \nthis chain, into this chain's tally. Votable on every chain once the replica is \
         \nannounced. Re-vote updates in place. Excluded reserves cannot vote."
    (with-capability (VOTE voter)
      (with-read proposals proposal { "close-at" := cl, "status" := st }
        (enforce (= st "active") "proposal not active")
        (enforce (< (curr-time) cl) "voting closed")
        ;; Bind the read to a let FIRST — a table read inside an enforce condition
        ;; trips read-only mode on the KDA-CE node (devnet-caught; the REPL allows
        ;; it, so REPL green is NOT evidence here — same fix as fund-dividends).
        (let ((is-excluded (excluded? voter)))
          (enforce (not is-excluded) "excluded reserve cannot vote"))
        (record-live-vote voter (this-chain) proposal direction (get-balance voter)))))

  (defun record-live-vote:string (voter:string chain:string proposal:string direction:bool weight:decimal)
    @doc "Shared vote-recording. Sets this (voter,chain,proposal) recorded vote to `weight` \
         \n(100% current shares), adjusting the tally by the delta from any prior vote (re-vote). \
         \nPRIVATE: the CALLER (cast-vote) authenticates the voter via VOTE = guard check. It \
         \nacquires TALLY itself for the writes. chain is always (this-chain) — ADR-006."
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

  ;; ---- results (THIS chain's advisory running view — ADR-006: the canonical
  ;; cross-chain result is get-final-results on the hub after post-close reporting;
  ;; per-chain quorum-met/passed are meaningful only on the complete aggregate) ----
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
            ;; LIVE-VOTE (ADR-004): release the voted portion of the moved shares from the
            ;; tally BEFORE the balance drops, so no share backs two live votes on transfer.
            (with-capability (TALLY) (release-votes-on-debit account amount))
            (update accounts account
              { "balance": (- bal amount), "reward-debt": rps, "pending-dividends": new-pend })
            (update state STATE-KEY { "circulating-supply": (- (get-circulating) amount) }))))))

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
              (update state STATE-KEY { "circulating-supply": (+ (get-circulating) amount) })))))))

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
    (with-read accounts account { "guard" := old-guard }
      (enforce-guard old-guard)
      ;; A principal account (k:/w:/c:/…) must stay bound to its name — only a
      ;; vanity account may rotate freely, or a principal back to a matching guard.
      ;; Mirrors coin.rotate; without this the principal⟺guard invariant that
      ;; enforce-reserved establishes at create/first-credit could silently drift.
      (enforce (or (not (is-principal account)) (validate-principal new-guard account))
        "It is unsafe for principal accounts to rotate their guard")
      (update accounts account { "guard": new-guard }))
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
  ;; POST-CLOSE ON-CHAIN AGGREGATION (ADR-006). Votes NEVER cross chains — there is
  ;; no cross-chain vote defpact (cast-vote-xchain was DELETED with ADR-006; every
  ;; chain votes its own shares via cast-vote, and the step-0 debit of a cross-chain
  ;; transfer releases locally like any debit). What DOES cross chains, once per
  ;; (proposal, chain) and only AFTER close-at (tally frozen => timing-independent),
  ;; is each chain's FINAL tally: report-tally-hub records chain 0's own numbers;
  ;; report-tally-xchain (2-step SPV defpact) carries chains 1-19's to the hub. Both
  ;; are PERMISSIONLESS: the payload is module-computed from the frozen tally (no
  ;; user input), duplicates die on the (proposal, chain) insert, and a chain whose
  ;; replica was never announced CANNOT report (fail closed — see create-proposal).
  ;; The SPV transport itself is VALIDATED ON DEVNET (never REPL).
  ;; ========================================================================
  (defun enforce-reportable:time (proposal:string)
    @doc "The local tally is reportable iff the replica EXISTS here (missing replica = \
         \nread failure, so a lagging chain cannot be zero-reported), close-at has passed \
         \n(the tally is frozen and can never change again), and the proposal was not \
         \ncancelled (a cancelled proposal has no result — auditor F2). Returns close-at."
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
         \nrecords it on the hub. DEVNET-validated (SPV is not REPL-testable)."
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
         \nA proposal with no reports yet reads as zeros/incomplete (auditor F1)."
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

  (defun init-supply:string (ipo-reserve-account:string ipo-guard:guard)
    @doc "Chain 0 only, one-time: create state + KDA accounts, mint 100k SPT to reserves."
    (with-capability (ADMIN)
      (enforce (= (at 'chain-id (chain-data)) "0") "Supply init only on chain 0")
      (enforce-not-initialized)
      (insert state STATE-KEY
        { "reward-per-share": 0.0, "circulating-supply": 0.0
        , "ipo-reserve-account": ipo-reserve-account, "total-distributed": 0.0 })
      (insert prop-count PROP-COUNT-KEY { "n": 0 })       ; active-proposal-index counter
      (coin.create-account REVENUE-ACCOUNT REVENUE-G)
      (coin.create-account POOL-ACCOUNT POOL-G)
      ;; Mint the full 100k to the (excluded) reserves — inlined (no exported mint surface).
      (with-capability (CREDIT TREASURY-ACCOUNT) (credit TREASURY-ACCOUNT TREASURY-G 75000.0))
      (with-capability (CREDIT FUNDERS-ACCOUNT)  (credit FUNDERS-ACCOUNT FUNDERS-G 5000.0))
      (with-capability (CREDIT ipo-reserve-account) (credit ipo-reserve-account ipo-guard 20000.0))
      (insert init-state INIT-KEY { "initialized": true })
      "supply initialized"))

  (defun init:string (ipo-reserve-account:string)
    @doc "Non-chain-0, one-time: create state + KDA accounts. No minting."
    (with-capability (ADMIN)
      (enforce (!= (at 'chain-id (chain-data)) "0") "Use init-supply on chain 0")
      (enforce-not-initialized)
      (insert state STATE-KEY
        { "reward-per-share": 0.0, "circulating-supply": 0.0
        , "ipo-reserve-account": ipo-reserve-account, "total-distributed": 0.0 })
      (insert prop-count PROP-COUNT-KEY { "n": 0 })       ; active-proposal-index counter
      (coin.create-account REVENUE-ACCOUNT REVENUE-G)
      (coin.create-account POOL-ACCOUNT POOL-G)
      (insert init-state INIT-KEY { "initialized": true })
      "chain initialized"))

  ;; ========================================================================
  ;; DIVIDENDS (float base; admin-synced global rps)
  ;; ========================================================================
  (defun fund-dividends:string (pool-amount:decimal rps-increment:decimal)
    @doc "Admin: move pool-amount KDA revenue->pool on THIS chain and bump the \
         \nadmin-computed GLOBAL rps increment (= global-amount / global-circulating)."
    (with-capability (FUND-DIVIDENDS)
      (enforce (> pool-amount 0.0) "pool-amount must be positive")
      (enforce (> rps-increment 0.0) "rps-increment must be positive")
      ;; SOLVENCY: this chain's pool must cover this chain's accrual from the bump
      ;; (= circulating * rps-increment). With correct admin math (rps-increment =
      ;; global-amount/global-circulating, pool-amount = local share) this holds with
      ;; equality; the check rejects admin error/malice that would strand late claimers.
      ;; Bind the read to a let FIRST — a read inside an enforce condition trips
      ;; read-only mode on KDA-CE.
      (let ((circ (get-circulating)))
        ;; ADR-001: funding requires positive circulating float. Without this,
        ;; the solvency bound below degenerates to (>= pool-amount 0.0) at circ=0,
        ;; so funding would succeed and strand KDA in the pool unclaimably.
        (enforce (> circ 0.0) "no circulating float")
        (enforce (>= pool-amount (* circ rps-increment))
          "pool underfunded: pool-amount must cover circulating * rps-increment"))
      (with-capability (REVENUE-GUARD)
        (install-capability (coin.TRANSFER REVENUE-ACCOUNT POOL-ACCOUNT pool-amount))
        (coin.transfer REVENUE-ACCOUNT POOL-ACCOUNT pool-amount))
      (with-read state STATE-KEY { "reward-per-share" := rps, "total-distributed" := td }
        (update state STATE-KEY
          { "reward-per-share": (+ rps rps-increment)
          , "total-distributed": (+ td pool-amount) }))
      (emit-event (DIVIDEND-FUNDED pool-amount rps-increment))
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
        (let ((payout (if (excluded? account) 0.0 (+ pend (* bal (- rps rd)))))
              (recipient (create-principal g)))
          (enforce (> payout 0.0) "nothing to claim")
          (update accounts account { "reward-debt": rps, "pending-dividends": 0.0 })
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
  ;; FUNDERS (cliff vesting)
  ;; ========================================================================
  (defun create-funder-allocation:string
    (account:string guard:guard amount:decimal release-date:time)
    @doc "Admin: reserve SPT from the funders pool into a cliff-vesting allocation."
    (with-capability (ADMIN)
      (enforce (> amount 0.0) "amount must be positive")
      ;; FUNDERS-ACCOUNT is capability-guarded — acquire its guard cap so DEBIT's
      ;; enforce-guard (on the capability guard) is satisfied.
      (with-capability (FUNDERS-GUARD)
        (with-capability (DEBIT FUNDERS-ACCOUNT) (debit FUNDERS-ACCOUNT amount)))
      (insert funder-allocations account
        { "guard": guard, "amount": amount, "release-date": release-date, "released": false })
      (emit-event (ALLOCATION-CREATED account amount release-date))
      "allocation created"))

  (defun release-allocation:string (account:string)
    @doc "Permissionless after release-date: credit the funder's SPT (enters float)."
    (with-read funder-allocations account
      { "guard" := g, "amount" := amt, "release-date" := rd, "released" := rel }
      (enforce (not rel) "allocation already released")
      (enforce (>= (curr-time) rd) "not yet releasable")
      (update funder-allocations account { "released": true })
      (with-capability (CREDIT account) (credit account g amt))
      (emit-event (ALLOCATION-RELEASED account amt))
      "allocation released"))
)

(create-table accounts)
(create-table state)
(create-table funder-allocations)
(create-table init-state)
(create-table proposals)        ; LIVE-VOTE governance (ADR-006): per-chain replicas
(create-table account-votes)    ; per-(chain,account,proposal) live recorded vote
(create-table tallies)          ; THIS chain's per-proposal running tally
(create-table prop-index)       ; active-proposal index (debit release-loop scans it)
(create-table prop-count)       ; active-proposal-index counter
(create-table final-reports)    ; post-close per-(proposal,chain) frozen reports (hub)
(create-table final-aggs)       ; post-close aggregated final result (hub)
