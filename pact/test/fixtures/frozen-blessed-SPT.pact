;; ============================================================================================
;; SPT — ANNOTATED SOURCE. THIS IS NOT THE FILE THAT IS DEPLOYED.
;;
;; The deployed payload is `deploy-bytes/SPT.pact`, which is this file with every `;;` comment
;; removed. Both carry module hash
;;     cg8sInne-rg-JM2L1H2rcppXqBGE8NUIyBdB275RTP0
;; because a Pact module hash excludes `;;` comments — so the annotations below are provably
;; absent from the program that runs, and the program that runs is provably the one reviewed.
;; `VERIFY.md` shows how to check that yourself rather than take it on trust.
;; ============================================================================================
;; SPT — Smart Pacts Token (SPT).
;; Fixed-supply fungible-v2 + fungible-xchain-v1 token. Holders earn a pro-rata portion of KDA
;; funding, vote on proposals, and the founder/treasury/liquidity reserves unlock on a calendar
;; fixed at init. Balances, votes and awards are all PER CHAIN; nothing on chain sums them.
(namespace (read-msg 'ns))

;; ---- AN UPGRADE MUST NOT TOUCH THE ADMIN KEYSETS ----------------------------------------
;; 🔴 A module re-runs its whole top level on EVERY upgrade, and `define-keyset` only requires
;; the INCOMING payload to satisfy the EXISTING keyset — so a payload that satisfies itself is
;; accepted and PERMANENTLY WIDENS admin authority. Measured: an upgrade signed by one admin
;; key, carrying a second key at `keys-any`, is accepted, and the added key alone then drives
;; `withdraw-funding`. On mainnet the tier is `keys-2` of 3, so a pasted predicate silently
;; drops the multisig threshold, and after the freeze the widened keyset governs every admin
;; entry point that survives.
;; ASSERTING THE KEYSET NAME IS NOT A FIX — the attack uses the CORRECT name with a widened
;; payload. The defect is that the definition re-runs at all, so it is gated on the `upgrade`
;; flag: a FRESH deploy defines the keysets, an UPGRADE cannot. Rotation stays possible as a
;; standalone, separately signed transaction — the one admin remedy that survives the freeze.
;;
;; 🔴 THERE IS NO `keys-1` PREDICATE IN PACT — the natives are keys-all / keys-2 / keys-any,
;; and 1-of-N is spelled `keys-any`. `keys-1` parses as a CUSTOM predicate naming a function
;; that does not exist, and the failure mode is the dangerous one: `define-keyset` ACCEPTS it
;; and it fails only later, at the first `enforce-keyset`. A `keys-1` ops tier deploys clean
;; and bricks every ops operation on a FROZEN module.
(enforce (= (read-msg 'spt-gov-name) "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
  "spt-gov-name must be the namespace's spt-gov keyset")
(enforce (= (read-msg 'spt-ops-name) "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-ops")
  "spt-ops-name must be the namespace's spt-ops keyset")
;; 🔴 KEEP THIS AS ONE `(if (read-msg 'upgrade)` FORM ON ONE LINE, both keysets inside it as a
;; list. The test suite builds the frozen-module fixture by truncating this file at the first
;; line starting that way; a SECOND top-level branch opening the same way would truncate the
;; whole module and make every freeze test vacuous.
;;
;; 🔴 THE FRESH-DEPLOY BRANCH VALIDATES THE KEYSET VALUE, NOT JUST ITS NAME. Enforcing only
;; the NAMES takes every property of the keyset itself on trust from transaction data, and two
;; payloads are catastrophic and one-shot. An EMPTY keyset loads clean and makes the gov tier
;; vacuously satisfiable by anyone — init-supply then succeeds with ZERO signatures. And
;; `keys-1`, a spelling that reads as correct and is not, is ACCEPTED by `define-keyset` and fails
;; only later at the first `enforce-keyset`, killing every ops operation on that chain FOREVER.
;;
;; 🔴 THE PREDICATE IS READABLE, and an earlier version of this comment said it was not.
;; That was wrong and it cost a finding: you never read `pred` off the guard — you derive the
;; PRINCIPAL, whose `w:` form carries the predicate as its suffix, exactly as
;; `enforce-beneficiary-address` already does for founder addresses 1,800 lines below. The
;; artifact was applying a weaker standard to the keysets governing the tranches, the funding
;; and the freeze than to a single beneficiary row.
;;
;; The 46 and the two literals are REPEATED rather than referenced: this runs BEFORE the module
;; exists, so EMPTY-KEYSET-PREFIX and BUILTIN-KEYSET-PREDS are not in scope. They must stay in
;; step with those defconsts. A `k:` principal is a single-key keyset with no predicate suffix
;; and is accepted; every other shape must name a built-in.
;; 🔴 ONE LINE, and it must stay one line — see the note above.
(if (read-msg 'upgrade) ["admin keysets untouched on upgrade"] [(let ((gp (create-principal (read-keyset 'spt-gov))) (op (create-principal (read-keyset 'spt-ops)))) (enforce (!= (take 46 gp) "w:DldRwCblQ7Loqy6wYJnaodHl30d3j3eH-qtFzfEv46g:") "SPT spt-gov must not be an empty keyset") (enforce (!= (take 46 op) "w:DldRwCblQ7Loqy6wYJnaodHl30d3j3eH-qtFzfEv46g:") "SPT spt-ops must not be an empty keyset") (enforce (or (= (typeof-principal gp) "k:") (contains (drop 46 gp) ["keys-all" "keys-any" "keys-2"])) "SPT spt-gov predicate must be a built-in") (enforce (or (= (typeof-principal op) "k:") (contains (drop 46 op) ["keys-all" "keys-any" "keys-2"])) "SPT spt-ops predicate must be a built-in")) (define-keyset (read-msg 'spt-gov-name) (read-keyset 'spt-gov)) (define-keyset (read-msg 'spt-ops-name) (read-keyset 'spt-ops))])

(module SPT GOVERNANCE
  @doc "SPT: a fungible-v2 + fungible-xchain-v1 token, minted once at init, with pro-rata KDA awards and time-locked reserve tranches. Balances, votes and awards are per-chain and no on-chain read sums them."

  (implements fungible-v2)
  (implements fungible-xchain-v1)

  ;; ---- SCHEMAS / TABLES -------------------------------------------------------------------
  (defschema spt-account
    @doc "A holder ledger row. pending-awards holds only the amount crystallized at the last write, not what is owed; read pending-awards-of for the live figure."
    balance:decimal
    guard:guard
    reward-debt:decimal          ; rpt already accounted for this account
    pending-awards:decimal    ; crystallized at last checkpoint
    ;; ---- THE RECORD-DATE SNAPSHOT ------------------------------------------------------
    ;; snap-index = the generation whose sealed float this row's frozen balance belongs to;
    ;; 0 = never checkpointed. snap-balance = the balance AT that generation's record instant,
    ;; captured lazily on the account's first write after the seal.
    ;;
    ;; 🔴 THE PAIR EXISTS BECAUSE THE DENOMINATOR MOVES, NOT THE ACCRUAL. The accrual pays
    ;; each holder the balance they held AT THE RECORD INSTANT — NOT at effective-at, and the
    ;; difference is the whole point of a record date. Measured: a holder who moved every token
    ;; away inside the window held nothing at effective-at and was still owed in full; a buyer who
    ;; acquired inside the window held it all at effective-at and was owed nothing. What it cannot
    ;; do is
    ;; fix the DENOMINATOR in advance: the float grows between declaring a round and its taking
    ;; effect, through purchases, permissionless tranche releases, and inbound cross-chain legs.
    ;; Measured without it: funding the declared bar exactly, then one stranger's ordinary
    ;; purchase inside the window, took the true debt 150% past the pool — and since claims pay
    ;; all-or-nothing, that becomes a race an HONEST HOLDER CAN LOSE. The loss lands on someone
    ;; who did not act, so the code refuses rather than leaving it to them.
    ;; With these two, a generation's payout is `snap-balance * rate`, so the total is
    ;; `rate * sealed float` exactly — a rate chosen against a denominator that cannot move.
    snap-index:integer
    snap-balance:decimal)
  (deftable accounts:{spt-account})

  ;; ---- GOVERNANCE STATE -------------------------------------------------------------------
  (defschema proposal
    @doc "One chain's replica of a proposal; each chain tallies only its own tokens, with no global result on chain. status stays active past close-at until someone closes it, so read finality from vote-record."
    title:string
    description:string
    created-at:time
    ;; ANNOUNCED at created-at, REVIEWED, then OPENS for voting at open-at. `cast-vote`
    ;; refuses before it and `cancel-proposal` refuses after it, so cancelling a proposal can
    ;; carry no information advantage ABOUT THAT PROPOSAL — during the review gap it has no
    ;; votes to read.
    ;; 🔴 SAY "blind about the proposal being CANCELLED", never "the admin is blind", and say
    ;; it PER CHAIN. Two things narrow it: one open-at is compared against twenty independent
    ;; clocks, and with two proposals running on different schedules — the ordinary case — B's
    ;; voting window can sit inside A's cancel window, so the admin may read B and cancel A.
    ;; Explicit and identical on all 20 chains. NOT block height: chains drift independently.
    open-at:time
    close-at:time                ; derived as open-at + duration-seconds, NOT created-at + duration
    status:string                ; "active" | "closed" | "cancelled"
    active-slot:integer)         ; its slot in the active-proposal index (0 = not indexed)
  (deftable proposals:{proposal})

  ;; account-votes: how many of an account's tokens are CURRENTLY voting on a proposal, + dir.
  ;; Key = (hash [chain account proposal]). Adjusted live: cast-vote sets it to current balance;
  ;; a debit releases max(0, voted - retained) from it (and the tally), where retained = bal -
  ;; debited — NOT min(debited, voted), which is a DIFFERENT formula that releases too much: it
  ;; takes back weight the retained balance still fully backs. Chain-bound so cross-chain
  ;; votes from the same account on different chains are distinct rows.
  (defschema account-vote
    @doc "One row is how many of an account's tokens back a live vote on one proposal, direction true for yes. Key is the hash of voter, chain and proposal, so each chain has its own row; a debit releases only what the balance no longer covers."
    weight:decimal direction:bool)
  (deftable account-votes:{account-vote})

  ;; vote-delegates: an OPTIONAL dedicated voting key per account, so the transfer key can
  ;; live in cold storage. Registered/replaced/cleared ONLY by the account's MAIN guard;
  ;; consumed ONLY by the VOTE cap (main guard OR vote key).
  ;; Per-chain rows, like votes — governance is chain-local.
  (defschema vote-delegate
    @doc "One row is an account's optional dedicated voting key on this chain, keyed by account name. Only the account's main guard may register, replace or clear it; active false means it is cleared and the main guard votes."
    guard:guard active:bool)
  (deftable vote-delegates:{vote-delegate})     ; key = account

  ;; THIS chain's running tally per proposal. Kept in sync live with every vote, re-vote and
  ;; transfer-release, so reading a result is O(1). Frozen at close-at by the DEADLINE, not by
  ;; the close-proposal transaction, which is only bookkeeping. This row IS the product.
  ;;
  ;; 🔴 THE WHOLE PRODUCT RESTS ON THIS: `tallies` has exactly TWO MUTATORS — `cast-vote` and
  ;; the release loop inlined in `debit` — and creation is insert-only. Say it as MUTATORS, not
  ;; writers: there IS a third writer (`create-proposal`'s zero row, which cannot overwrite
  ;; because the `proposals` insert aborts first), and the loose wording lets a regression look
  ;; complete while ignoring a real write site.
  (defschema tally
    @doc "One row is this chain's running yes and no totals for one proposal, keyed by proposal id and updated live by every vote and by the release a debit performs. It counts only tokens held here; a global result is the off-chain sum of 20 rows."
    yes:decimal no:decimal)
  (deftable tallies:{tally})

  ;; active-proposal index: the small set the transfer release-loop iterates. Admin-created
  ;; (create-proposal), so its size is governance cadence — NEVER attacker-inflatable.
  (defschema prop-idx id:string)
  (deftable prop-index:{prop-idx})     ; key = integer index as string
  (defschema prop-count-row n:integer)
  (deftable prop-count:{prop-count-row})

  (defschema state-schema
    @doc "Singleton award and supply state for THIS chain. reward-per-token holds only what apply-round has folded in, so it can lag the live value; read get-rpt."
    reward-per-token:decimal     ; = Σ rate of applied rounds (global)
    circulating-supply:decimal   ; participating balances on this chain (rpt denominator)
    ;; 🔴 DO NOT ADD A STORED EXCLUSION FIELD HERE. The accounts that must be excluded are
    ;; reserve DEFCONSTS, which `excluded?` already covers on all 20 chains — nothing stored,
    ;; nothing to mistype. A stored exclusion address brings back a severe defect class: a
    ;; well-formed but WRONG address, accepted at init, permanently disenfranchises a real
    ;; holder on that chain, with no setter and no repair after the freeze.
    rounds-applied:integer       ; how many declared rounds have been folded into rpt here
    total-distributed:decimal    ; NET KDA moved funding->pool on this chain (solvency
                                 ; bookkeeping; recover-pool-surplus moves the other way and
                                 ; subtracts, so a recovered third-party donation can take
                                 ; this below zero — that is the true net flow, not an error)
    ;; EXACT SOLVENCY, in O(1): the chain's true unclaimed liability is
    ;;   L = sum-pending + rpt*circulating - sum-debt
    ;; `circulating * rpt` alone UNDER-counts it — when a token leaves the chain its earned
    ;; award stays claimable here, but circulating drops. These two counters are maintained on
    ;; every debit, credit and claim, which is what lets `fund-awards` enforce pool >= L
    ;; exactly, making "funded" a hard guarantee that every claim is payable.
    sum-pending:decimal          ; Σ pending-awards over non-excluded accounts (crystallized owed)
    ;; The DECLARATION RUNWAY, in seconds. It lives in state rather than in a defconst so it
    ;; can be lengthened at `spt-gov`; it can never go BELOW MIN-RUNWAY, which is a defconst
    ;; and freezes.
    runway-seconds:integer       ; minimum notice a round/record date must leave
    sum-debt:decimal             ; Σ (balance * reward-debt) over non-excluded accounts
    ;; ---- THE RECORD-DATE GENERATION --------------------------------------------------
    ;; 🔴 THE ORDER IS THE DESIGN: SEAL the float first, choose the rate second.
    ;;
    ;; snap-gen     the generation sealed here; 0 = none ever has.
    ;; snap-at      the SCHEDULED record instant; EPOCH = none scheduled. An INSTANT and not a
    ;;              transaction on purpose: a transaction lands at twenty different block
    ;;              times, so the same tokens would be counted twice. It seals LAZILY, at the
    ;;              first write after it passes — the float only changes at a write, so the
    ;;              seal is correct however long the chain is idle.
    ;; snap-settled whether that generation's correction has been folded into snap-corr.
    ;; snap-corr    the third term of the claim arithmetic, maintained incrementally at every
    ;;              account write, exactly as sum-pending and sum-debt are.
    ;;
    ;; The liability stays O(1):  L = [ sum-pending + rpt*circ - sum-debt ] + snap-corr + OPEN
    snap-gen:integer
    snap-at:time
    snap-settled:bool
    snap-corr:decimal)
  (deftable state:{state-schema})

  ;; ---- One row per generation, keyed by generation number ------------------------------
  ;; circ = the float LATCHED at the record instant — the denominator the operator funds
  ;;        against and the one `declare-round` enforces the rate over. Immutable once sealed.
  ;; base = this chain's rpt at the seal. `min(rpt, base + rate)` is what caps a generation's
  ;;        correction to ITS OWN round, so a later round pays on the CURRENT balance.
  ;; rate = the rate later declared against this generation; 0.0 until `declare-round`, and
  ;;        back to 0.0 on `retract-round`. 🔴 BOTH SIDES OR NEITHER — zeroing only the
  ;;        award-rounds row would leave the accrual still paying.
  (defschema snapshot
    @doc "One row is a sealed record-date generation, keyed by generation number: circ is the float latched at that instant, base the reward-per-token then, and rate the round declared against it, 0.0 before declaration and after a retraction."
    circ:decimal base:decimal rate:decimal)
  (deftable snapshots:{snapshot})       ; key = generation number as string
  ;; The shape `get-snapshot` returns. `exists` distinguishes "never sealed" from a sealed
  ;; generation whose round has not been declared (rate 0.0) — the same `exists` idiom as
  ;; `get-round` and `vote-record`, and for the same reason: a comparator sweeping 20 chains
  ;; must never read a missing row as agreement.
  (defschema snapshot-record
    @doc "The object get-snapshot returns for one generation, adding exists so a caller can tell never sealed from sealed without an abort. Rate 0.0 does not distinguish a generation with no round declared from one whose round was retracted."
    gen:integer exists:bool circ:decimal base:decimal rate:decimal)

  ;; AWARD ROUNDS. A round is declared once by the admin and replicated to EVERY chain with
  ;; identical rate and effective-at. Because every chain holds the same list and reads the
  ;; same consensus block time, the reward-per-token value is identical everywhere BY
  ;; CONSTRUCTION. Indexed 1..n so rounds fold in order without scanning; immutable once
  ;; declared.
  ;;
  ;; 🔴 THE PROPERTY IS THE rpt VALUE, and "a token moving between chains is never mis-paid"
  ;; is an OVER-CLAIM — do not write it. A cross-chain transfer takes two blocks: the sender's
  ;; award crystallizes at the departing chain's rate in step 0, and the arriving chain's rate
  ;; is set in step 1, so a round taking effect BETWEEN them is earned on neither leg. The
  ;; direction is safe (the pool is never short, the holder never over-paid) and the size is
  ;; bounded by how long the sender leaves the transfer incomplete. Stated precisely because
  ;; it FREEZES.
  (defschema award-round
    @doc "One row is a declared award round: a rate in KDA per token effective at a timestamp, keyed by index from 1 up; the admin declares the same values on all 20 chains. A retraction zeroes the rate and rewinds effective-at, never deleting."
    rate:decimal effective-at:time)
  (deftable award-rounds:{award-round})   ; key = round id (integer as string)
  ;; The shape `get-round` returns. `exists` distinguishes "never declared" from "declared then
  ;; RETRACTED", which retract-round makes indistinguishable in the row itself (it zeroes the
  ;; rate rather than deleting). Same `exists` idiom as `vote-rec`.
  (defschema round-record
    @doc "The object get-round returns for one round index, adding exists so an index outside the declared range reads empty instead of aborting. exists true with rate 0.0 is a retracted round; exists false means never declared on this chain."
    index:integer exists:bool rate:decimal effective-at:time)
  (defschema round-count-row n:integer)
  (deftable round-count:{round-count-row})      ; singleton: how many rounds declared here
  ;; apply-round fold accumulator: the last consecutive-effective prefix index + its summed rate.
  (defschema apply-acc i:integer rate:decimal)

  (defschema tranche-lock
    @doc "One time-locked tranche, keyed treasury, liquidity or founder:<account>. The cliff and vest dates are fixed at init and never change; treasury and liquidity pay out only via disburse-tranche."
    beneficiary:string
    ;; 🔴 NO STORED `guard` HERE, AND DO NOT ADD ONE. `release-tranche` reads the guard from
    ;; the beneficiary's own ledger row; one frozen here at ceremony time would be a SECOND,
    ;; STALE copy of an authority the account already owns — and the more misleading of the
    ;; two, because `get-tranche` publishes it.
    total:decimal
    released:decimal
    cliff-end:time
    vest-end:time)
  (deftable tranche-locks:{tranche-lock})

  (defschema init-schema
    @doc "The single row, keyed init, recording that this chain's one-time setup has run: init-supply writes it on chain 0 and init on every other chain. While it is present any further initialization of this chain aborts."
    initialized:bool)
  (deftable init-state:{init-schema})

  ;; ---- CONSTANTS --------------------------------------------------------------------------
  (defconst TOTAL-SUPPLY 100000.0)
  ;; ---- Tranche allocation + release calendar ----------------------------------------------
  ;; 🔴 THE CALENDAR IS SOURCE, NOT DATA. `init-supply` stamps T = its block time once, and
  ;; every cliff and vest date is T plus these constants. After the freeze nothing can alter
  ;; it — no setter exists and none can be added.
  (defconst LAUNCH-TRANCHE 20000.0)
  (defconst FOUNDER-TRANCHE 10000.0)
  (defconst TREASURY-TRANCHE 55000.0)
  (defconst LIQUIDITY-TRANCHE 15000.0)
  (defconst FOUNDER-CLIFF-DAYS 365)    (defconst FOUNDER-VEST-DAYS 1460)   ; 12mo cliff -> 4y
  (defconst TREASURY-CLIFF-DAYS 365)   (defconst TREASURY-VEST-DAYS 1825)  ; 12mo cliff -> 5y
  (defconst LIQUIDITY-CLIFF-DAYS 90)   (defconst LIQUIDITY-VEST-DAYS 730)  ; 3mo cliff -> 2y
  ;; The founder tranche is N rows, one per founder, keyed "founder:<account>" — the COUNT is
  ;; ceremony data, the SCHEDULE stays source. A prefixed key can never collide with the two
  ;; fixed keys below, and only `init-supply` writes tranche rows at all.
  (defconst TRANCHE-FOUNDER-PREFIX "founder:")
  (defconst TRANCHE-TREASURY "treasury")
  (defconst TRANCHE-LIQUIDITY "liquidity")
  ;; The principal prefix of a keyset with NO KEYS — an empty keys-all keyset is vacuously
  ;; satisfiable by anyone. The hash covers the key list only and the predicate is a suffix, so
  ;; this ONE prefix covers all three predicates. Pact exposes no keyset introspection from a
  ;; `guard`, so this pinned principal is the only check available.
  (defconst EMPTY-KEYSET-PREFIX "w:DldRwCblQ7Loqy6wYJnaodHl30d3j3eH-qtFzfEv46g:")
  ;; The ONE account init may record as the launch reserve, on all 20 chains, without the sale
  ;; module needing to be deployed. 🔴 Hand-building a principal is legitimate ONLY because a
  ;; NAMED test goes red the moment it diverges from what the sale module derives.
  (defconst LAUNCH-RESERVE-PIN
    "m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT-launch:SPT-launch-reserve")
  ;; The three BUILT-IN keyset predicates. Anything else is a CUSTOM predicate — an arbitrary
  ;; module function, which may return true with no signature at all.
  (defconst BUILTIN-KEYSET-PREDS ["keys-all" "keys-any" "keys-2"])
  (defconst MINIMUM-PRECISION 12)
  (defconst STATE-KEY "state")
  (defconst INIT-KEY "init")
  (defconst PROP-COUNT-KEY "pc")               ; active-proposal-index counter singleton key
  (defconst ROUND-COUNT-KEY "rc")              ; award-round counter singleton key
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))  ; sentinel (missing-proposal default)
  ;; ---- The two admin tiers ----------------------------------------------------------------
  ;;   GOV-KS  keys-2 of 3 — irreversible, or moves value out.
  ;;   OPS-KS  keys-any of 3 (1-of-3) — reversible day-to-day operation.
  ;; Split so one argument-free grant cannot authorize every operation. The split FREEZES.
  ;; 🔴 THE NAMESPACE DERIVES FROM GOV-KS, AND FROM ITS PREDICATE. A keyset guard carries the
  ;; keys AND the predicate, so deriving from the ops tier by mistake yields a DIFFERENT,
  ;; valid-looking namespace with no error at all. Name GOV-KS explicitly, always.
  (defconst GOV-KS "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
  (defconst OPS-KS "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-ops")
  ;; ---- Governance --------------------------------------------------------------------------
  ;; 🔴 THERE IS NO ON-CHAIN PARTICIPATION THRESHOLD, AND ONE MUST NOT BE ADDED. Quorum lives in
  ;; the charter, where it can be revised. On chain it is unimplementable here, for four
  ;; measured reasons — kept because a future reader will try to add it back:
  ;;  1. No cross-chain aggregate exists, so a quorum would be judged PER CHAIN against a
  ;;     global-sized number. The maximum voting float is 45,000 across 20 chains, so a bar
  ;;     large enough to mean anything is unreachable on a thin chain at 100% turnout, forever.
  ;;  2. Simultaneously TRIVIAL on chain 0, where a single vesting beneficiary clears it alone.
  ;;     A bar the person the vote advises can clear single-handedly is not a participation
  ;;     test.
  ;;  3. At launch the voting float is literally zero — every token sits in a reserve — and the
  ;;     cliffs release gradually, so governance would be impossible for months.
  ;;  4. BURN-VETOABLE, measured: a losing voter destroying their own tokens flips a passing
  ;;     vote to failing. A relative bar is immune to that; an absolute one is not.
  (defconst MIN-PROPOSAL-DURATION 259200)       ; 72 hours (seconds)
  ;; 🔴 THE ACTIVE-PROPOSAL CEILING EXISTS BECAUSE THE COST LANDS ON HOLDERS. Every transfer
  ;; walks the open proposals to release the moved tokens' votes, so each open proposal is a
  ;; permanent surcharge on EVERY transfer (measured: 948 gas at 0 open, 3,684 at 20). The
  ;; index self-drains only when someone pays to close, so proposals opened and abandoned
  ;; would tax every holder indefinitely.
  ;; 🔴 THE LIVENESS TRADE: hitting the ceiling blocks NEW proposals until finished ones are
  ;; closed — and that remedy is PERMISSIONLESS, so the cap can always be cleared without a key
  ;; nobody has. That is what makes a ceiling acceptable here.
  (defconst MAX-ACTIVE-PROPOSALS 32)
  (defconst MAX-PROPOSAL-DURATION 1209600)      ; 14 days (seconds)
  ;; ---- THE INDEX TAX IS BOUNDED BY SIZE, NOT JUST COUNT -----------------------------------
  ;; 🔴 BOUNDING THE COUNT BOUNDS NOTHING WHEN EACH ENTRY IS UNBOUNDED. The release loop
  ;; deserialises the WHOLE proposal row per entry, so the per-transfer cost scales with the
  ;; row's SIZE, not just how many there are. Measured on one transfer against 20 open
  ;; proposals: 1,630 gas with 10-character descriptions, 17,590 with 4,000 — a 26x spread that
  ;; every holder pays forever, on a module that cannot be patched.
  ;; BOUNDED TOGETHER, not just `description`: `id` is replicated into three table keys AND the
  ;; vote-record digest, so it has the widest blast radius per character. It gets its own tight
  ;; bound, and the three draw on ONE combined budget, so trading one for another escapes nothing.
  ;; The full charter text lives off-chain by design.
  (defconst MAX-PROPOSAL-ID-CHARS 64)
  (defconst MAX-PROPOSAL-CHARS 1024)   ; id + title + description, combined
  ;; ---- THE MINIMUM REVIEW GAP, AND IT FREEZES ---------------------------------------------
  ;; The enforced distance between announcing a proposal and voting opening on it.
  ;; 🔴 "FOR NOW" IS NOT AVAILABLE FOR A FROZEN CONSTANT. After the freeze no proposal can EVER
  ;; be announced with less notice — emergencies included — and no upgrade can lower it. A
  ;; shorter floor with 48h as an operational default was REJECTED: a default nobody enforces
  ;; is the shape this project has been bitten by repeatedly, and the mandatory votes are
  ;; scheduled events, not emergencies.
  ;; WHAT IT BUYS: time to notice a mistyped title, a wrong duration, or a replica missing from
  ;; one of 20 chains. It costs nothing in veto power, because there is nothing to see yet.
  ;; 🔴 SECONDS, AS A DECIMAL, and that is not cosmetic: `diff-time` returns a decimal and Pact
  ;; will not compare a decimal against an integer. The neighbouring duration constants are
  ;; integers because they are compared against an integer and fed to `add-time`.
  (defconst MIN-REVIEW-GAP 172800.0)            ; 48 hours in SECONDS — announcement -> voting opens
  ;; ---- THERE IS NO CANCEL-WINDOW CONSTANT, AND ONE MUST NOT BE RE-DERIVED -----------------
  ;; A fixed window measured from the announcement is NOT what keeps a cancellation blind:
  ;; results are public and live, so any window overlapping the vote hands the admin a
  ;; near-full-information veto — read the tally, then void it (measured). A window short
  ;; enough to prevent that trades review time away to almost nothing.
  ;; THE TRADE IS DISSOLVED INSTEAD OF BALANCED: cancelling is legal only BEFORE voting opens,
  ;; and no vote can exist before then, so during the entire cancel window there is nothing to
  ;; read. Blind by construction rather than by stopwatch.
  ;; 🔴 ABOUT THE PROPOSAL BEING CANCELLED, AND PER CHAIN — never "the admin is blind". Another
  ;; proposal on a different schedule can be readable during this one's cancel window, and one
  ;; open-at is compared against twenty independent clocks. The full residual is stated on
  ;; `cancel-proposal`; do not restate it unqualified here.
  ;; It also retires a subtlety: the tally is NON-MONOTONIC (a voter who transfers out is
  ;; released back out of it), so a "no votes so far" bound would silently re-open.

  ;; ---- THE ROUND RATE IS NOT CAPPED, AND THE FUNDING BAR IS WHY ---------------------------
  ;; There is deliberately no maximum rate. What bounds the damage is the EXACT funding bar
  ;; over the SEALED float, which refuses at the point of declaration any rate the pool cannot
  ;; cover — strictly better than a cap's bounded loss. Measured: fund exactly what
  ;; `funding-needed` reports, then mistype the rate tenfold, and the declaration is REFUSED ON
  ;; THE MONEY while the intended rate is accepted from identical state.
  ;; A cap is a float-INDEPENDENT proxy for that check. Against an exact bar it would only
  ;; refuse legitimate rounds.
  ;; WHY THE RATE IS THE MOST DAMAGING INPUT IF IT EVER ESCAPES: rounds are IMMUTABLE and the
  ;; pool has exactly one bounded exit. Measured with no bar at all, a single mistyped
  ;; declaration permanently disabled funding, surplus recovery AND claims on all 20 chains,
  ;; stranding the pool with no exit at all.
  ;;
  ;; 🔴🔴 THE COUPLING — READ THIS BEFORE TOUCHING MIN-RETRACT-LEAD. The ONE fat finger the bar
  ;; CANNOT refuse is a wrong rate the pool ALREADY covers. For that case the runway floor is
  ;; the ONLY remedy, and it must NEVER be argued down on the grounds that rounds are bounded
  ;; elsewhere — they are not.

  ;; ---- MIN-RETRACT-LEAD ---------------------------------------------------------------------
  ;; How far a round must still be from taking effect for a retraction to be accepted. A round
  ;; is retracted as 20 separate transactions, so what is being bounded is a retraction landing
  ;; on some chains and not others — the one thing the replicated-round design exists to
  ;; prevent. Cross-chain block-time skew is seconds; this is four orders of magnitude of
  ;; margin.
  ;; IT IS HALF OF ONE DECISION: declaring requires 2x this lead, which guarantees the
  ;; retraction window is at least this wide. Without that doubling the usable window is
  ;; admin-chosen and collapses to a single block — not a remedy at all.
  ;;
  ;; 🔴 WHAT IT DOES NOT DO, written plainly because it freezes: a chain past the lead REFUSES
  ;; the retraction, and that refusal does NOT fail safe. Measured — one chain retracted in
  ;; time, a late chain was refused, and the first retraction was NOT undone. The refusal LOCKS
  ;; THE DIVERGENCE IN: one chain pays nothing and the other pays in full, permanently. The
  ;; divergence is detectable by comparing the round list across all 20, but it is not
  ;; self-correcting. VERIFY AFTER RETRACTING, ALWAYS.
  (defconst MIN-RETRACT-LEAD 21600)             ; 6 hours (seconds); declaration floor is 2x = 12h
  ;; ---- THE RUNWAY IS SETTABLE; ITS MINIMUM IS NOT -----------------------------------------
  ;; The runway lives in `state` and can be lengthened at gov. This is the floor under it, and
  ;; it FREEZES — it is what stops an accidental instant launching a round immediately.
  ;; 🔴 WRITTEN AS A DERIVATION, NOT A BARE NUMBER. The property that matters is the SPAN:
  ;; declaring requires twice the retraction lead, so the remedy window is at least one lead
  ;; wide for EVERY round. A literal here would hide which fact is load-bearing.
  ;; 🔴 THIS MINIMUM CARRIES THE WEIGHT A RATE CAP WOULD HAVE — see the coupling above.
  ;; Raising it is always safe; only lowering is a decision, and the code forbids lowering.
  (defconst MIN-RUNWAY (* 2 MIN-RETRACT-LEAD))  ; 12 hours (seconds) — the founder's own guard
  (defconst MAX-RUNWAY 315360000)   ; seconds — ten years; guards `add-time`'s silent wrap
  ;; ---- NO UPPER BOUND ON A ROUND'S LEAD, DELIBERATELY -------------------------------------
  ;; A far-future effective-at jams our own scheduler; it is not a loss, and the operator
  ;; recovers alone. Monotonicity is anchored to the PREVIOUS round, so one mistyped year would
  ;; otherwise reject every later round forever — but `retract-round` REWINDS effective-at,
  ;; which makes a lone far-future typo a true undo (measured).
  ;; 🔴 THE REWIND IS WHAT MAKES THE MISSING BOUND SAFE — never remove it while there is no
  ;; lead bound.

  ;; ---- FROZEN-MODULE -----------------------------------------------------------------------
  ;; Set true and redeploy to permanently freeze UPGRADES of this module. That is the whole
  ;; definition — every defun and defpact must keep working exactly as before, forever.
  ;;
  ;; 🔴 FREEZING CHANGES THIS MODULE'S HASH, and `SPT-launch` links against that hash. A
  ;; plain flip therefore kills `launch.buy` with "hash not blessed", and aborts an in-flight
  ;; cross-chain transfer at step 1 — DESTROYING tokens whose sender was already debited.
  ;; Measured both ways, on a node and in the REPL. So the freeze artifact MUST also carry
  ;; `(bless "<pre-freeze hash>")`: without it the freeze breaks public functions, which is a
  ;; DEFECT by the definition above, not a trade-off.
  ;;
  ;; 🔴 THE ORDER IS LOAD-BEARING: freeze the SALE first and its re-deploy becomes impossible,
  ;; stranding the unsold launch reserve permanently, with no key and no upgrade that can help.
  ;;
  ;; 🔴 AND THERE IS A SECOND HASH PIN THAT POINTS AT A MODULE WE DO NOT CONTROL: `coin`.
  ;; Pact pins a cross-module call to the callee's hash at the CALLER's compile time, so a frozen
  ;; token is bound forever to the exact `coin` it was compiled against on that chain. If a future
  ;; `coin` upgrade ever drops that hash from its bless list, EVERY KDA PATH HERE DIES PERMANENTLY
  ;; — funding, claiming, surplus recovery, funding in and out, the sale — and the KDA already in
  ;; the pool and funding accounts is STRANDED, because both are module-guarded and their only
  ;; exits are the dead functions. `try` does not catch it. Transfers, governance and vesting
  ;; survive, so the module is half-alive with no route back.
  ;; 🔴 NO IN-MODULE REMEDY EXISTS AND NONE IS TO BE INVENTED — a module cannot bless on
  ;; another module's behalf. It is an ACCEPTED, PERMANENT third-party dependency, and the only
  ;; mitigation is procedural: RE-DEPLOY ON EACH CHAIN IMMEDIATELY BEFORE THE FREEZE so the link is
  ;; to that chain's current `coin`, then freeze.
  ;;
  ;; 🔴 THE BLESS LINE CANNOT BE ADDED IN ADVANCE, because blessing a hash CHANGES the hash. The
  ;; freeze artifact is necessarily two lines off the reviewed build, and BOTH lie outside the
  ;; reviewed hash — arithmetic, not a process failure. 🔴 READ THE HASH FROM `describe-module`
  ;; ON THE TARGET CHAIN. Never from an audit report or a config file: a module hash covers its
  ;; DEPENDENCY hashes, so a REPL-derived value cannot equal the on-chain one, and blessing it
  ;; blesses nothing.
  (bless "cg8sInne-rg-JM2L1H2rcppXqBGE8NUIyBdB275RTP0")
  (defconst FROZEN-MODULE true)

  ;; ========================================================================
  ;; EVENTS
  ;; ========================================================================

  ;; ---- VALUE-DESCRIBING EVENTS -------------------------------------------------------------
  ;; Every event cap below either carries a REAL BODY or records an explicit weak-by-decision
  ;; disposition. 🔴 THE SILENCE IS THE DEFECT, NOT THE WEAKNESS: an event with no disposition
  ;; leaves a reader unable to tell decided-and-accepted from overlooked.
  ;; A REAL BODY COSTS NO LIVENESS: `emit-event` does not evaluate the body at all, so the body
  ;; is reached only on the ACQUISITION route, which is not the honest emitter's route.
  ;; THE ONES WITHOUT A BODY ARE A DECISION. Their emitters are PERMISSIONLESS, so no holder
  ;; exists to require, and inventing one would produce a body asserting a PRECONDITION while
  ;; reading as an AUTHORIZATION — protection in appearance only. 🔴 READ THE TABLE, NOT THE
  ;; STREAM.
  (defcap ROUND-DECLARED (id:string rate:decimal effective-at:time)
    @doc "spt-gov: this chain has promised an award round paying rate KDA per SPT from effective-at, priced against its sealed record date. id is an operator label carried only in the event; on chain a round is addressed by index, never by id."
    @event
    (require-capability (ADMIN-GOV)))
  ;; A declared round neutralised before it can take effect. `index` and `rate` name exactly
  ;; which row was zeroed and what it held, so an indexer can reconstruct the round list from
  ;; the event stream alone (the row itself keeps no history).
  (defcap ROUND-RETRACTED (id:string index:integer rate:decimal effective-at:time)
    @doc "spt-ops: the round at index was zeroed on this chain before it took effect, so it pays nothing. rate and effective-at are what the row held before retraction, since the row keeps no history; id is an operator label and names no row."
    @event
    (require-capability (ADMIN-OPS)))
  ;; WEAK BY DECISION: apply-round is PERMISSIONLESS (anyone may fold an effective round
  ;; into this chain's rpt). No holder exists to require.
  (defcap ROUND-APPLIED (id:string chain:string rate:decimal)
    @doc "Permissionless: rate is the sum of newly effective round rates just folded into this chain's stored reward-per-token. Bookkeeping only, since rounds pay from their own effective-at whether or not anyone calls this; id is a caller label."
    @event true)
  ;; ---- Record-date events ----------------------------------------------------------------
  ;; These two carry `require-capability (ADMIN-OPS)` because that is the tier their emitters
  ;; acquire. 🔴 NAME THE TIER THE EMITTER ACTUALLY HOLDS — and know that NOTHING AT RUNTIME
  ;; TELLS YOU WHEN IT IS WRONG. Measured on 5.4: `emit-event` does not evaluate the body at all
  ;; (it only checks the cap belongs to this module), so a mismatch costs no liveness and the
  ;; event still lands. The body is load-bearing on the ACQUISITION route instead, where it must
  ;; name a tier no caller outside this module can hold. A wrong tier is therefore a silent
  ;; defect that freezes with the module, not one a test will fail for you. Measured across both
  ;; modules: no event cap is emitted from operations in BOTH tiers, so each has one right answer.
  (defcap SNAPSHOT-SCHEDULED (record-at:time)
    @doc "spt-ops: this chain will latch its float at record-at, the instant that fixes the denominator for the next award round. No rate is attached yet, and the date stays cancellable until it is close to landing."
    @event
    (require-capability (ADMIN-OPS)))
  (defcap SNAPSHOT-CANCELLED (record-at:time)
    @doc "spt-ops: the record date at record-at was called off on this chain before it landed, so no float was latched for it. Cancellation is per chain, so check all 20 before assuming the date is gone everywhere."
    @event
    (require-capability (ADMIN-OPS)))
  ;; WEAK BY DECISION: `advance-snapshot` is permissionless by design, because a chain with no
  ;; activity must still be sealable by anyone. `circ` is the sealed float an indexer needs to
  ;; reconstruct each generation, but the authority for it is `get-snapshot`, not the stream.
  (defcap SNAPSHOT-SEALED (gen:integer chain:string circ:decimal base:decimal)
    @doc "Permissionless: chain sealed generation gen at its record date. circ is the float latched as that generation's denominator and base the reward-per-token at that instant; get-snapshot is the authority for both."
    @event true)
  (defcap SNAPSHOT-SETTLED (gen:integer chain:string correction:decimal)
    @doc "Permissionless: generation gen is closed on chain and correction, in KDA, has been folded into that chain's award-liability counters. Bookkeeping only; it moves no money and no holder needs to act on it."
    @event true)
  (defcap AWARD-FUNDED (amount:decimal)
    @doc "spt-gov: amount KDA moved from this chain's funding account into its award pool, which must then cover the chain's whole unclaimed liability. Funding is per chain, so fund all 20 before declaring a round."
    @event
    (require-capability (FUND-AWARDS)))                ; per-chain cash into the pool
  ;; WEAK BY DECISION: claim-awards is PERMISSIONLESS (a bot may claim for a holder).
  (defcap AWARD-CLAIMED (account:string amount:decimal)
    @doc "Permissionless: amount KDA of accrued awards was paid out for account. It goes to the principal of that account's stored SPT guard, not a like-named coin account, floored to 12 decimals with the dust carried forward."
    @event true)
  ;; Pool KDA owed to nobody, returned to funding (never leaves the module).
  (defcap POOL-SURPLUS-RECOVERED (amount:decimal)
    @doc "spt-gov: amount KDA that the award pool owed to nobody was returned to this chain's funding account. It never leaves the module, and no holder's accrued award is reduced by it."
    @event
    (require-capability (RECOVER-SURPLUS amount)))
  ;; WEAK BY DECISION: receive-funding is PERMISSIONLESS — anyone may route KDA in.
  (defcap FUNDING-RECEIVED (from:string amount:decimal)
    @doc "Permissionless: from sent amount KDA into this chain's funding account as an ordinary coin transfer. Anyone may route KDA in, and the module records no obligation to the sender in return."
    @event true)
  (defcap FUNDING-WITHDRAWN (to:string amount:decimal)
    @doc "spt-gov: amount KDA left this chain's funding account for the external coin account to. The signature must name the destination and the amount it approves, so this reports a spend that was scoped in advance."
    @event
    (require-capability (WITHDRAW-FUNDING to amount)))
  ;; 🔴 TRANCHE-LOCKED IS THE PUBLIC DISCLOSURE ANCHOR: the full release schedule of every
  ;; tranche is published on chain through this one event, so a forgeable one would be worse
  ;; here than anywhere else. Hence the real body.
  (defcap TRANCHE-LOCKED (tranche:string beneficiary:string total:decimal cliff-end:time vest-end:time)
    @doc "spt-gov: at initialization total SPT was locked as tranche on a fixed schedule: nothing before cliff-end, then linear to the full amount at vest-end. beneficiary is a payout address only for a founder tranche, else the reserve holding it."
    @event
    (require-capability (ADMIN-GOV)))
  ;; WEAK BY DECISION: release-tranche is PERMISSIONLESS (anyone may push a vested release
  ;; to its ceremony-fixed beneficiary), so there is no holder to require.
  (defcap TRANCHE-RELEASED (tranche:string beneficiary:string amount:decimal released-total:decimal)
    @doc "Permissionless, chain 0: amount SPT that had newly vested from tranche was credited to beneficiary, taking released-total out of that tranche in all. Anyone may push a release; the destination is fixed at initialization."
    @event true)
  ;; The disclosure anchor for the ONE discretionary power over these tokens: every departure
  ;; from the treasury or liquidity reserve is published here with its target, amount and
  ;; running total, so the whole history is reconstructible from the stream.
  (defcap TRANCHE-DISBURSED (tranche:string target:string amount:decimal disbursed-total:decimal)
    @doc "spt-gov, chain 0: amount SPT was sent from the treasury or liquidity tranche to target, taking disbursed-total out of that tranche in all. The vesting calendar caps the amount, the admin chooses target, and there is no reversal."
    @event
    (require-capability (DISBURSE tranche target amount)))
  ;; ---- GOVERNANCE EVENTS CARRY REAL BODIES -------------------------------------------------
  ;; A forged event cannot move the tally — only `cast-vote` and `debit`'s release loop write
  ;; it — so this is HYGIENE, not the security boundary. It matters because a fabricated record
  ;; named VOTE-CAST actively misleads explorers, indexers and holders who read the stream
  ;; instead of the table. Each body requires a capability an outsider cannot hold.
  ;;
  ;; 🔴 SEVERAL BODIES NAME A TIER THEIR EMITTER NEVER HOLDS, because the emitter holds a
  ;; PARAMETERISED capability instead. That looks like an inert assertion and a review has
  ;; already proposed relaxing those bodies to `true`. KEEP THEM — measured both ways on these
  ;; bytes, the written form emits NOTHING to an outside caller, and at `true` the same caller
  ;; emits a forged disbursement naming an amount and an account of its choosing. The body is
  ;; skipped on the honest path and is the WHOLE defense on the other one. It is STRICTER than
  ;; this block's rule, never weaker, and a defense that FREEZES stays.
  (defcap PROPOSAL-CREATED (id:string title:string)
    @doc "spt-ops: proposal id was announced on this chain under title. The same proposal is submitted to every chain, so expect one of these per chain; the voting window, text and status live in the proposals row, not in this event."
    @event
    (require-capability (ADMIN-OPS)))
  ;; `key` = (create-principal guard): indexers can tell WHICH key was granted, which is the
  ;; audit trail for detecting a stealth registration.
  (defcap VOTE-KEY-SET (account:string key:string)
    @doc "account registered a vote key on this chain, signed by its own main guard. key is the principal of the delegate guard, so a reader can tell exactly which key was granted; a vote key may only vote and can never move tokens."
    @event
    (require-capability (VOTE-KEY-ADMIN account)))
  ;; Emitted from TWO authorized places: clear-vote-key (VOTE-KEY-ADMIN) and rotate's
  ;; key-revocation leg (ROTATE). Both enforce the account's own guard, so either is a
  ;; sufficient authorization and the cap accepts either rather than forcing a weaker body.
  (defcap VOTE-KEY-CLEARED (account:string)
    @doc "account no longer has an active vote key on this chain, so voting falls back to its main guard alone. Emitted both when the owner clears the key and when a guard rotation revokes it, always under the account's own guard."
    @event
    (enforce-one "vote key cleared: neither VOTE-KEY-ADMIN nor ROTATE is in scope"
      [ (require-capability (VOTE-KEY-ADMIN account))
        (require-capability (ROTATE account)) ]))
  (defcap VOTE-CAST (voter:string proposal:string weight:decimal direction:bool)
    @doc "voter recorded weight SPT on proposal on this chain; direction is true for yes and false for no. Weight is the voter's whole balance at that instant, and a re-vote replaces the earlier one, so never sum one voter's events."
    @event
    (require-capability (VOTE voter)))
  ;; Released inside `debit`, under the real DEBIT of the account losing the tokens.
  (defcap VOTE-RELEASED (voter:string proposal:string amount:decimal)
    @doc "amount of voter's recorded weight on proposal was released from this chain's tally, because a debit left them holding too little to back it. Emitted inside the transfer that caused it; the recorded weight drops by amount, possibly to zero."
    @event
    (require-capability (DEBIT voter)))
  ;; PROPOSAL-CLOSED KEEPS A WEAK BODY DELIBERATELY. It is emitted from `close-proposal`, which
  ;; is PERMISSIONLESS, so no capability authorizes that path — there is no authority involved,
  ;; every precondition being objective and publicly checkable. Inventing one would recreate the
  ;; weak lifecycle capability this module refuses to carry. The answer is that `vote-record`
  ;; reports status and frozen from the TABLE, where the truth is.
  (defcap PROPOSAL-CLOSED (id:string status:string) @event true)

  ;; ---- INTERNAL ACCOUNT GUARDS (module-owned) ----------------------------------------------
  (defcap TREASURY-GUARD () @doc "Derives the treasury reserve account principal. It authorizes nothing: no code acquires it, and the reserve is protected by protocol-account?." true)
  (defcap FOUNDER-GUARD () @doc "Derives the founder reserve account principal. It authorizes nothing: no code acquires it, and the reserve is protected by protocol-account?." true)
  (defcap LIQUIDITY-GUARD () @doc "Derives the liquidity reserve account principal. It authorizes nothing: no code acquires it, and the reserve is protected by protocol-account?." true)
  ;; 🔴 FUNDING AND POOL HOLD KDA AND ARE GUARDED DIFFERENTLY, ON PURPOSE. They are `coin`
  ;; accounts, so their guards are enforced inside coin — a different module — which is exactly
  ;; where a MODULE guard discriminates: SPT is on the call stack only when it
  ;; genuinely initiates the spend. Any other caller falls through to this module's admin keyset:
  ;; a STRANGER fails there, and module GOVERNANCE succeeds — which is not a hole, because a gov
  ;; signer can already redeploy the module. Never replace these with capability guards.
  ;; 🔴 SAY "A STRANGER FAILS", NEVER "IT FAILS". The unqualified form was false, and it is the
  ;; only case the suite exercises.
  ;; `create-module-guard` must run inside a module FUNCTION frame, hence the defuns.
  ;;
  ;; 🔴 A PERMANENT CHOICE, NOT A STOPGAP, and not reversible: a different guard derives a
  ;; different PRINCIPAL, so the change stops being possible at FIRST FUNDING — earlier than
  ;; the freeze. Accepted residual: `create-module-guard` is deprecated, and if it is ever
  ;; removed these accounts cannot be migrated.
  ;; 🔴 NEVER RENAME THIS MODULE AFTER DEPLOY — the principals derive from guards naming it.
  ;;
  ;; TREASURY / FOUNDER / LIQUIDITY do NOT use this pattern and do not need to: they live in
  ;; THIS module's own table, where a module guard cannot discriminate. What protects them is
  ;; that every value and state path rejects protocol accounts outright — the defence is not
  ;; the guard, it is that there is nothing left for a forged one to unlock.
  (defun funding-guard:guard ()
    @doc "Returns the module guard owning this module KDA funding account, the guard its principal name derives from. It passes only while SPT initiates the spend; any other caller falls through to module governance, which a stranger cannot pass."
    (create-module-guard "SPT-funding"))
  (defun pool-guard:guard ()
    @doc "Returns the module guard owning this module KDA award pool account, the guard its principal name derives from. It passes only while SPT initiates the spend; any other caller falls through to module governance, which a stranger cannot pass."
    (create-module-guard "SPT-pool"))

  (defconst TREASURY-G  (create-capability-guard (TREASURY-GUARD)))
  (defconst FOUNDER-G   (create-capability-guard (FOUNDER-GUARD)))
  (defconst LIQUIDITY-G (create-capability-guard (LIQUIDITY-GUARD)))
  (defconst FUNDING-G   (funding-guard))
  (defconst POOL-G      (pool-guard))

  (defconst TREASURY-ACCOUNT  (create-principal TREASURY-G))
  (defconst FOUNDER-ACCOUNT   (create-principal FOUNDER-G))
  (defconst LIQUIDITY-ACCOUNT (create-principal LIQUIDITY-G))
  (defconst FUNDING-ACCOUNT   (create-principal FUNDING-G))
  (defconst POOL-ACCOUNT      (create-principal POOL-G))

  ;; ---- GOVERNANCE / ADMIN ------------------------------------------------------------------
  (defcap GOVERNANCE ()
    @doc "Upgrade gate. FROZEN-MODULE=true permanently blocks upgrades."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset GOV-KS))

  ;; ---- `ADMIN` IS TWO TIERS ----------------------------------------------------------------
  ;; The rule that decides every placement: OPERATING within a limit = ADMIN-OPS. CHANGING a
  ;; limit, moving value out, or anything that cannot be undone = ADMIN-GOV.
  ;; 🔴 THE TIERS FREEZE — an operation placed in the wrong one is placed there permanently.
  ;;
  ;; 🔴 THE TWO TIERS ARE TELLABLE APART IN A TEST ONLY BECAUSE THEIR PREDICATES DIFFER, and
  ;; that is worth protecting deliberately. The engine's refusal message names the predicate,
  ;; and the key LISTS are identical (the same three devices), so the predicate is the only
  ;; discriminator. Give both tiers the same predicate and every tier negative silently stops
  ;; asserting WHICH tier refused, while staying green — this estate's most-repeated defect
  ;; shape, and a second reason not to "fix" the ops tier to keys-2.
  ;; It also means a tier negative must NEVER stand alone: pair each refusal with a positive
  ;; control, or it cannot distinguish "the tier refused it" from "it was broken anyway".
  (defcap ADMIN-GOV ()
    @doc "Governance and value tier, gated by the spt-gov keyset. Irreversible operations, or operations that move value out."
    (enforce-keyset GOV-KS))

  (defcap ADMIN-OPS ()
    @doc "Operations tier, gated by the spt-ops keyset. Reversible day-to-day operations."
    (enforce-keyset OPS-KS))

  ;; ---- A TIER IS NOT A SPENDING SCOPE ------------------------------------------------------
  ;; `ADMIN-GOV` takes no arguments, so a signature scoped to it authorizes EVERY gov operation
  ;; in the same transaction — one clist naming it drives a routine `set-runway` AND a
  ;; 70,000-SPT disbursement together. Splitting one argument-free grant into two tiers shrinks
  ;; the blast radius; it does not touch that mechanism. So every value-mover carries its own
  ;; parameterised capability.
  ;;
  ;; 🔴 THIS MATTERS MORE HERE THAN IN MOST PROJECTS BECAUSE THE SIGNER USES A HARDWARE WALLET,
  ;; AND THE DEVICE RENDERS THE CLIST. Under a tier name it shows a tier name while the same
  ;; signature moves 70% of supply; under `DISBURSE` it shows the tranche, the destination and
  ;; the amount. The fix is what the device DISPLAYS, not a new restriction on the admin.
  ;;
  ;; 🔴 ENFORCE THE KEYSET DIRECTLY. Do NOT `compose-capability (ADMIN-GOV)` — the obvious
  ;; shape is the wrong one, because `enforce-keyset` passes whenever the signer's clist names
  ;; any capability on the acquisition stack, and composing puts the tier back there. Enforcing
  ;; the keyset directly is what makes the scope bind. An UNSCOPED signature still works, which
  ;; is what keeps the deploy ceremony from bricking.
  ;;
  ;; BOUNDARY: it scopes the SIGNATURE, not the authority. The gov tier still authorizes this
  ;; operation and the authority's own bound is still `tranche-available`; what changes is that
  ;; a signature for something else no longer carries it.
  ;;

  ;; ---- THE AMOUNT IS A REAL SPENDING LIMIT ------------------------------------------------
  ;; 🔴 PARAMETERS BIND THE ARGUMENTS, NOT THE NUMBER OF ACQUISITIONS. Without the meter below,
  ;; ONE clist entry approving 100.0 drives 150 identical calls in a single transaction and
  ;; moves the WHOLE 15,000 SPT tranche — a plain capability pops at end of extent and
  ;; re-acquires freely. Parameters alone are not worthless (a different tranche, destination
  ;; or amount is refused), but they do not bound repetition.
  ;;
  ;; 🔴 SO `@managed` IS THE ONLY THING THAT MAKES "THE SIGNATURE MUST NAME IT" TRUE. Do not
  ;; infer that scoping is required elsewhere from any other mechanism: measured on a node,
  ;; mined, an UNSCOPED gov signature drives the other value-movers for any amount to any
  ;; destination, with both clists empty on the wire. What coin's own meter bounds is the
  ;; number of CALLS to one destination, never the amount or the destination.
  ;; A related engine behaviour is real but is a DIFFERENT fact: the first `install-capability`
  ;; disables unscoped signatures for the REST of that transaction, so a SECOND value-mover in
  ;; an unscoped transaction dies at this module's keyset check. Control measured: a non-managed
  ;; capability does not poison the transaction, so the trigger is the install specifically.
  ;;
  ;; 🔴 THE INSTALL IDENTITY EXCLUDES THE MANAGED PARAMETER (a platform trap), so the identity
  ;; is (tranche, target) and `amount` is the metered resource. THAT IS THE WANTED SHAPE AND IT
  ;; IS NOT ONE-SHOT: one approved budget per tranche AND destination, spendable across as many
  ;; calls as the operator likes, never exceeded in TOTAL. Two destinations need two entries.
  ;;
  ;; 🔴 THE COST IS REAL: an unscoped signature CANNOT drive this function. That does not touch
  ;; the deploy ceremony, which signs unscoped — this is a post-deploy operation — but every
  ;; disbursement must be signed scoped. The number the device shows is a LIMIT, which is the
  ;; whole point.
  (defcap DISBURSE (tranche:string target:string amount:decimal)
    @doc "Requires spt-gov, scoped to one tranche and one target. Managed on amount: the total that pair may receive across the transaction, spendable in parts, so the signature must name this capability."
    @managed amount DISBURSE-mgr
    (enforce-keyset GOV-KS))

  ;; The linear meter for DISBURSE, in this module's own TRANSFER-mgr shape (same arithmetic,
  ;; same refusal wording) so a reader who knows one knows the other. `managed` is what remains
  ;; of the approved budget; `requested` is this call. Returning the remainder is what makes the
  ;; budget spendable in parts, and the enforce is what makes the total binding.
  ;; 🔴 FREEZE BEHAVIOUR: this is a MANAGER function, never called directly and never callable
  ;; by a transaction — the engine invokes it on each acquisition of DISBURSE. It carries no
  ;; guard of its own by design; its authority is the defcap's. Frozen behaviour is therefore
  ;; identical to unfrozen, and the property that matters after the freeze is that the budget
  ;; still BINDS — pinned by name in the admin-tier test suite, not by calling this function.
  (defun DISBURSE-mgr:decimal (managed:decimal requested:decimal)
    @doc "Meter for DISBURSE: the engine calls it on each acquisition, subtracting this call amount from the SPT still approved for that tranche and target and returning the remainder. It refuses anything past the approved total."
    (let ((remainder (- managed requested)))
      (enforce (>= remainder 0.0)
        (format "DISBURSE exceeded: {} requested of {} managed" [requested managed]))
      remainder))

  ;; ---- THE OTHER TWO VALUE-MOVERS GET THE SAME TREATMENT ----------------------------------
  ;; Same rule as `DISBURSE`: ENFORCE `GOV-KS` DIRECTLY, NEVER `compose-capability (ADMIN-GOV)`,
  ;; which would put the tier back on the stack and reopen the hole these exist to close.
  ;;
  ;; 🔴 WHY THEY ARE `@managed`: `amount` is KDA leaving an account — the same linear resource
  ;; DISBURSE meters. Left unmanaged, an unscoped gov signature moved KDA for an amount and to
  ;; a destination the signature never named (measured on a node, mined, both clists empty on
  ;; the wire) while the founder-facing page promised the opposite. `@managed` is the ONLY
  ;; construct that makes "the signature must name it" true.
  ;;
  ;; 🔴 THE INSTALL IDENTITY EXCLUDES THE MANAGED PARAMETER (platform trap), so WITHDRAW-FUNDING
  ;; is identified by its destination — one approved total each, two destinations needing two
  ;; entries — and RECOVER-SURPLUS by the capability alone, which is right because recovered KDA
  ;; can only return to the funding account.
  ;; 🔴 THESE TWO ARE NOT SPENDABLE IN PARTS, unlike DISBURSE. Both wrap an inner coin transfer
  ;; whose own install identity is the (from, to) pair, so a SECOND partial call to the same
  ;; destination dies there — before this meter is consulted, and naming the inner capability
  ;; rather than this one, which misleads an operator reading the error. Say it per capability,
  ;; never as a blanket claim.
  (defcap WITHDRAW-FUNDING (to:string amount:decimal)
    @doc "spt-gov, managed on amount: the signature MUST name this capability and the amount it approves for this destination is a real spending limit that cannot be exceeded. ONE call per destination per transaction — a second call to the same destination is refused by the inner coin transfer, not by this capability. An unscoped signature cannot drive it at all."
    @managed amount WITHDRAW-FUNDING-mgr
    (enforce-keyset GOV-KS))

  (defun WITHDRAW-FUNDING-mgr:decimal (managed:decimal requested:decimal)
    @doc "Meter for WITHDRAW-FUNDING: the engine subtracts this amount from the KDA approved for that destination and refuses anything past the total. The remainder is not reusable, since only one withdrawal per destination settles per transaction."
    (let ((remainder (- managed requested)))
      (enforce (>= remainder 0.0)
        (format "WITHDRAW-FUNDING exceeded: {} requested of {} managed" [requested managed]))
      remainder))

  (defcap RECOVER-SURPLUS (amount:decimal)
    @doc "spt-gov, managed on amount: the signature MUST name this capability and the amount it approves is a real spending limit that cannot be exceeded. ONE call per transaction — a second is refused by the inner coin transfer, not by this capability. There is no destination parameter because recovered KDA can only return to the funding account. An unscoped signature cannot drive it at all."
    @managed amount RECOVER-SURPLUS-mgr
    (enforce-keyset GOV-KS))

  (defun RECOVER-SURPLUS-mgr:decimal (managed:decimal requested:decimal)
    @doc "Meter for RECOVER-SURPLUS: on each acquisition the engine subtracts this amount from the KDA approved for recovery and refuses anything past the total. The remainder is not reusable, since only one recovery settles per transaction."
    (let ((remainder (- managed requested)))
      (enforce (>= remainder 0.0)
        (format "RECOVER-SURPLUS exceeded: {} requested of {} managed" [requested managed]))
      remainder))

  (defcap VOTE-KEY-ADMIN (account:string)
    @doc "Gates registering and clearing an account vote key. Satisfied only by the account main guard, never by the vote key itself, so a signature can be scoped to just this action."
    (enforce-guard (account-guard account)))

  (defcap ROTATE (account:string)
    @doc "Gates guard rotation for account. Satisfied only by the account current stored guard, so a signature can be scoped to rotation alone."
    (enforce-guard (account-guard account)))

  (defcap VOTE (voter:string)
    @doc "Authorizes voter: satisfied by the account main guard or, when registered and active, its vote key. The main guard always works, so registering a key cannot lock the owner out."
    (let ((main (account-guard voter)))
      (with-default-read vote-delegates voter
        { "guard": main, "active": false }
        { "guard" := vg, "active" := act }
        (enforce-one "neither account guard nor registered vote key satisfied"
          [ (enforce-guard main)
            (if act (enforce-guard vg) (enforce false "no vote key registered")) ]))))

  ;; ---- TRANSFER CAPABILITIES (fungible-v2 + fungible-xchain-v1) ----------------------------
  (defcap DEBIT (sender:string)
    @doc "Authorizes debiting sender: enforces the sender account guard."
    (enforce-guard (account-guard sender)))

  ;; ---- `credit` IS A PUBLIC WRITER GATED BY A WEAK-BODIED `CREDIT` -------------------------
  ;; This is exactly `coin`'s own shape, and the case for deleting it instead is persuasive
  ;; enough to answer here rather than leave to be rediscovered.
  ;; The alternative — never rest the supply invariant on the engine when a contract-layer
  ;; invariant is available — offers a choice that does not exist. Every guard, every transfer,
  ;; gas payment and consensus itself already rest on that engine, and `coin.credit` is
  ;; protected by precisely this and nothing else. If SPT's credit were forgeable, coin's would
  ;; be too, and the network would be minting KDA. So the trade is not engine-trust versus
  ;; code-trust; it is engine-trust plus FOUR duplicated writers versus engine-trust plus one —
  ;; and the duplication is not free, because this credit also maintains three solvency
  ;; counters, making four copies four places to get the checkpoint wrong.
  ;;
  ;; 🔴 THIS IS NOT A LICENCE TO ADD OTHER PUBLIC WRITERS. The non-transferable reserves, the
  ;; tally writes inlined into cast-vote and debit, and the inlined index writer all stay as
  ;; they are, because they rest on ENGINE-INDEPENDENT properties — `debit` hard-rejecting
  ;; protocol accounts does not care what is on the capability stack. This is ONE function,
  ;; public for ONE reason: `coin` parity.
  ;;
  ;; Two "fixes" get re-proposed and both are wrong:
  ;;   * input validation — `credit-plan` already enforces a positive amount and the unit; an
  ;;     attacker passes a perfectly valid positive amount, so it changes nothing.
  ;;   * requiring MINT or DEBIT on the writer — a capability in scope is NOT value moved: the
  ;;     attacker composes DEBIT of their own account as fake backing.
  (defcap CREDIT (receiver:string)
    @doc "Authorizes crediting receiver; the body only rejects an empty account name, so it proves nothing about backing — each caller must establish that on its own path. A foreign module cannot acquire it, but module governance can."
    ;; Same check as coin's, with an SPT-unique string — see the error-prefix note below.
    (enforce (!= receiver "") "SPT credit receiver must not be empty"))


  ;; ---- THERE IS NO `TALLY` AND NO `AGGREGATE` CAPABILITY, AND THERE MUST NOT BE -----------
  ;; Both were weak `true`-bodied capabilities gating PUBLIC writers, which meant any live tally
  ;; could be set to any value and honest votes erased. They are not to be replaced by stronger
  ;; capabilities either: a `true` body authorizes nobody, and a body asserting public state is
  ;; not an authorization — that substitution reads as protection and is not.
  ;; Instead the writers they gated do not exist as named functions at all. Their writes are
  ;; inlined into `cast-vote` (VOTE-gated) and `debit` (DEBIT-gated under a real TRANSFER), with
  ;; the shared computation in the pure planner. A capability with nothing left to gate is an
  ;; attractive nuisance, so neither name is kept "just in case".

  ;; ---- WHY THE "SPT " PREFIX ON ERROR MESSAGES --------------------------------------------
  ;; 🔴 DO NOT "TIDY" IT AWAY. A test's `expect-failure` matches by SUBSTRING, so a negative
  ;; whose expected string is also a substring of a message `coin` can raise is satisfied by
  ;; COIN failing rather than by us — the branch it names goes untested while the suite stays
  ;; green. Nine of these messages would otherwise be character-for-character identical to a
  ;; coin message, and that collision has been reached by accident twice. Every SPT-raised
  ;; message is unique to SPT, the public runbooks quote them verbatim, and they FREEZE.
  (defcap TRANSFER:bool (sender:string receiver:string amount:decimal)
    @doc "Authorizes moving amount SPT from sender to receiver and emits the canonical transfer event; an empty account marks a mint or a cross-chain leg. Managed on amount: one install is a total budget for that pair, spent down by each transfer."
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "sender and receiver must differ")
    (enforce (> amount 0.0) "SPT transfer amount must be positive")
    (enforce-unit amount)
    ;; Acquiring this @managed cap EMITS the canonical fungible-v2 TRANSFER event, and that
    ;; event is what every indexer rebuilds balances from. Without the enforce below, the cap
    ;; can be acquired WITHOUT any transfer happening and a transaction committed publishing a
    ;; reserve-sized TRANSFER that never occurred — balances untouched, indexers misled.
    ;; Blocking the sender here costs nothing legitimate: `debit` already rejects these
    ;; accounts, so no honest path acquires either cap with one.
    (enforce (not (protocol-account? sender))
      "protocol accounts cannot send SPT; tranche SPT leaves only by vesting")
    ;; Composes BOTH authorizers, which is coin's shape. `debit` runs lexically before the
    ;; credit inside `transfer-create` under this same cap, so a credit on this path cannot
    ;; happen without a real debit.
    ;;
    ;; 🔴🔴 THE ORDER OF THE NEXT TWO LINES IS LOAD-BEARING. DO NOT SWAP THEM, AND DO NOT
    ;; "SIMPLIFY" THEM. Composing a capability RUNS its body, and `DEBIT`'s body evaluates the
    ;; SENDER'S OWN GUARD — which, for several legitimate guard shapes, is CALLER-SUPPLIED CODE
    ;; running inside this acquisition. Composing DEBIT FIRST means `CREDIT receiver` is not yet
    ;; on the capability stack while that code runs, so a re-entrant call into `credit` is
    ;; refused by its own `require-capability`.
    ;; 🔴 SWAPPED, THIS MINTS. Measured on a swapped copy, two different guard shapes each took
    ;; circulating supply from 2,000 to hundreds of thousands. A third shape is separately
    ;; blocked by the engine evaluating guards read-only — so a reader who tests only THAT
    ;; shape concludes this order is defence in depth, and that conclusion is FALSE. For the
    ;; other two it is the SOLE barrier.
    ;; This text exists because IT FREEZES, and the only other record is a test file a future
    ;; editor reordering two lines for tidiness would never open.
    (compose-capability (DEBIT sender))
    (compose-capability (CREDIT receiver)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    @doc "Meter for TRANSFER: the engine calls it on each acquisition, subtracting the transfer amount from the SPT still approved for that sender and receiver and returning the remainder. It refuses anything past the approved total."
    (let ((remainder (- managed requested)))
      (enforce (>= remainder 0.0)
        (format "TRANSFER exceeded: {} requested of {} managed" [requested managed]))
      remainder))

  (defcap TRANSFER_XCHAIN:bool (sender:string receiver:string amount:decimal target-chain:string)
    @doc "Authorizes and announces the departing leg of a cross-chain transfer: amount SPT debited from sender here for receiver on target-chain. Managed one-shot, so the installed amount is consumed whole by a single transfer."
    @managed amount TRANSFER_XCHAIN-mgr
    (enforce (> amount 0.0) "cross-chain amount must be positive")
    (enforce-unit amount)
    ;; 🔴 THE TARGET MUST BE A REAL CHAIN. Without this, step 0 debits and yields to a chain
    ;; that does not exist, no continuation can ever run, and the SPT is DESTROYED — reachable
    ;; by a typo, unbounded and silent. It sits in the DEFCAP rather than step 0 so it also
    ;; binds the managed capability: a signature scoped to a bogus chain cannot be acquired.
    ;; Do NOT add a separate empty-string check: "" is not a valid id, so that branch could
    ;; never fail, and a branch that cannot fail cannot be proven by a negative test.
    (enforce (contains target-chain coin.VALID_CHAIN_IDS) "target-chain is not a valid chain id")
    ;; ---- THE RESERVE RECEIVE-BLOCK MUST BIND *HERE*, NOT IN THE RESUME -----------------
    ;; 🔴 Put this enforce only in the resume — after step 0 has already debited — and a
    ;; cross-chain send to a reserve passes step 0 while the resume aborts FOREVER. A
    ;; cross-chain yield has NO ROLLBACK, so those tokens are DESTROYED: strictly worse than
    ;; the stranding this check exists to prevent.
    ;; SPT is deliberately STRICTER than coin here, so do not "align with coin" by moving it.
    ;; In the DEFCAP it is stronger than in step 0 — the cap is @managed, so a signature scoped
    ;; to a reserve receiver cannot even be ACQUIRED — and it is immediately testable, whereas
    ;; a resume-only copy is not, so a mutation deleting one would survive every suite.
    (enforce (not (protocol-account? receiver))
      "protocol accounts cannot receive SPT")
    (enforce (not (protocol-account? sender))
      "protocol accounts cannot send SPT; tranche SPT leaves only by vesting")
    (enforce (!= (at 'chain-id (chain-data)) target-chain) "cannot xchain to same chain")
    (compose-capability (DEBIT sender)))

  (defun TRANSFER_XCHAIN-mgr:decimal (managed:decimal requested:decimal)
    @doc "One-shot meter for TRANSFER_XCHAIN: on acquisition the engine refuses a request larger than the installed amount, then zeroes the budget. One installed signature therefore authorizes exactly one cross-chain send, never several partial ones."
    (enforce (>= managed requested) "cross-chain transfer exceeds installed amount")
    0.0) ; one-shot

  ;; WEAK BY DECISION: emitted by the cross-chain RESUME, which carries no signer, so there is
  ;; no capability to require. It is also how indexers reconstruct cross-chain balances, which
  ;; makes the forgery worth naming rather than leaving silent — an indexer trusting this
  ;; stream can be shown a credit that never happened. 🔴 READ THE TABLE, NOT THE STREAM.
  (defcap TRANSFER_XCHAIN_RECD:bool
    (sender:string receiver:string amount:decimal source-chain:string)
    @doc "Announces the arriving leg of a cross-chain transfer: amount SPT credited to receiver on this chain, sent from source-chain. sender is always empty here, as the continuation carries no sender identity; confirm arrivals against the ledger."
    @event true)

  ;; A SEPARATE capability rather than the bare tier, because this is the one admin action a
  ;; wallet is expected to scope a signature to routinely, and a distinct name is what makes
  ;; that scoping possible.
  ;; 🔴 GOV, NOT OPS: it moves KDA OUT of funding, and the rule above is explicit that moving
  ;; value out is the gov tier. It was the first link in a measured one-device extraction
  ;; chain. It is a SCHEDULED operation, so the second device costs nothing operationally.
  (defcap FUND-AWARDS () @doc "spt-gov: authorizes funding the award pool on this chain." (enforce-keyset GOV-KS))

  ;; ========================================================================
  ;; HELPERS
  ;; ========================================================================
  (defun curr-time:time ()
    @doc "The consensus block time this module treats as now: voting windows, record dates and round effective-at judge against it. Anyone. It is a block timestamp, not wall clock, the same for every read in a transaction, and can trail real time."
    (at 'block-time (chain-data)))
  (defun this-chain:string ()
    @doc "The Chainweb chain id this SPT instance runs on. Anyone. SPT state is per chain: balances, votes, tallies, awards and rounds belong to the chain you called, so record this id beside any figure read from here."
    (at 'chain-id (chain-data)))
  (defun account-guard:guard (account:string)
    @doc "The guard stored on an account row on THIS chain: the authority a debit or guard rotation must satisfy, and whose principal receives that account KDA awards. Aborts if the account has no row here, and it is the main guard, never a vote key."
    (at 'guard (read accounts account)))
  (defun get-round-count:integer ()
    @doc "How many award rounds THIS chain has declared; rounds are index addressed 1..n and read with get-round. Anyone. A retracted round still counts, since its rate is zeroed rather than deleted, and a chain missing a replication reads lower."
    (at 'n (read round-count ROUND-COUNT-KEY)))

  ;; The GLOBAL reward-per-token right now: what has been folded in, PLUS any declared round
  ;; already effective but not yet folded here. A PURE read, so it is safe on the hot paths.
  ;; 🔴 This is what makes rpt identical on every chain the instant a round becomes effective,
  ;; without `apply-round` having run: it derives from the identically-replicated round list
  ;; and consensus block time, so drift is impossible. `apply-round` only MATERIALIZES it for
  ;; O(1) reads — correctness never depends on it having been called.
  (defun get-rpt:decimal ()
    @doc "The cumulative KDA award per SPT token on THIS chain from every round already effective, including any apply-round has not folded in yet. Anyone. It is a rate since init, not one round and not what an account is owed; see pending-awards-of."
    (with-read state STATE-KEY { "reward-per-token" := folded, "rounds-applied" := applied }
      (let* ((n (get-round-count))
             (now (curr-time))
             (pending (if (>= applied n) []
                        (filter (!= 0.0)
                          (map (lambda (i:integer)
                                 (with-read award-rounds (rkey i)
                                   { "rate" := rate, "effective-at" := eff }
                                   (if (<= eff now) rate 0.0)))
                               (enumerate (+ applied 1) n))))))
        (fold (+) folded pending))))
  (defun get-circulating:decimal ()
    @doc "The SPT float on THIS chain that earns awards; treasury, founder, liquidity and launch reserves sit outside it. Anyone. Not total supply, and not what a round is priced against: that is the float sealed at the record date."
    (at 'circulating-supply (read state STATE-KEY)))

  ;; ---- THE RECORD-DATE SNAPSHOT ------------------------------------------------------------
  ;; 🔴 READ THIS BEFORE CHANGING ANY LINE BELOW. The mechanism is three equations and every
  ;; one is load-bearing in a module that FREEZES.
  ;;
  ;;   (1) THE PER-ACCOUNT CLAIM, with m = rpt when snap-index is 0, else min(rpt, base+rate):
  ;;         owed = pending + balance*(rpt - reward-debt)
  ;;                        + (snap-balance - balance)*(m - reward-debt)
  ;;       The third term is the ENTIRE change, and it is identically zero when no generation
  ;;       has sealed, when the account has not written since the record instant, and while the
  ;;       round is not yet effective. With reward-debt = base and the round effective it
  ;;       collapses to `snap-balance * rate` — the holder is paid on the balance they held AT
  ;;       THE RECORD INSTANT, so the chain's total is exactly rate x sealed float.
  ;;       The `min` caps the correction to THIS generation's round, so a LATER round pays on
  ;;       the current balance. Pact has no `min` native, hence the explicit `if`.
  ;;
  ;;   (2) THE O(1) LIABILITY:
  ;;         L = [ sum-pending + rpt*circulating - sum-debt ] + snap-corr + OPEN
  ;;
  ;;   (3) THE SETTLE IDENTITY, which is why `advance-snapshot` runs where it does:
  ;;         Sum over accounts checkpointed in generation g of (snap-balance - balance)
  ;;           = circ(g) - circulating
  ;;       Both numbers are already stored, which is why this needs no fifth counter.
  ;;       🔴 IT STOPS HOLDING the moment any checkpointed account re-bases its reward-debt,
  ;;       which is why the fold MUST happen before any such write.

  (defun snap-m:decimal (idx:integer rpt:decimal)
    @doc "Pure read: the rpt ceiling for a generation correction - rpt when idx is 0, else min(rpt, base + rate) of sealed generation idx on this chain. Aborts if that generation is not sealed."
    (if (= idx 0) rpt
      (with-read snapshots (gkey idx) { "base" := base, "rate" := rate }
        (let ((cap (+ base rate)))
          (if (< rpt cap) rpt cap)))))

  (defun snap-corr-of:decimal
      ( idx:integer snap-bal:decimal bal:decimal rd:decimal rpt:decimal )
    @doc "Pure read: one account record-date correction, (snap-bal - bal) * (snap-m idx rpt - rd). Exactly 0.0 when idx is 0; any other idx aborts unless that generation is sealed here."
    (if (= idx 0) 0.0
      (* (- snap-bal bal) (- (snap-m idx rpt) rd))))

  (defun snap-open:decimal (rpt-at:decimal)
    @doc "The part of the current generation correction that snap-corr does not yet hold, evaluated at the given reward per token. Reads 0.0 when the generation is settled or none has sealed on this chain."
    (with-read state STATE-KEY
      { "snap-gen" := g, "snap-settled" := settled, "circulating-supply" := circ }
      (if (or (= g 0) settled) 0.0
        (with-read snapshots (gkey g) { "circ" := gcirc, "base" := base, "rate" := grate }
          (let ((cap (+ base grate)))
            ;; (min rpt-at cap) - base : 0 before the round is effective, rate after it.
            (* (- (if (< rpt-at cap) rpt-at cap) base) (- gcirc circ)))))))

  (defschema snap-cp
    @doc "Result of planning an account record-date checkpoint: store index and balance on the account row, add corr to pending, and apply d-corr as a delta to state snap-corr."
    corr:decimal
    index:integer
    balance:decimal
    d-corr:decimal)

  (defun plan-snap:object{snap-cp}
      ( snap-index:integer snap-balance:decimal
        bal:decimal new-bal:decimal rd:decimal rpt:decimal )
    @doc "Plans one account record-date checkpoint and writes nothing; bal is the pre-operation balance and new-bal the post-operation one. Call advance-snapshot first, then apply the returned corr and d-corr."
    (with-read state STATE-KEY { "snap-gen" := gen }
      (let* ((corr (snap-corr-of snap-index snap-balance bal rd rpt))
             (fires (< snap-index gen))
             (ni (if fires gen snap-index))
             (nb (if fires bal snap-balance))
             ;; After the write reward-debt is rpt, so the new correction measures at rd=rpt and
             ;; the term is 0 — which is what makes this a ONE-SHOT transfer into pending
             ;; rather than something that accumulates.
             (ncorr (snap-corr-of ni nb new-bal rpt rpt)))
        { "corr": corr, "index": ni, "balance": nb, "d-corr": (- ncorr corr) })))

  (defun get-snapshot:object{snapshot-record} (g:integer)
    @doc "Reads this chain sealed generation g and never aborts: exists false means nothing ever sealed at that number. Rate 0.0 does not distinguish a generation with no round from a retracted one."
    (with-read state STATE-KEY { "snap-gen" := cur }
      (if (and (> g 0) (<= g cur))
        (with-read snapshots (gkey g) { "circ" := c, "base" := b, "rate" := r }
          { "gen": g, "exists": true, "circ": c, "base": b, "rate": r })
        { "gen": g, "exists": false, "circ": 0.0, "base": 0.0, "rate": 0.0 })))

  (defun get-snapshot-gen:integer () (at 'snap-gen (read state STATE-KEY)))
  (defun get-snapshot-at:time () (at 'snap-at (read state STATE-KEY)))
  (defun get-total-distributed:decimal ()
    @doc "Net KDA moved from funding into this chain award pool: fund-awards adds, recover-pool-surplus subtracts. It is per chain and can read negative."
    (at 'total-distributed (read state STATE-KEY)))

  (defun snapshot-circulating:decimal ()
    @doc "This chain float latched at the CURRENTLY sealed generation record instant. Reads 0.0 when no generation has ever sealed here. A scheduled record date that lands between this read and a declaration seals a NEW generation, and the declaration then prices against that one instead."
    (with-read state STATE-KEY { "snap-gen" := g }
      (if (= g 0) 0.0 (at 'circ (read snapshots (gkey g))))))

  ;; EXACT SOLVENCY — this chain's TRUE unclaimed liability, in O(1). This is what fund-awards
  ;; must cover; `circulating * rpt` alone UNDER-counts it by the crystallized pending of
  ;; tokens that have since left the chain.
  (defun award-liability:decimal ()
    @doc "The exact KDA this chain owes now for unclaimed awards, and what fund-awards must cover. Anyone. Per chain and current only: rounds not yet effective are excluded, see declared-liability, and get-rpt times get-circulating under-counts it."
    (with-read state STATE-KEY
      { "sum-pending" := sp, "circulating-supply" := circ, "sum-debt" := sd
      , "snap-corr" := sc }
      (let ((rpt (get-rpt)))
        (+ (+ sp (- (* rpt circ) sd)) (+ sc (snap-open rpt))))))

  ;; ---- SIZING THE AWARD POOL'S UNOWED SURPLUS ----------------------------------------------
  ;; `award-liability` answers "what is owed right now". Recovering pool cash needs the
  ;; STRICTER question — what could be owed under everything already DECLARED — because a chain
  ;; may legitimately be pre-funded ahead of a round that is not yet effective. That cash is
  ;; spoken for and must never read as surplus.
  (defun max-rpt:decimal ()
    @doc "The reward per token this chain will hold once every declared round is effective, including rounds whose effective-at is still in the future. Always at least get-rpt."
    (with-read state STATE-KEY { "reward-per-token" := folded, "rounds-applied" := applied }
      (let ((n (get-round-count)))
        (if (>= applied n) folded
          (fold (+) folded
            (map (lambda (i:integer) (at 'rate (read award-rounds (rkey i))))
                 (enumerate (+ applied 1) n)))))))

  (defun declared-liability:decimal ()
    @doc "This chain award liability at max-rpt: what it will owe once every declared round is effective, at the current float. Always at least award-liability."
    (with-read state STATE-KEY
      { "sum-pending" := sp, "circulating-supply" := circ, "sum-debt" := sd
      , "snap-corr" := sc }
      (let ((mrpt (max-rpt)))
        (+ (+ sp (- (* mrpt circ) sd)) (+ sc (snap-open mrpt))))))

  (defun pool-surplus:decimal ()
    @doc "Read-only: KDA in this chain award pool owed to nobody, even under every declared round. Negative means the pool is short. Floored to KDA precision, so this is the exact ceiling recover-pool-surplus accepts and the value can be passed straight back to it."
    ;; 🔴 THE FLOOR IS LOAD-BEARING, NOT COSMETIC. The liability accumulates rate x supply
    ;; products, so the subtraction lands at up to 24 decimal places while KDA carries 12 —
    ;; without this, the obvious call `(recover-pool-surplus (pool-surplus))` ABORTS on
    ;; precision, and the operator cannot use the number the module told them to use.
    ;; FLOOR is the safe direction: it can only UNDERSTATE the surplus, so it can never
    ;; authorize recovering a KDA that is owed. Rounding up, or to nearest, could.
    (let ((poolbal (try 0.0 (coin.get-balance POOL-ACCOUNT))))
      (floor (- poolbal (declared-liability)) (coin.precision))))
  ;; 🔴 THE LAUNCH RESERVE IS A CONSTANT, NOT STATE. Storing it would buy nothing and cost on
  ;; every transfer. A stored column could only ever hold LAUNCH-RESERVE-PIN — both one-shot inits
  ;; would have to enforce equality with the constant before writing it, and nothing may update it
  ;; afterwards — so the read can never return anything the constant does not already say. But
  ;; `excluded?` consults it on EVERY debit and EVERY credit, so a stored version charges a `state`
  ;; read forever, on a module that freezes. Measured: a stored column costs 219 gas on every
  ;; transfer (1223 vs 1004 with two active proposals, unchanged at eight), and the cost is wider
  ;; than the field — a narrower `state` row makes every `state` access cheaper, not just these two.
  ;; It also keeps the schema honest: the state schema forbids exactly this pattern — "DO NOT ADD A
  ;; STORED EXCLUSION FIELD HERE … nothing stored, nothing to mistype". A stored address is a severe
  ;; defect class; a constant cannot be mistyped at all.
  ;; 🔴 THE PIN STAYS LEGITIMATE ONLY WHILE THE NAMED DIVERGENCE TEST DOES — it compares
  ;; LAUNCH-RESERVE-PIN against SPT-launch's own derived value and goes RED if either moves.
  (defun get-launch-reserve:string ()
    @doc "The account name this module recognises as the launch sale reserve: a code constant, identical on every chain and settable by nobody. Anyone. It is excluded from awards, circulating supply and voting, but it can still transfer."
    LAUNCH-RESERVE-PIN)
  ;; Readable because a published notice window means nothing unless it can be confirmed on
  ;; each chain.
  (defun get-runway:integer ()
    @doc "The notice, in seconds, a new award round or record date must leave on THIS chain, never below MIN-RUNWAY. Anyone. Per-chain state that spt-gov changes with set-runway, so confirm it on each chain; declared dates are unaffected."
    (at 'runway-seconds (read state STATE-KEY)))
  ;; 🔴 THERE IS NO STORED TREASURY BENEFICIARY, AND NONE MAY BE ADDED — no state field, no
  ;; getter, no enforce, no event, no init argument. A stored exclusion is only needed when
  ;; module-owned tokens are paid on a schedule to a NAMED outside account, and no such payment
  ;; exists here: the reserves are DEFCONSTS, identical on all 20 chains, and leave only
  ;; through `disburse-tranche` to an account that is then an ordinary holder.
  ;; Re-adding one would buy nothing and revive a defect class: a well-formed but WRONG address
  ;; accepted there permanently disenfranchises a real holder on that chain, no on-chain check
  ;; can detect it, and after the freeze it is unfixable.
  (defun get-prop-count:integer ()
    @doc "How many proposals sit in THIS chain active proposal index now, at most MAX-ACTIVE-PROPOSALS. Anyone. Not a total ever created and not an id source: closing or cancelling pops a slot and moves the last entry into it, so the count falls."
    (at 'n (read prop-count PROP-COUNT-KEY)))

  (defun precision:integer ()
    @doc "The maximum decimal places an SPT amount may carry, fixed at 12 by this module; fungible-v2 requires the hook, not the value. Anyone. An amount finer than 12 places is refused rather than rounded."
    MINIMUM-PRECISION)

  (defun enforce-unit:bool (amount:decimal)
    @doc "Aborts unless amount is exact at the token minimum precision, returning true when it is. Anyone may call it; every transfer, debit and credit path applies it, so an amount with more decimal places is refused outright and never rounded."
    (enforce (= (floor amount MINIMUM-PRECISION) amount) "amount violates minimum precision"))

  (defun validate-account (account:string)
    @doc "Aborts unless the account name is 3 to 256 characters long and made only of Latin-1 characters. Anyone may call it; every path that can create an SPT holder runs it first, so a name outside those bounds can never hold SPT."
    (enforce (and (>= (length account) 3) (<= (length account) 256)) "account name length 3..256")
    (enforce (is-charset CHARSET_LATIN1 account) "account name has invalid characters"))

  ;; 🔴 THE ELSE-BRANCH REFUSES A RESERVED PREFIX, IT DOES NOT WAVE IT THROUGH. `is-principal`
  ;; is EXACT: "k:"+63 hex, "k:"+65 hex, "k:"+64 non-hex and "k:abc" are all FALSE, so a shape test
  ;; alone sends every one of them down the unchecked branch and accepts them UNDER ANY GUARD.
  ;; Measured: SPT accepted `k:`+63hex under an unrelated keyset where coin refuses it. The result
  ;; is a `k:`-prefixed account that is NOT self-custodial-by-name, permanently — so every
  ;; integrator applying the Kadena k:/w: convention is wrong about SPT, and a sender reasoning
  ;; "my receiver is a k: address, so squatting cannot apply" is wrong too.
  ;; This is coin's own rule: if the guard derives the name, accept; else if the name claims a
  ;; reserved prefix (`<char>:`), REFUSE; else it is an ordinary vanity name and passes.
  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "A name that claims a reserved prefix must be the principal of its guard. An ordinary name with no prefix passes unchanged."
    (if (validate-principal guard account)
      true
      (enforce (!= ":" (take -1 (take 2 account)))
        (format "SPT reserved protocol guard violation: {}" [account]))))

  (defun ensure-coin-account:string (account:string g:guard)
    @doc "Creates account in coin under guard g only when the row does not exist. Idempotent where coin.create-account is not; an existing row keeps its own guard, which is not checked against g."
    (if (< (try -1.0 (coin.get-balance account)) 0.0)
      (coin.create-account account g)
      "coin account already exists"))

  (defun protocol-account?:bool (account:string)
    @doc "True for the treasury, founder, liquidity, funding and pool accounts: they can never send or receive through the transfer API, rotate a guard or register a vote key. The tranche reserves still pay out, only via release-tranche or disburse-tranche; the launch reserve is not one of them and stays transferable."
    (or (= account TREASURY-ACCOUNT)
      (or (= account FOUNDER-ACCOUNT)
        (or (= account LIQUIDITY-ACCOUNT)
          (or (= account FUNDING-ACCOUNT)
              (= account POOL-ACCOUNT))))))

  (defun excluded?:bool (account:string)
    @doc "True for the three tranche reserves and the launch reserve: no award accrual, outside circulating supply, votes refused. It excludes a name, not an owner: the same key can vote from another account."
    ;; 🔴 NO DATABASE ACCESS AT ALL. All four reserves are defconsts, so this is four string
    ;; comparisons on the hottest path in the module — it runs on every debit and every credit.
    ;; Reading `state` for the launch reserve instead would cost a measured 219 gas per transfer
    ;; (REPL gas model) to retrieve a value the source already fixes — see `get-launch-reserve`.
    (or (= account TREASURY-ACCOUNT)
      (or (= account FOUNDER-ACCOUNT)
        (or (= account LIQUIDITY-ACCOUNT)
            (= account LAUNCH-RESERVE-PIN)))))

  ;; ---- GOVERNANCE — LIVE VOTE --------------------------------------------------------------
  ;; Vote weight is the voter's CURRENT tokens, and a re-vote updates in place. A transfer
  ;; SHRINKS the vote to what the sender's REMAINING balance can still back — releasing
  ;; max(0, voted - retained), retained = bal - debited — so no token ever backs two
  ;; live votes, and dust cannot suppress a vote because receiving never removes tokens.
  ;; CHAIN-LOCAL: every chain runs this machinery over its own replica, and votes never cross.
  (defun vkey:string (voter:string chain:string proposal:string)
    @doc "Returns the account-votes row key for one voter on one chain and one proposal: the hash of those three values as a list. Anyone may call it; hashing a list keeps element boundaries, so distinct triples can never collide on one key."
    ;; 🔴 A STRUCTURED hash, never a ':'-joined string: account names legally CONTAIN ':', so a
    ;; formatted key is ambiguous. Hashing the list keeps element boundaries, so distinct
    ;; triples can never collide.
    (hash [voter chain proposal]))
  (defun pkey:string (i:integer) (int-to-str 10 i))
  (defun rkey:string (i:integer) (int-to-str 10 i))   ; award-round key
  (defun gkey:string (g:integer) (int-to-str 10 g))   ; snapshot generation key
  (defun active-prop-indices:[integer] ()
    @doc "Indices 1 through the active-proposal count, or an empty list when the count is zero."
    (let ((n (get-prop-count))) (if (= n 0) [] (enumerate 1 n))))

  (defun proposal-active?:bool (proposal:string)
    @doc "True while status is active and close-at has not passed. It does not test open-at, so it is true before voting opens too, and the tally freezes at close-at whether or not anyone pays to close."
    (with-default-read proposals proposal { "status": "", "close-at": EPOCH }
      { "status" := st, "close-at" := cl }
      (and (= st "active") (< (curr-time) cl))))

  ;; ---- THE TALLY WRITER HAS NO NAME, DELIBERATELY -----------------------------------------
  ;; 🔴 A writer of critical state gets NO name and NO capability of its own, because a named
  ;; public writer is reachable by anything that can satisfy its gate. So there is deliberately
  ;; no `apply-tally` function and no `TALLY` capability gating one — with those, any live
  ;; tally could be set to any value and the honest votes erased.
  ;; Re-asserting trust inside such a function is insufficient: it blocks a POST-CLOSE forge
  ;; and cannot cover the pre-close window, because a live tally is legitimately mutable. And
  ;; no capability fixes it — a `true` body authorizes nobody, and a body asserting public
  ;; state is not an authorization either.
  ;; So `plan-tally` below is PURE: it reads, enforces and returns, and performs NO write. That
  ;; is what makes it safe to expose, and it is the same line `credit-plan` and `plan-deindex`
  ;; must never cross. Its two callers apply the returned row INLINE, under their own gates.
  (defschema tally-row yes:decimal no:decimal)

  (defun plan-tally:object{tally-row} (proposal:string dw:decimal direction:bool)
    @doc "Pure read: the tally row with dw added to the yes side when direction is true, else the no side; it aborts unless the proposal is open. It writes nothing, so the caller must write the row inline."
    ;; Re-asserted here rather than trusted: both callers check it, but this function is public.
    ;; Let-bound BEFORE the enforce — proposal-active? reads a table, and a table read inside an
    ;; enforce condition trips read-only mode on upstream-lineage nodes.
    (let ((open (proposal-active? proposal)))
      (enforce open "proposal not open for tally changes"))
    (with-read tallies proposal { "yes" := y, "no" := n }
      (if direction { "yes": (+ y dw), "no": n }
                    { "yes": y, "no": (+ n dw) })))

  ;; ========================================================================
  ;; PROPOSALS (admin) + VOTING (public)
  ;; ========================================================================
  (defun create-proposal:string
    (id:string title:string description:string
     created-at:time open-at:time duration-seconds:integer)
    @doc "spt-ops: announce a proposal; voting opens at open-at and closes at open-at plus duration-seconds. Submit the identical payload on every chain, at least the minimum review gap before open-at."
    (with-capability (ADMIN-OPS)
      ;; CHAIN-LOCAL voting: the admin submits this SAME payload to EVERY chain.
      ;; created-at and open-at are EXPLICIT (not block-time) so close-at is identical on all
      ;; chains — the per-chain tally freeze (proposal-active?) is one shared timestamp, not a
      ;; tx. It does not matter exactly when each chain's transaction lands, as long as it
      ;; lands before the notice deadline enforced below.
      (enforce (>= duration-seconds MIN-PROPOSAL-DURATION) "duration below 72h minimum")
      (enforce (<= duration-seconds MAX-PROPOSAL-DURATION) "duration above 14d maximum")
      ;; Bound the row's SIZE, not only how many rows exist. See MAX-PROPOSAL-CHARS.
      (enforce (<= (length id) MAX-PROPOSAL-ID-CHARS)
        "SPT proposal id exceeds the character budget")
      (enforce (<= (+ (length id) (+ (length title) (length description))) MAX-PROPOSAL-CHARS)
        "SPT proposal id + title + description exceed the combined character budget")
      (enforce (<= created-at (curr-time)) "created-at cannot be in the future")
      ;; ---- THE REVIEW GAP IS MEASURED FROM *THIS TRANSACTION*, NOT FROM CALLER DATA ----
      ;; 🔴 THE OBVIOUS FORM OF THIS CHECK IS WRONG. Comparing `open-at` against `created-at`
      ;; relates TWO CALLER-SUPPLIED TIMESTAMPS and bounds nothing: `created-at` is bounded only
      ;; from above, so BACKDATING IT COSTS NOTHING. Measured — a backdated created-at satisfies
      ;; every enforce and reports a full review gap while voting opens SIXTY SECONDS after the
      ;; announcement lands. The same shape reaches the duration, which is why `close-at`
      ;; derives from `open-at` and never from `created-at`.
      ;; So the notice is measured from the announcement's own BLOCK TIME, which no caller can
      ;; choose. It subsumes two other checks, which are therefore absent rather than stacked —
      ;; the check is dominated here.
      ;; It is also a real PER-CHAIN skew bound: each chain checks its own block time, so every
      ;; replica must land at least a full gap before the shared open-at, and a late chain is
      ;; REFUSED rather than silently giving its holders a shorter review.
      ;;
      ;; 🔴 WHAT IT COSTS: a missing replica is NOT fail-closed. Nineteen chains vote, the
      ;; twentieth reads back `exists:false` — degraded and visible rather than undecidable —
      ;; which puts the obligation on whoever sums the chains to assert all 20 exist first.
      ;; And after the freeze, overrunning the window is permanent: the un-announced chains can
      ;; never be added for this proposal, and the announced ones can never be withdrawn.
      ;; Abandon and re-announce with a FRESH id is the only recovery.
      (let ((notice (diff-time open-at (curr-time))))
        (enforce (>= notice MIN-REVIEW-GAP)
          "SPT voting must open at least the minimum review gap after this announcement"))
      ;; ---- `open-at` IS BOUNDED ONLY FROM BELOW, AND THAT IS A DECISION ----
      ;; An open-at in any year is accepted. The row then sits in the active index — which every
      ;; transfer scans — for the whole review gap plus the duration. No upper bound is added
      ;; deliberately: the drain is real but ALWAYS admin-endable, because cancelling is legal
      ;; for the entire period before open-at, so a mistyped year is recoverable by the admin
      ;; alone. A frozen maximum would put a policy number beyond revision to defend against a
      ;; typo that is already reversible.
      ;; 🔴 SO THE OPERATIONAL RULE: a proposal announced with a wrong open-at MUST BE
      ;; CANCELLED, NOT ABANDONED. Abandoning it leaves a permanent per-transfer tax on every
      ;; holder.
      ;; 🔴 REFUSE BEFORE ALLOCATING A SLOT — past this point the index has grown and every
      ;; later transfer pays for it.
      ;; 🔴 LET-BOUND, LIKE EVERY PRE-ENFORCE READ HERE. This was the one place the file broke
      ;; its own rule, because the read hides behind a zero-arg HELPER — so grepping for the
      ;; pattern returns nothing and only resolving the helper finds it. It survived eighteen
      ;; reviews that way.
      (let ((n (get-prop-count)))
        (enforce (< n MAX-ACTIVE-PROPOSALS)
          (format "SPT too many active proposals on this chain (max {}) — close a finished one first" [MAX-ACTIVE-PROPOSALS])))
      (let ((close-at (add-time open-at duration-seconds))
            (slot (+ (get-prop-count) 1)))
        ;; 🔴 close-at DERIVES FROM open-at, NEVER created-at, so the voting window is exactly
        ;; duration-seconds long and the minimum is enforced exactly rather than within a slack
        ;; window. The enforce below is DOMINATED by the notice bound and deliberately
        ;; untested — kept as defence in depth against a future change to either constant.
        (enforce (< (curr-time) close-at) "close-at already passed on this chain")
        ;; 🔴 INSERT THE PROPOSAL FIRST. It fails on a duplicate id BEFORE any index write, so a
        ;; rejected duplicate never bumps the count or dirties the index. The slot is stored on
        ;; the proposal for O(1) swap-and-pop removal later, so the transfer release loop scans
        ;; the INDEXED set rather than the ever-growing history.
        ;; 🔴 INDEXED, NOT "currently active": the index drains only when someone VOLUNTEERS gas
        ;; for the permissionless close, so an expired-but-unclosed proposal is re-read on every
        ;; transfer forever. Closing expired proposals is an operational duty; the module will
        ;; not do it for you.
        (insert proposals id
          { "title": title, "description": description, "created-at": created-at
          , "open-at": open-at
          , "close-at": close-at, "status": "active", "active-slot": slot })
        (insert tallies id { "yes": 0.0, "no": 0.0 })
        (write prop-index (pkey slot) { "id": id })
        (update prop-count PROP-COUNT-KEY { "n": slot }))
      (emit-event (PROPOSAL-CREATED id title))
      "proposal created"))

  ;; ---- THE INDEX WRITER HAS NO NAME EITHER -------------------------------------------------
  ;; The swap-and-pop is INLINED into close-proposal and cancel-proposal, fused with the status
  ;; update that makes it correct.
  ;; 🔴 WHY, MEASURED. Closing is permissionless, so its gate cannot be the admin keyset, and
  ;; the tempting substitute is a capability whose body asserts `status = "active"`. THAT IS A
  ;; PRECONDITION, NOT AN AUTHORIZATION — it asserts public state the attacker WANTS to be
  ;; true, so it authenticates nobody. Measured with the attacker holding zero tokens and
  ;; signing nothing: a LIVE proposal is popped out of the index while its status stays active,
  ;; the release loop never sees it again, and the same tokens then vote TWICE — a final tally
  ;; of double the circulating supply. The control that makes it decisive: the identical route
  ;; against a real keyset gate is BLOCKED, because a keyset authenticates and public state
  ;; does not.
  ;; A parameterised version is not sufficient either — it would let an outsider force an EARLY
  ;; close, which is what the close and cancel bounds exist to prevent. Pact has no private
  ;; functions, so the only way to make a state-transition writer unreachable on its own is to
  ;; not give it a name.
  (defschema deindex-plan
    @doc "Result of planning a swap-and-pop: whether an entry is popped, whether the tail moved, the target slot, the tail entry id, and the new count."
    pop:bool moved:bool slot:integer last-id:string new-n:integer)

  (defun plan-deindex:object{deindex-plan} (id:string slot:integer)
    @doc "Pure read: the swap-and-pop plan for removing id from the active-proposal index; it aborts unless slot is the recorded active-slot. It writes nothing, so the caller must apply the plan inline."
    ;; The (id, slot) pairing is re-asserted rather than trusted: a slot not belonging to this
    ;; id would write the tail entry into an unrelated position and decrement the count,
    ;; dropping a still-active proposal out of the release loop — after which the same tokens
    ;; can vote twice.
    (let ((recorded (at 'active-slot (read proposals id))))
      (enforce (= slot recorded) "slot does not match the proposal's recorded active-slot"))
    (let ((n (get-prop-count)))
      ;; UNREACHABLE ON A CONSISTENT INDEX, and deliberately untested — a mutation deleting
      ;; this line correctly SURVIVES the suite, which is stated plainly rather than papered
      ;; over. It is kept for one reason: the check above cannot catch a stale-but-
      ;; self-consistent slot, and if the index is ever corrupted this converts a SILENT
      ;; dropping of a live proposal into a hard abort. On a module that can never be patched,
      ;; that trade is worth one enforce.
      (enforce (<= slot n) "active-slot is out of the index range")
      (if (and (> n 0) (> slot 0))
        (let ((last-id (at 'id (read prop-index (pkey n)))))
          { "pop": true, "moved": (!= slot n), "slot": slot
          , "last-id": last-id, "new-n": (- n 1) })
        { "pop": false, "moved": false, "slot": slot, "last-id": "", "new-n": 0 })))

  ;; ---- DEDICATED VOTING KEY (hot key votes; transfer key stays cold) ----
  (defun set-vote-key:string (account:string guard:guard)
    @doc "Per chain, signed by the main guard: registers a k:, w: or r: keyset as the account vote guard, which may only vote. An r: reference resolves late, so whoever governs that keyset can vote for you."
    ;; Without this, a public VOTE-KEY-SET naming a reserve account can be emitted — a false
    ;; on-chain signal that the treasury had delegated its vote. There is no voting effect
    ;; (an excluded reserve cannot vote), so this is disclosure noise rather than value;
    ;; blocked anyway because it is one line.
    (enforce (not (protocol-account? account))
      "protocol accounts cannot register a vote key")
    ;; ---- THE GUARD IS AUTHORITY, SO IT IS VALIDATED ------------------------------------
    ;; 🔴 THE RULE: WHEN A FUNCTION TAKES AN ARGUMENT THAT BECOMES AUTHORITY, THE DOCSTRING
    ;; MUST SAY WHAT THAT ARGUMENT MAY AND MAY NOT BE — and the code must enforce it.
    ;; Unvalidated, this accepts THIS MODULE'S OWN module guard, which is satisfied whenever
    ;; the module is on the call stack — and inside `cast-vote` it always is, so an UNSIGNED
    ;; stranger casts the holder's full vote (measured).
    ;; THE ADMITTED SET IS THE GUARDS WHOSE SATISFACTION REDUCES TO SIGNATURES: `k:`, `w:` and
    ;; `r:`. Refused: module, capability, user and pact guards, every one of which can be
    ;; satisfied by something other than a signature — the whole property a voting delegate
    ;; must have.
    ;; 🔴 `r:` IS AN ACCEPTED RESIDUAL, NOT A PROPERTY: it encodes a keyset NAME, resolution is
    ;; LATE, and a delegate keyset rotated to empty afterwards is satisfied by anyone. It is
    ;; kept because it is a supported delegation, and disclosed in the docstring rather than
    ;; silently. Same for a custom-predicate `w:` — both are HOLDER-chosen at an owner-signed
    ;; registration, whereas `enforce-beneficiary` refuses custom predicates because that
    ;; surface is ADMIN-chosen, one-shot and worth most of supply.
    ;;
    ;; 🔴 THE TYPE TEST ALONE IS NOT THE PROPERTY — BOTH ENFORCES BELOW ARE LOAD-BEARING. A
    ;; keyset with NO KEYS is still a keyset, so the type test admits it, and `keys-all` over
    ;; an empty list is VACUOUSLY TRUE — an unsigned stranger casting a holder's full vote.
    ;; Rejecting the empty-keyset hash closes all three predicates at once, because the hash
    ;; covers the key list and the predicate is only a suffix.
    ;; Why not "the keyset has at least one key": Pact offers no keyset introspection from a
    ;; guard, so the count is unreachable here. If a future engine exposes it, use the count.
    (let ((p (create-principal guard)))
      (enforce (or (= (typeof-principal p) "k:")
                   (or (= (typeof-principal p) "w:") (= (typeof-principal p) "r:")))
        "SPT vote key must be a keyset guard (k:/w:/r:)")
      (enforce (!= (take (length EMPTY-KEYSET-PREFIX) p) EMPTY-KEYSET-PREFIX)
        "SPT vote key must not be an empty keyset"))
    (with-capability (VOTE-KEY-ADMIN account)
      (write vote-delegates account { "guard": guard, "active": true })
      (emit-event (VOTE-KEY-SET account (create-principal guard))))
    "vote key set")

  (defun clear-vote-key:string (account:string)
    @doc "Deactivates the account vote key on this chain, signed by the main guard. Requires a prior registration; voting falls back to the main guard alone."
    (enforce (not (protocol-account? account))
      "protocol accounts cannot register a vote key")
    (with-capability (VOTE-KEY-ADMIN account)
      (update vote-delegates account { "active": false })
      (emit-event (VOTE-KEY-CLEARED account)))
    "vote key cleared")

  (defun get-vote-key:object{vote-delegate} (account:string)
    @doc "Read-only: the vote-key registration as guard plus active; it aborts if the account has no SPT row. Never registered reads back as the main guard with active false, so check active, not the guard."
    (with-default-read vote-delegates account
      { "guard": (account-guard account), "active": false }
      { "guard" := g, "active" := a }
      { "guard": g, "active": a }))

  (defun cast-vote:string (voter:string proposal:string direction:bool)
    @doc "Vote or re-vote via the main guard or a registered vote key; weight is the voter's current balance on this chain, into this chain's tally. Open-at to close-at; no excluded reserve, no zero balance."
    (with-capability (VOTE voter)
      (with-read proposals proposal { "open-at" := op, "close-at" := cl, "status" := st }
        (enforce (= st "active") "proposal not active")
        ;; 🔴 THIS IS WHAT MAKES THE CANCEL WINDOW BLIND BY CONSTRUCTION, about THIS proposal,
        ;; rather than merely short. Delete it and `cancel-proposal`'s bound becomes
        ;; decorative: votes could accumulate during the review gap and be read before the
        ;; proposal was voided. The two enforces are ONE mechanism — read them together.
        (enforce (>= (curr-time) op) "SPT voting has not opened for this proposal yet")
        (enforce (< (curr-time) cl) "voting closed")
        ;; let-bound: see the read-only-mode rule. A green REPL is NOT evidence here.
        (let ((is-excluded (excluded? voter)))
          (enforce (not is-excluded) "excluded reserve cannot vote"))
        ;; ---- vote recording, INLINED -----------------------------------------------------
        ;; 🔴 Weight and chain are MODULE-DERIVED and cannot be supplied by anyone. As a
        ;; separate function they would be PARAMETERS, and Pact has no private functions — so
        ;; the voter could call it directly while every precondition that makes it safe lived
        ;; only in this wrapper, and a holder of one token could record any weight they liked,
        ;; on any chain, on a closed proposal. Inlining removes the trust boundary instead of
        ;; re-asserting it.
        ;; enforce-unit on the weight is deliberately NOT applied: a balance is already unit-
        ;; checked on every path into the table, so the branch could never fail.
        (let* ((chain (this-chain))
               (weight (get-balance voter))
               (k (vkey voter chain proposal)))
          (enforce (> weight 0.0) "no voting weight")
          (with-default-read account-votes k
            { "weight": 0.0, "direction": direction } { "weight" := oldw, "direction" := oldd }
            ;; 🔴 INLINED TALLY WRITES — never factor these into a function. Two sequential
            ;; applications: remove the old vote, then add the current one. The second plan
            ;; READS what the first write left, so the order is load-bearing.
            (if (> oldw 0.0)
              (update tallies proposal (plan-tally proposal (* -1.0 oldw) oldd))   ; remove old
              "")
            (update tallies proposal (plan-tally proposal weight direction))       ; add current
            (write account-votes k { "weight": weight, "direction": direction }))
          (emit-event (VOTE-CAST voter proposal weight direction))
          "vote cast"))))

  ;; ---- LIFECYCLE IS BOUNDED BY THE PROPOSAL'S OWN CLOCK ------------------------------------
  ;; `close-at` is the single shared timestamp replicated to all 20 chains, and it alone
  ;; decides when this chain's tally freezes. Neither admin transition may cross it:
  ;;   before close-at -> only CANCEL   (the outcome is not yet final)
  ;;   at/after        -> only CLOSE    (the outcome is final and already public)
  ;; 🔴 THE VETO IS CLOSED AT BOTH ENDS, and both directions are unfixable after the freeze.
  ;; Bounding cancel alone would leave two ways to void an outcome — cancel late with almost
  ;; full information, or simply never close. So closing is PERMISSIONLESS (its preconditions
  ;; are entirely objective, leaving nothing to exercise discretion over) and cancelling is
  ;; bounded to before voting opens. Two residuals survive, both stated on `cancel-proposal`.
  (defun close-proposal:string (id:string)
    @doc "Permissionless: mark a proposal closed once close-at has passed and drop it from the active index. Bookkeeping only since the tally already froze at close-at; a second call aborts the transaction."
    (let ((_ 0))
      (with-read proposals id { "status" := st, "active-slot" := slot, "close-at" := cl }
        (enforce (= st "active") "only active can close")
        ;; 🔴 THE EARLY-CLOSE BOUND. Without it a proposal can be closed BEFORE its deadline,
        ;; freezing this chain's tally early and rejecting every remaining holder while the
        ;; published voting window is still open. The truncated tally then reads as a
        ;; legitimate frozen result — nothing on chain distinguishes it from a complete one.
        (enforce (>= (curr-time) cl) "cannot close before voting has ended")
        ;; 🔴 INLINED SWAP-AND-POP — never factor this into a function. Fused with the status
        ;; update below, so "the index was popped" is a LEXICAL property of this block and
        ;; cannot happen without the transition that authorizes it.
        (let ((pl (plan-deindex id slot)))
          (if (at 'pop pl)
            (let ((_ 0))
              (if (at 'moved pl)                              ; move the tail into the freed slot
                (let ((__ 0))
                  (write prop-index (pkey (at 'slot pl)) { "id": (at 'last-id pl) })
                  (update proposals (at 'last-id pl) { "active-slot": (at 'slot pl) }))
                "")
              (update prop-count PROP-COUNT-KEY { "n": (at 'new-n pl) }))   ; pop the tail
            "")))
      (update proposals id { "status": "closed", "active-slot": 0 })
      (emit-event (PROPOSAL-CLOSED id "closed"))
      "proposal closed"))

  ;; ---- TWO RESIDUALS, CLOSED BY DISCLOSURE RATHER THAN BY CODE ----------------------------
  ;; NOT BLIND ACROSS CHAINS: one shared open-at is tested against twenty independent block
  ;; clocks, so voting can already be open on a fast chain while cancellation is still legal
  ;; on a slow one.
  ;; NOT BLIND ABOUT OTHER PROPOSALS: another proposal's voting window can sit inside this
  ;; one's cancel window.
  ;; 🔴 A CODE FIX WOULD MAKE HOLDERS WORSE OFF. Announcing is admin-gated, so the same
  ;; information needs no cancellation at all — announce a probe, read it, then decide whether
  ;; to announce the real vote. Refusing to cancel whenever another tally is live would remove
  ;; the path that IS recorded on chain while leaving the one that is not, and would cost the
  ;; only remedy for a genuinely mistaken proposal.
  (defun cancel-proposal:string (id:string)
    @doc "spt-ops: void a proposal on this chain, allowed only before ITS OWN open-at — the admin may still have seen live votes on a different proposal, or on another chain's clock. A cancelled replica has no result and makes the whole 20-chain set unsummable."
    (with-capability (ADMIN-OPS)
      ;; `created-at` is deliberately NOT bound: nothing here reads it, and binding it would
      ;; read as though a created-at bound still existed.
      (with-read proposals id
        { "status" := st, "active-slot" := slot, "close-at" := cl, "open-at" := op }
        (enforce (= st "active") "only active can cancel")
        ;; 🔴 THE LATE-CANCEL BOUND, and it is reachable because `status` stays "active" until
        ;; someone pays to close. After the deadline the frozen result is already publicly
        ;; readable, so cancelling then would flip the RECORD of an outcome the network has
        ;; already seen. A malformed proposal discovered late is NOT a reason to reopen this:
        ;; the on-chain result stays immutable and what the operator does with it is an
        ;; off-chain decision.
        (enforce (< (curr-time) cl) "cannot cancel after voting has closed")
        ;; ---- CANCEL ONLY BEFORE VOTING OPENS ------------------------------------------
        ;; 🔴 The deadline bound above is necessary but NOT sufficient: results are public and
        ;; LIVE for the whole voting window, so cancelling a second before the deadline would
        ;; be a near-full-information veto. This bound is what makes it blind about the
        ;; proposal it voids — and blind BY CONSTRUCTION, not by being short, because no vote
        ;; can exist before voting opens. So the review gap can be long enough to actually
        ;; notice a mistake. Prevention instead of correction.
        ;; 🔴 WHY NOT "BEFORE THE FIRST VOTE", since that is the obvious reach: the tally is
        ;; NOT MONOTONIC. A holder who votes and then transfers out has their weight released
        ;; back out of it, so a zero-votes bound would silently RE-OPEN the cancel window after
        ;; information had already leaked. This bound retires the hazard instead of defending
        ;; against it.
        (enforce (< (curr-time) op)
          "SPT cannot cancel once voting has opened for this proposal")
        ;; 🔴 INLINED SWAP-AND-POP — never factor this out; see `close-proposal`.
        (let ((pl (plan-deindex id slot)))
          (if (at 'pop pl)
            (let ((_ 0))
              (if (at 'moved pl)                              ; move the tail into the freed slot
                (let ((__ 0))
                  (write prop-index (pkey (at 'slot pl)) { "id": (at 'last-id pl) })
                  (update proposals (at 'last-id pl) { "active-slot": (at 'slot pl) }))
                "")
              (update prop-count PROP-COUNT-KEY { "n": (at 'new-n pl) }))   ; pop the tail
            "")))
      (update proposals id { "status": "cancelled", "active-slot": 0 })
      (emit-event (PROPOSAL-CLOSED id "cancelled"))
      "proposal cancelled"))

  ;; ---- results: THIS chain's tally, and nothing else ---------------------------------------
  ;; 🔴 `participation`, `quorum-met` and `passed` are deliberately ABSENT. With no cross-chain
  ;; aggregate they are actively misleading: a two-chain total can be genuinely quorate while
  ;; BOTH chains print `passed:false`, because a global-sized constant lands on a chain-local
  ;; denominator. `passed` in particular is a verdict this contract cannot support — the winner
  ;; is an off-chain sum of 20 rows, and a per-chain boolean that reads as a decision is a
  ;; number people screenshot.
  (defschema results
    @doc "The yes and no totals get-results returns for one proposal on this chain. It carries no participation, quorum or passed field on purpose, because a chain-local denominator cannot decide an outcome that is the sum of 20 chains."
    yes:decimal no:decimal)
  (defun results-of:object{results} (yes:decimal no:decimal) { "yes": yes, "no": no })
  (defun get-results:object{results} (proposal:string)
    (with-read tallies proposal { "yes" := yes, "no" := no } (results-of yes no)))
  (defun get-vote:object{account-vote} (voter:string chain:string proposal:string)
    (read account-votes (vkey voter chain proposal)))
  (defun vote-weight:decimal (voter:string chain:string proposal:string)
    @doc "Read-only: the recorded vote weight for this voter, chain and proposal, or 0 if none."
    (with-default-read account-votes (vkey voter chain proposal)
      { "weight": 0.0 } { "weight" := w } w))
  (defun proposal-details:object{proposal} (id:string)
    @doc "THIS chain replica of a proposal: title, description, created-at, open-at, close-at, status and active index slot. It aborts when this chain holds no such proposal, and status stays active past close-at, so read finality from vote-record."
    (read proposals id))

  ;; ---- THE PRODUCT: one read that makes the off-chain 20-chain sum self-proving ------------
  ;; Governance computes no winner on chain. The claim it makes instead is narrower and
  ;; provable: THIS chain's tally is what the contract recorded, and only `cast-vote` and
  ;; `debit`'s release loop can write it. The 20-chain audit is 20 read-only calls to this
  ;; function — no indexer, no block scan, no privileged access.
  ;;
  ;; 🔴 THE SUMMING RULE IS STATED ONCE, IN THIS FUNCTION'S @doc, AND NOWHERE ELSE. Two
  ;; statements of one rule is the defect: the copy drifts, and a top-down reader meets the
  ;; drifted one first. In particular, a restatement demanding that `status` AGREE across
  ;; chains is wrong — closing is permissionless and per-chain, so statuses legitimately
  ;; differ.
  ;;
  ;; Three properties of this read are load-bearing:
  ;;  * A MISSING REPLICA MUST NOT ABORT. A plain read aborts on an unknown id, which makes
  ;;    "this chain never got the proposal" and "this chain's node is unreachable" look
  ;;    identical to an auditor. This returns `exists:false` instead.
  ;;  * `frozen` DERIVES FROM close-at, NOT FROM `status`, because status stays "active" past
  ;;    the deadline until somebody pays to close. A summer keying on status would either
  ;;    refuse a final result or sum a live one.
  ;;  * A WHOLE-OBJECT COMPARISON PRODUCES FALSE DIVERGENCE, because some fields legitimately
  ;;    differ per chain. The digest covers exactly the fields that MUST agree, so one string
  ;;    comparison replaces knowing which fields to ignore.
  ;; The digest is computed AT READ TIME and never stored — a stored digest can drift from the
  ;; fields it claims to cover.
  ;; 🔴 `open-at` IS IN THE DIGEST AS A REQUIREMENT, NOT BOOKKEEPING: it decides when voting
  ;; opens and when cancellation shuts, so a replica with a different open-at IS A DIFFERENT
  ;; PROPOSAL. Outside the digest that divergence would be invisible to the 20-chain check
  ;; that is the entire product.
  (defschema vote-rec
    proposal:string chain:string exists:bool digest:string
    created-at:time open-at:time close-at:time status:string frozen:bool as-of:time
    yes:decimal no:decimal)

  (defun vote-record:object{vote-rec} (id:string)
    @doc "This chain's record for a proposal; a missing replica reads exists false instead of aborting. Sum yes and no only over 20 distinct chains with every row exists, frozen, digest-equal and not cancelled."
    (let ((now (curr-time)))
      ;; The "" status default doubles as the missing-row sentinel: it is not a value
      ;; `create-proposal` can write, so no second read is needed.
      (with-default-read proposals id
        { "title": "", "description": "", "created-at": EPOCH, "open-at": EPOCH
        , "close-at": EPOCH, "status": "" }
        { "title" := title, "description" := description
        , "created-at" := ca, "open-at" := op, "close-at" := cl, "status" := st }
        (let ((exists (!= st "")))
          (with-default-read tallies id
            { "yes": 0.0, "no": 0.0 } { "yes" := y, "no" := n }
            { "proposal": id
            , "chain": (this-chain)
            , "exists": exists
            ;; 🔴 THE TIMES ARE HASHED AS EPOCH DECIMALS, NOT AS `time` VALUES, because
            ;; hashing a `time` IS BLIND BELOW ONE SECOND: two times half a second apart are
            ;; NOT equal, yet they hash to the same digest, character for character.
            ;; It matters here and almost nowhere else, because the summing rule leans on
            ;; DIGEST EQUALITY and the replication is a script — exactly where a timestamp
            ;; picks up sub-second drift. The digest is the only thing standing between that
            ;; drift and a published tally, so its resolution must be finer than the drift.
            , "digest": (if exists
                          (hash [id title description
                                 (diff-time ca EPOCH) (diff-time op EPOCH) (diff-time cl EPOCH)])
                          "")
            , "created-at": ca
            , "open-at": op
            , "close-at": cl
            , "status": st
            , "frozen": (and exists (>= now cl))
            , "as-of": now
            , "yes": y
            , "no": n })))))

  ;; ---- READS (fungible-v2 + getters) -------------------------------------------------------
  (defun get-balance:decimal (account:string)
    @doc "An account SPT balance on THIS chain. Anyone. It aborts when the account has no row here rather than reading 0, and balances are per chain, so a holder total is an off-chain sum over all 20; unclaimed awards are separate."
    (at 'balance (read accounts account)))

  (defun details:object{fungible-v2.account-details} (account:string)
    @doc "The fungible-v2 account view for THIS chain: the account name, its balance here and its stored guard. Anyone. It aborts when the account has no row on this chain, and the guard returned is the main guard, never a registered vote key."
    (with-read accounts account { "balance" := bal, "guard" := g }
      { "account": account, "balance": bal, "guard": g }))

  (defun get-guard:guard (account:string) (account-guard account))

  (defun pending-awards-of:decimal (account:string)
    @doc "Read-only: this chain's unclaimed award accrual for account, in KDA; always 0 for an excluded reserve. A claim pays this floored to 12 decimals and carries the remainder forward as pending."
    (if (excluded? account)
      0.0
      (with-default-read accounts account
        { "balance": 0.0, "reward-debt": 0.0, "pending-awards": 0.0
        , "snap-index": 0, "snap-balance": 0.0 }
        { "balance" := bal, "reward-debt" := rd, "pending-awards" := pend
        , "snap-index" := si, "snap-balance" := sb }
        (let ((rpt (get-rpt)))
          (+ (+ pend (* bal (- rpt rd)))
             (snap-corr-of si sb bal rd rpt))))))

  ;; ---- DEBIT / CREDIT (per-leg float checkpoint inlined) -----------------------------------
  (defun debit (account:string amount:decimal)
    @doc "Removes amount SPT: settles award accrual, releases the vote weight the retained balance no longer backs, and lowers circulating supply. Needs DEBIT granted; protocol accounts and overdrafts abort, and excluded reserves only move balance."
    (require-capability (DEBIT account))
    ;; ---- THE THREE TRANCHE RESERVES ARE NON-TRANSFERABLE ------------------------------
    ;; 🔴 WITHOUT THIS REFUSAL 80% OF TOTAL SUPPLY IS REACHABLE with no keys and no tokens.
    ;; These three accounts are guarded by capability guards over weak caps, so the guard alone
    ;; is not a barrier — and the refusal REMOVES WHAT A FORGED GUARD WOULD UNLOCK rather than
    ;; strengthening the guard. The generic transfer path cannot touch a reserve at all, on any
    ;; engine, with any capability in scope: there is no guard left to forge, because no path
    ;; enforces one. (`release-tranche` does its own inlined reserve debit and never comes
    ;; through here.)
    ;; 🔴 THE COST, PERMANENT AFTER FREEZE: the ONLY way SPT leaves a tranche reserve is vesting
    ;; to the ceremony-fixed beneficiary. No administrative move, no correction, no
    ;; redirection.
    (enforce (not (protocol-account? account))
      "protocol accounts cannot send SPT; tranche SPT leaves only by vesting")
    (enforce (> amount 0.0) "SPT debit amount must be positive")
    (enforce-unit amount)
    ;; Settle and seal BEFORE anything below reads or writes. Bound in the same `let` as rpt to
    ;; keep the nesting of the module's most-audited function flat. 🔴 Never inside an enforce:
    ;; it WRITES, and a writing helper in an enforce condition aborts on some nodes.
    (let* ((_ (advance-snapshot))
           (rpt (get-rpt)))
      (with-read accounts account
        { "balance" := bal, "reward-debt" := rd, "pending-awards" := pend
        , "snap-index" := si, "snap-balance" := sb }
        (enforce (<= amount bal) "insufficient funds")
        (if (excluded? account)
          ;; An excluded reserve can never vote, so there is no vote to release. NO CHECKPOINT
          ;; HERE, deliberately: it is outside the float, contributing to neither the
          ;; denominator nor the liability, so it has no correction to freeze — and giving it a
          ;; snap row would put a non-float balance into the settle identity and break it.
          (update accounts account { "balance": (- bal amount) })
          ;; The record-date checkpoint, on the PRE-operation balance. The correction is
          ;; crystallized into pending ALONGSIDE the ordinary accrual — dropping it loses money
          ;; the module already owes.
          (let* ((cp (plan-snap si sb bal (- bal amount) rd rpt))
                 (cp-corr (at 'corr cp))
                 (new-pend (+ (+ pend (* bal (- rpt rd))) cp-corr)))
            ;; 🔴 INLINED VOTE RELEASE — never factor this into a function. As a separate
            ;; public function it would need a gate, and any weak gate lets an honest voter's
            ;; weight be erased. It has exactly ONE caller, so the trust boundary is removed
            ;; rather than re-asserted: the loop exists only inside the debit that authorizes
            ;; it. It shrinks the vote to what the RETAINED balance can back — max(0, voted -
            ;; retained), never min(debited, voted) — BEFORE the balance drops, so no token backs
            ;; two live votes, and it fires on EVERY chain — including cross-chain step 0,
            ;; which is what closes the cross-chain double-count.
            (let ((chain (this-chain)))
              (map (lambda (i:integer)
                     (let* ((pr (at 'id (read prop-index (pkey i))))
                            (k (vkey account chain pr)))
                       (if (proposal-active? pr)
                         (with-default-read account-votes k { "weight": 0.0, "direction": true }
                           { "weight" := w, "direction" := d }
                           (if (> w 0.0)
                             ;; 🔴 RELEASE ONLY WHAT THE RETAINED BALANCE NO LONGER BACKS.
                             ;; The intuitive formula — release the amount MOVED — is WRONG: it
                             ;; ignores what the voter KEEPS, so a voter whose balance exceeds
                             ;; their weight loses weight they still fully back. A stranger
                             ;; gifts tokens, the victim returns exactly what was gifted, ends
                             ;; where they started, and part of their vote is gone. A GRIEFER
                             ;; NEEDS NO SIGNATURE, because gifting is unilateral, and the loss
                             ;; AMPLIFIES across every proposal the victim has voted on.
                             ;; 🔴 THE TWO FORMULAS ARE ALGEBRAICALLY EQUAL WHENEVER THE VOTER
                             ;; HAS VOTED THEIR WHOLE BALANCE, so any test written that way
                             ;; passes under either one. The defect lives only in the gap.
                             (let* ((retained (- bal amount))
                                    (release (if (> w retained) (- w retained) 0.0)))
                               ;; Skipped when nothing is owed: this runs per active proposal on
                               ;; EVERY debit, so a no-op write is real gas on the hottest path
                               ;; — and a zero-valued event would tell an indexer a release
                               ;; happened when none did.
                               (if (> release 0.0)
                                 (let ((wrote (update account-votes k { "weight": (- w release) })))
                                   (update tallies pr (plan-tally pr (* -1.0 release) d))
                                   (emit-event (VOTE-RELEASED account pr release))
                                   "released")
                                 "fully-backed"))
                             "no-vote"))
                         "inactive")))
                   (active-prop-indices)))
            (update accounts account
              { "balance": (- bal amount), "reward-debt": rpt, "pending-awards": new-pend
              , "snap-index": (at 'index cp), "snap-balance": (at 'balance cp) })
            ;; Exact solvency counters. The pending delta carries the correction because it is
            ;; crystallized into pending, and snap-corr moves by the matching negative — the two
            ;; are ONE TRANSFER BETWEEN COUNTERS, never a change in what is owed.
            (with-read state STATE-KEY
              { "circulating-supply" := circ, "sum-pending" := sp, "sum-debt" := sd
              , "snap-corr" := sc }
              (update state STATE-KEY
                { "circulating-supply": (- circ amount)
                , "sum-pending": (+ sp (+ (* bal (- rpt rd)) cp-corr))
                , "sum-debt": (+ sd (- (* (- bal amount) rpt) (* bal rd)))
                , "snap-corr": (+ sc (at 'd-corr cp)) })))))))

  ;; ---- THE CREDIT COMPUTATION, SHARED — ONE PLANNER, ONE WRITER ---------------------------
  ;; `credit-plan` holds the whole receive-side checkpoint in exactly ONE place, and it is
  ;; PURE: it reads and returns, and performs no write.
  ;; 🔴 THERE IS EXACTLY ONE WRITER, `credit`, holding the only `(write accounts …)` in the
  ;; module. The purity of the PLANNER is a separate requirement standing on its own: it is
  ;; public, so anything that wrote in here would be an ungated writer regardless of what
  ;; gates `credit`.
  (defschema planned-credit
    @doc "Result of planning a credit: the new accounts row plus solvency-counter deltas. For an excluded reserve the balance still rises but every delta is 0.0, so d-circ does not track the credited amount."
    row:object{spt-account}
    d-circ:decimal
    d-pending:decimal
    d-debt:decimal
    d-corr:decimal)          ; delta to state.snap-corr (0.0 for an excluded reserve)

  (defschema mint-spec
    @doc "One reserve allocation for the one-shot init-supply mint."
    account:string guard:guard amount:decimal)

  (defschema tranche-spec
    @doc "One time-locked tranche of the one-shot init-supply calendar; both counts are days from init. Nothing vests before cliff-days, then it vests linearly to vest-days, which must be the larger."
    tranche:string beneficiary:string total:decimal
    cliff-days:integer vest-days:integer)

  (defschema founder-alloc
    @doc "One founder allocation for init-supply: a k: or w: address and its amount, on the fixed founder schedule. Amounts must sum to exactly FOUNDER-TRANCHE, and the account must exist before release."
    ;; 🔴 NO `guard` FIELD. The ceremony is given an ADDRESS and nothing else — how the keyset
    ;; behind it is built is the recipient's own responsibility, and the release reads the
    ;; guard from that account's own ledger row.
    account:string amount:decimal)

  (defun credit-plan:object{planned-credit} (account:string guard:guard amount:decimal)
    @doc "Pure preview of crediting amount to account: the new accounts row plus solvency-counter deltas, no writes. Aborts on an invalid name, a bad amount, or a guard differing from the stored one."
    ;; 🔴 NAME VALIDATION LIVES HERE, IN THE ONE PURE COMPUTATION EVERY CREDIT ROUTES THROUGH,
    ;; never copied to each caller — a per-caller copy is the shape that leaves the NEXT caller
    ;; unprotected. Without it, `create-account` rejects a too-short name while a transfer
    ;; creates a holder with that same name anyway, or with an EMPTY one.
    ;; It stays in the planner rather than the writer so it also covers anyone calling the
    ;; planner directly to preview a credit.
    ;; The SENDER side is deliberately NOT validated: a debit can only reach an EXISTING row,
    ;; and every row is created through a validating path, so the check could never fail.
    (validate-account account)
    (enforce (> amount 0.0) "SPT credit amount must be positive")
    (enforce-unit amount)
    (let ((rpt (get-rpt)))
      (with-default-read accounts account
        { "balance": -1.0, "guard": guard
        , "reward-debt": rpt, "pending-awards": 0.0
        , "snap-index": 0, "snap-balance": 0.0 }
        { "balance" := bal, "guard" := retg, "reward-debt" := rd, "pending-awards" := pend
        , "snap-index" := si, "snap-balance" := sb }
        (enforce (= retg guard) "SPT account guards do not match")
        (let* ((is-new (= bal -1.0))
               (cur-bal (if is-new 0.0 bal)))
          (if is-new (enforce-reserved account guard) true)
          ;; Credited tokens arrive UNVOTED, and a credit never affects the receiver's existing
          ;; recorded vote — which is why no branch here touches the votes or the tally, and
          ;; why dust cannot suppress.
          (if (excluded? account)
            ;; Excluded reserve: outside the float — no accrual, no counter movement and NO
            ;; checkpoint, since freezing a balance for it would put a non-float number into
            ;; the settle identity. Its snap fields pass through untouched rather than reset.
            { "row": { "balance": (+ cur-bal amount), "guard": retg
                     , "reward-debt": rd, "pending-awards": pend
                     , "snap-index": si, "snap-balance": sb }
            , "d-circ": 0.0, "d-pending": 0.0, "d-debt": 0.0, "d-corr": 0.0 }
            ;; Float account: crystallize accrued awards AND the record-date correction, then
            ;; re-base reward-debt. The counter deltas mirror `debit`.
            (let* ((cp (plan-snap si sb cur-bal (+ cur-bal amount) rd rpt))
                   (cp-corr (at 'corr cp)))
              { "row": { "balance": (+ cur-bal amount), "guard": retg
                       , "reward-debt": rpt
                       , "pending-awards": (+ (+ pend (* cur-bal (- rpt rd))) cp-corr)
                       , "snap-index": (at 'index cp), "snap-balance": (at 'balance cp) }
              , "d-circ": amount
              , "d-pending": (+ (* cur-bal (- rpt rd)) cp-corr)
              , "d-debt": (- (* (+ cur-bal amount) rpt) (* cur-bal rd))
              , "d-corr": (at 'd-corr cp) }))))))

  (defun credit:string (account:string guard:guard amount:decimal)
    @doc "Credit amount to account and maintain this chain's supply and award counters. CREDIT must already be in scope, and an existing account must already carry the supplied guard."
    (require-capability (CREDIT account))
    ;; Every enforce lives in the planner, so there is nothing to re-assert here and no second
    ;; copy to drift. This is the whole of the write.
    ;; 🔴 THE SNAPSHOT ADVANCE RUNS BEFORE THE PLAN, and the order is load-bearing both ways:
    ;; the planner reads the generation to decide whether this account's checkpoint fires, so
    ;; planning against a stale one would freeze the wrong balance — and it must precede any
    ;; account write, because the settle identity holds only while no checkpointed account has
    ;; re-based its reward-debt.
    (let* ((_ (advance-snapshot))
           (p (credit-plan account guard amount)))
      (write accounts account (at 'row p))
      (with-read state STATE-KEY
        { "circulating-supply" := circ, "sum-pending" := sp, "sum-debt" := sd
        , "snap-corr" := sc }
        (update state STATE-KEY
          { "circulating-supply": (+ circ (at 'd-circ p))
          , "sum-pending": (+ sp (at 'd-pending p))
          , "sum-debt": (+ sd (at 'd-debt p))
          , "snap-corr": (+ sc (at 'd-corr p)) })))
    "credit ok")

  ;; ---- fungible-v2 TRANSFER SURFACE --------------------------------------------------------
  (defun transfer:string (sender:string receiver:string amount:decimal)
    @doc "fungible-v2 transfer to a receiver that must already exist; amount must be positive and at most 12 decimals. Sender and receiver must differ, and protocol accounts can never receive."
    (enforce (!= sender receiver) "sender and receiver must differ")
    (enforce (> amount 0.0) "SPT transfer amount must be positive")
    (enforce-unit amount)
    (with-read accounts receiver { "guard" := g }
      (transfer-create sender receiver g amount))
    "transfer ok")

  (defun transfer-create:string (sender:string receiver:string receiver-guard:guard amount:decimal)
    @doc "fungible-v2 transfer, creating the receiver with receiver-guard if absent; an existing receiver must carry exactly that guard. Sender and receiver must differ, and protocol accounts can never receive."
    (enforce (!= sender receiver) "sender and receiver must differ")
    (enforce (> amount 0.0) "SPT transfer amount must be positive")
    (enforce-unit amount)
    ;; ---- A RESERVE MAY NOT RECEIVE EITHER ---------------------------------------------
    ;; 🔴 CLOSING THE EXIT WITHOUT CLOSING THE ENTRANCE MAKES A DEPOSIT PERMANENTLY DESTROYED
    ;; RATHER THAN MERELY STUCK. `debit` refuses every route out, and vesting is capped by the
    ;; lock row's immutable total — so a transfer into a tranche reserve settles, raises its
    ;; balance, and the deposited SPT has no exit on any engine, forever. The reserve
    ;; principals are published addresses, so a misdirected transfer is foreseeable user
    ;; error, not an exotic case.
    ;; It goes HERE and in the cross-chain resume, NOT in the credit planner, because the
    ;; one-shot mint routes through that helper and must be able to fund the reserves once.
    (enforce (not (protocol-account? receiver))
      "protocol accounts cannot receive SPT")
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      ;; `debit` runs lexically first under the same cap, so "a credit happened here"
      ;; structurally implies "a real debit happened".
      (credit receiver receiver-guard amount))
    "transfer-create ok")

  (defun create-account:string (account:string guard:guard)
    @doc "Creates a zero-balance SPT row for account under guard. Anyone may call it, but the name must validate, a name claiming a reserved prefix must be the principal of its guard, protocol names are refused, and an existing account aborts."
    (validate-account account)
    ;; ---- PROTOCOL NAMES ARE BLOCKED; ORDINARY VANITY SQUATTING IS NOT -----------------
    ;; The row would be inert either way, but refusing costs one line and reuses the predicate
    ;; that already governs send, receive, rotate and vote-key — and leaving a stranger able to
    ;; create a row for a PROTOCOL account on a frozen module invites exactly the "harmless
    ;; until it isn't" reasoning that produced the reserve-deposit trap above.
    ;; ACCEPTED, NOT FIXED: ordinary vanity squatting. Squat a name and a later transfer under
    ;; the rightful guard fails on the guard mismatch. That is coin's shape — the first writer
    ;; binds the name — and closing it needs a name registry this module should not grow before
    ;; a freeze. The operational answer is to use k:/w: PRINCIPAL accounts, which cannot be
    ;; squatted because the name IS the guard hash.
    (enforce (not (protocol-account? account))
      "protocol accounts cannot be created by an outside caller")
    (enforce-reserved account guard)
    ;; A zero-balance row needs NO checkpoint: index 0 makes the correction identically zero,
    ;; and the row's first credit checkpoints it correctly. Seeding the live generation here
    ;; would freeze a zero balance for an account that held nothing at the record instant —
    ;; which is already what 0 means.
    (insert accounts account
      { "balance": 0.0, "guard": guard
      , "reward-debt": (get-rpt), "pending-awards": 0.0
      , "snap-index": 0, "snap-balance": 0.0 })
    "account created")

  (defun rotate:string (account:string new-guard:guard)
    @doc "Replaces the account stored guard with new-guard and revokes any active vote key. Needs the current stored guard; a principal account may only rotate to a guard that still derives its name, and protocol accounts are refused."
    ;; Protocol accounts are refused outright. The rotation would be a no-op anyway, since a
    ;; reserve name IS the hash of its guard — but refusing costs one line and removes the LAST
    ;; writer the weak reserve capabilities can reach.
    (enforce (not (protocol-account? account))
      "protocol accounts cannot rotate their guard")
    (with-capability (ROTATE account)
      ;; A principal account must stay bound to its name; only a vanity account may rotate
      ;; freely. Without this, the name-to-guard invariant established at creation could
      ;; silently drift.
      (enforce (or (not (is-principal account)) (validate-principal new-guard account))
        "SPT: it is unsafe for principal accounts to rotate their guard")
      (update accounts account { "guard": new-guard })
      ;; 🔴 Rotating the main guard REVOKES any active vote key: recovery from a stolen key
      ;; must not leave the thief's delegate alive to keep re-voting the balance.
      (with-default-read vote-delegates account { "active": false } { "active" := act }
        (if act
          (let ((_ (update vote-delegates account { "active": false })))
            (emit-event (VOTE-KEY-CLEARED account))
            "vote key revoked")
          "no vote key")))
    "guard rotated")

  ;; ---- fungible-xchain-v1 — transfer-crosschain (2-step SPV defpact) -----------------------
  (defpact transfer-crosschain:string
    (sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    @doc "Two-step cross-chain send. Step 0 debits sender, releasing only the vote weight the retained balance no longer backs, then yields to target-chain; step 1 credits receiver under receiver-guard. Until it runs tokens are debited, not credited."
    (step
      (with-capability (TRANSFER_XCHAIN sender receiver amount target-chain)
        (validate-account sender)
        (validate-account receiver)
        ;; 🔴 STEP 0 MUST REFUSE EVERY PAIR STEP 1 WILL REFUSE, because step 0 has already
        ;; DEBITED by the time step 1 looks. Checking only the receiver's NAME and not the
        ;; (name, guard) PAIR lets a principal-shaped receiver whose guard does not derive it
        ;; pass here, get debited, and then abort in step 1 — tokens debited on the source
        ;; chain, never credited on the target, and no continuation can complete. Measured.
        ;; This is a deliberate, minimal deviation from coin, WHICH HAS THE SAME DEFECT: the
        ;; agreement was to work LIKE coin, not to inherit a path that destroys a holder's
        ;; tokens. It refuses nothing a correct caller would send.
        ;; 🔴 THIS IS AN ABORT, NOT A REPAIR — it costs nothing, grants no new power, and the
        ;; loss it prevents lands on a HOLDER who did nothing wrong, which is the one case where
        ;; the module owns the problem rather than the person who typed it.
        (enforce (not (protocol-account? receiver))
          "protocol accounts cannot receive SPT")
        ;; 🔴 A LIVE, ACCEPTED RISK — FOUNDER DECISION, NOT AN OVERSIGHT. If the receiver is a
        ;; VANITY name and a row for it ALREADY EXISTS on the TARGET chain under a different
        ;; stored guard, step 1 aborts, the sender was ALREADY DEBITED at step 0, and the tokens
        ;; are HOSTAGE — not burned. 🔴 MEASURED, AND THE WORD MATTERS: the failing continuation
        ;; does NOT consume the defpact. It stays open and completes as soon as that row carries
        ;; the yielded guard, so the squatter can rotate and release the funds at any later block
        ;; — which means there is a party who can DEMAND PAYMENT to do so. Tell a holder
        ;; "extortable", never "lost". Step 0 cannot detect it: it cannot read the target chain.
        ;; An earlier version refused vanity receivers outright and closed this. It was rolled
        ;; back deliberately: the reasoning is that coin accepts exactly this risk, so SPT can
        ;; too, rather than locking vanity holders out of cross-chain delivery.
        ;; 🔴 DO NOT "FIX" THIS BY REFUSING VANITY RECEIVERS. Re-opening it is a founder call,
        ;; not an audit finding.
        ;; 🔴 WHAT THAT DECISION DOES **NOT** TOUCH: the `enforce-reserved` below STAYS, and so
        ;; does the protocol-account refusal above. That is a different protection with a
        ;; different shape — it catches a PRINCIPAL-shaped name whose guard, supplied in THIS
        ;; transaction, does not derive it. A purely local judgement, needing no target-chain
        ;; read, refusing nothing a correct caller sends. Deleting it re-opens a SECOND,
        ;; separately measured destruction path.
        (enforce-reserved receiver receiver-guard)
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
        ;; A reserve may not be a cross-chain credit destination either.
        (enforce (not (protocol-account? receiver))
          "protocol accounts cannot receive SPT")
        ;; Authorized by the continuation itself: this step runs only against a proven yield
        ;; from OUR step 0, which performed the matching debit on the source chain. Receiver,
        ;; guard and amount come from the resume payload and never from caller input, so the
        ;; debit pairing holds across the chain boundary. The capability is ACQUIRED here
        ;; rather than composed, because there is no transfer cap in a resume.
        (with-capability (CREDIT receiver)
          (credit receiver rg amount))
        (emit-event (TRANSFER_XCHAIN_RECD "" receiver amount source-chain))
        "cross-chain credit ok")))

  ;; ---- INIT (supply creation + per-chain setup) --------------------------------------------
  (defun enforce-not-initialized ()
    @doc "Aborts if this chain has already been initialized, reading the flag that init and init-supply set. It is what makes each of those one-time; it says nothing about other chains, since every chain carries its own flag."
    (with-default-read init-state INIT-KEY { "initialized": false } { "initialized" := i }
      (enforce (not i) "module already initialized")))

  ;; ---- THE LAUNCH RESERVE ACCOUNT CANNOT BE MISTYPED ---------------------------------------
  ;; It is stored at init, has no setter, and drives `excluded?` — which gates voting rights,
  ;; award accrual AND the circulating-supply denominator. Accepted as a bare string, one typo
  ;; on one chain silently mis-classifies an account there, permanently and invisibly.
  ;; DERIVING IT FROM THE SALE MODULE IS IMPOSSIBLE: that module already depends on this one, so
  ;; a reference back is a load-time cycle and NEITHER module could be deployed first.
  ;;
  ;; 🔴 SO THE PRINCIPAL IS PINNED AS A LITERAL, AND THE PIN IS CONDITIONAL. A hand-built
  ;; principal string can diverge from the derived value on a module that can never be patched,
  ;; so the pin is legitimate ONLY while that divergence is LOUD — a NAMED test compares it
  ;; against the sale module's own value and goes RED the moment either side moves. DELETING
  ;; THAT TEST RE-OPENS THE HOLE THE PIN CLOSES.
  ;; What the pin closes that guard-binding alone cannot: the sale exists on chain 0 only, so
  ;; its cross-check runs ONCE rather than twenty times, while the spoke pair arrives as
  ;; transaction data. On the other 19 chains a well-formed impostor pair is internally
  ;; consistent and would otherwise be accepted.
  ;; 🔴 A MODULE GUARD *CAN* BE WRITTEN BY HAND IN TRANSACTION JSON — any text claiming
  ;; otherwise is false, and one naming a NON-EXISTENT module still validates. So the guard
  ;; alone is not operator-proof; the pinned NAME is what makes the pair unforgeable, and the
  ;; principal check binds the guard to that name.
  ;;
  ;; 🔴 DO NOT "HARDEN" THIS WITH `enforce-guard` ON THE LAUNCH GUARD. Evaluating a module guard
  ;; loads the module, the sale module is ABSENT on the 19 spokes, and init is one-shot on a
  ;; module that freezes — it would permanently brick setup on 19 of 20 chains. It looks exactly
  ;; like the natural next hardening. It is not.
  ;; No empty-keyset or predicate stack here, deliberately: exact equality against a fixed
  ;; literal is STRICTLY stronger and shorter, and reusing the beneficiary rules would be WRONG,
  ;; since they require a k:/w: principal and would reject the genuine reserve.
  (defun enforce-launch-reserve:bool (guard:guard)
    @doc "Enforce that the supplied launch reserve guard is the one that derives LAUNCH-RESERVE-PIN."
    ;; 🔴 THE ACCOUNT IS NOT A PARAMETER, DELIBERATELY. It is the pin, so it cannot be mistyped,
    ;; and an equality check against a value the caller supplied could not fail in any useful way.
    ;; What this enforces is the half that CAN fail and is load-bearing: the guard must derive that
    ;; exact name, because the guard is what `credit` stores as the authority over the launch
    ;; tranche. A guard that derives a different name would hand that tranche to someone else.
    (enforce (validate-principal guard LAUNCH-RESERVE-PIN)
      "launch reserve guard does not derive the pinned SPT-launch reserve principal"))

  ;; ---- THE CHECKS SPLIT BY WHAT THEIR INPUTS REQUIRE ---------------------------------------
  ;; The ceremony supplies an ADDRESS and no guard, so the checks needing only the address run
  ;; there, and the one needing a guard runs where a guard exists — at release, read from the
  ;; beneficiary's own ledger row. Most of them need only the address, the predicate check
  ;; included, because a `w:` principal carries its predicate in the STRING.
  ;; There is deliberately NO satisfiability check: Pact gives a module no accessor for a
  ;; guard's keys or predicate, so the class is unclosable in-module.
  (defun enforce-beneficiary-address:bool (beneficiary:string)
    @doc "Enforce the address-only beneficiary rules: a k: or w: principal, a built-in keyset predicate, and never the empty keyset."
    (validate-account beneficiary)
    (let ((ptype (typeof-principal beneficiary)))
      (enforce (or (= ptype "k:") (= ptype "w:")) "beneficiary must be a k:/w: principal")
      ;; 🔴 AND THE PREDICATE MUST BE A BUILT-IN. The empty-keyset pin below matches one keyset
      ;; hash exactly, and is SILENT ON THE CLASS: a keyset with a CUSTOM predicate is still a
      ;; `w:` principal, and its satisfaction reduces to an arbitrary module function that may
      ;; return true with no signature — a whole vesting tranche payable to an account anyone
      ;; can spend from. Multisig beneficiaries are unaffected.
      (enforce (or (= ptype "k:")
                   (contains (drop (length EMPTY-KEYSET-PREFIX) beneficiary)
                             BUILTIN-KEYSET-PREDS))
        "beneficiary keyset predicate must be a built-in"))
    ;; 🔴 THE SAME VACUOUS-KEYSET HOLE AS `set-vote-key`'s, and here it stands in front of a
    ;; WHOLE VESTING TRANCHE. A keyset with no keys is still a keyset, so the test above admits
    ;; it, and `keys-all` over zero keys is satisfied by ANYONE. Without this refusal the
    ;; permissionless release vests the tranche to it and an UNSIGNED transfer moves the whole
    ;; balance away. The one-shot mint and the freeze mean the check has to hold HERE — the ops
    ;; layer refuses non-principals too, but that is defence in depth and it does not freeze.
    (enforce (!= (take (length EMPTY-KEYSET-PREFIX) beneficiary) EMPTY-KEYSET-PREFIX)
      "beneficiary must not be an empty keyset"))

  (defun enforce-beneficiary:bool (beneficiary:string guard:guard)
    @doc "Enforce the full beneficiary rules: everything enforce-beneficiary-address checks, plus the name must be the principal of the supplied guard."
    (enforce-beneficiary-address beneficiary)
    ;; Belt and braces rather than load-bearing — the same check ran at account creation and
    ;; rotation refuses to move a principal off its guard. Kept because it costs nothing, and
    ;; because "it is guaranteed elsewhere" is how a guarantee quietly stops being true.
    (enforce (validate-principal guard beneficiary) "beneficiary guard/principal mismatch"))

  ;; ---- THERE IS NO PUBLIC TRANCHE WRITER, AND THERE MUST NOT BE ONE ------------------------
  ;; Tranche rows are written ONLY inside `init-supply`, in a lambda. A lambda body is not a
  ;; callable function, so it is lexically inlined and there is no name a forged capability can
  ;; reach.
  ;; 🔴 DO NOT REINSTATE A NAMED WRITER GATED ONLY ON A BARE `require-capability`. Pact has no
  ;; private functions, so that shape is reachable by a foreign module whenever an admin
  ;; signature is present in the transaction — and both tiers are equally reachable, so the tier
  ;; split is no reason to bring one back. Such a writer accepts a PLANTED ROW with an arbitrary
  ;; total and emits a forged event on the module's public disclosure anchor.
  ;; The blast radius is bounded — a planted row pays nothing, and overwriting a real tranche is
  ;; refused by the insert — which is why it is not fatal, NOT why it would be harmless. What it
  ;; produces is a lying public read and a forged disclosure event.
  ;;
  ;; 🔴 AND THE INSERT CUTS BOTH WAYS: `init-supply` INSERTS these rows, so a row planted before
  ;; it runs would make `init-supply` abort on that chain FOREVER. Nothing can plant one while
  ;; the only writer is that lambda — a future writer must not re-open the window.

  (defun init-supply:string
    (launch-guard:guard
     founders:[object{founder-alloc}])
    @doc "Chain 0 only, one time: mint total supply to the reserves and lock the vesting tranches, dated from this block time. Founder accounts must be distinct and their amounts must sum to FOUNDER-TRANCHE."
    (with-capability (ADMIN-GOV)
      (enforce (= (at 'chain-id (chain-data)) "0") "Supply init only on chain 0")
      (enforce-not-initialized)
      ;; Stated explicitly here as well: credit-plan -> enforce-reserved already binds this pair
      ;; while minting the launch tranche, but only on the is-new branch and only as a side
      ;; effect of the mint. The check that governs `excluded?` must not be a by-product of a
      ;; credit, and chain 0 must be checked the same way chains 1-19 are.
      (enforce-launch-reserve launch-guard)
      (enforce (= TOTAL-SUPPLY
                  (+ LAUNCH-TRANCHE (+ FOUNDER-TRANCHE (+ TREASURY-TRANCHE LIQUIDITY-TRANCHE))))
        "tranche totals do not sum to TOTAL-SUPPLY")
      ;; ---- THE FOUNDER LIST IS CEREMONY DATA — VALIDATED AS A SET ----------------------
      ;; Founder AMOUNTS are the one tranche quantity that is ceremony data rather than a source
      ;; constant, so what only the LIST AS A WHOLE can get wrong is checked here:
      ;;  * positive and precision-exact — too many decimals makes that founder's FINAL release
      ;;    non-unit and therefore permanently unclaimable in a frozen module;
      ;;  * distinct accounts — two rows would need one row key;
      ;;  * summing to EXACTLY the tranche, because that is what the reserve mint funds.
      ;;    Under-allocation strands reserve SPT forever, since nothing else can ever debit that
      ;;    account; over-allocation makes the LAST releases fail after earlier founders have
      ;;    drained the row.
      (let ((f-amounts (map (lambda (f:object{founder-alloc}) (at 'amount f)) founders))
            (f-accounts (map (lambda (f:object{founder-alloc}) (at 'account f)) founders)))
        ;; 🔴 DO NOT ADD A SINGLE-KEY-ONLY RULE HERE. The tempting argument is that it makes a
        ;; beneficiary nobody can ever satisfy unrepresentable. It does not hold: a single-key
        ;; address whose key NOBODY HOLDS — a typo, or a lost key — is the likelier real
        ;; mistake, is equally representable, and does IDENTICAL DAMAGE. Such a rule closes one
        ;; of two identical entrances while permanently banning every multisig founder on a
        ;; module that freezes. That is a cost, not a protection.
        ;; What protects this path is the FAILURE MODE, not a filter: the ceremony stores an
        ;; ADDRESS, the founder owns their own guard, and the release credits an account that
        ;; must ALREADY EXIST — so a wrong address pays nothing to nobody and refuses retryably,
        ;; with the tokens still in the reserve.
        (map (lambda (amt:decimal)
               (enforce (> amt 0.0) "SPT founder allocation amount must be positive"))
             f-amounts)
        (map (lambda (amt:decimal)
               (enforce (= amt (floor amt MINIMUM-PRECISION))
                 "SPT founder allocation amount violates precision"))
             f-amounts)
        (enforce (= (length f-accounts) (length (distinct f-accounts)))
          "SPT founder accounts must be distinct")
        (enforce (= FOUNDER-TRANCHE
                    (fold (lambda (acc:decimal amt:decimal) (+ acc amt)) 0.0 f-amounts))
          "SPT founder allocations must sum to FOUNDER-TRANCHE")
        ;; The per-row identity check runs HERE, not in the lock loop, because that loop also
        ;; writes the two MODULE-HELD rows whose beneficiary is a reserve principal these rules
        ;; must reject. Founder rows are the only ceremony-supplied identities, so their
        ;; validator belongs where their list is validated — same transaction, before any
        ;; write, over the exact list the loop maps.
        (map (lambda (f:object{founder-alloc})
               (enforce-beneficiary-address (at 'account f)))
             founders))
      ;; The ceremony's only identity inputs are the launch reserve pair and the founder
      ;; addresses — there is no treasury beneficiary to store or validate.
      (insert state STATE-KEY
        { "reward-per-token": 0.0, "circulating-supply": 0.0
        , "rounds-applied": 0
        , "total-distributed": 0.0, "sum-pending": 0.0, "sum-debt": 0.0
        ;; Generation 0 = nothing has ever sealed, so `declare-round` refuses until a record
        ;; date has been scheduled AND has landed. There is deliberately no "legacy" mode.
        , "snap-gen": 0, "snap-at": EPOCH, "snap-settled": false, "snap-corr": 0.0
        , "runway-seconds": MIN-RUNWAY })
      (insert prop-count PROP-COUNT-KEY { "n": 0 })
      (insert round-count ROUND-COUNT-KEY { "n": 0 })
      (ensure-coin-account FUNDING-ACCOUNT FUNDING-G)
      (ensure-coin-account POOL-ACCOUNT POOL-G)
      ;; ---- THE MINT, AND THE ONLY ONE THERE WILL EVER BE --------------------------------
      ;; The four amounts come from SOURCE constants whose sum is enforced above to equal
      ;; TOTAL-SUPPLY, so not even the admin can mint a different quantity, and the one-shot
      ;; init flag is set in this same transaction. Written as ONE block over a fixed list so
      ;; there is one place to audit rather than four copy-pasted ones.
      ;; 🔴 EACH MINT EMITS THE fungible-v2 MINT EVENT. Without it an indexer rebuilding
      ;; balances from the event stream — which is how every explorer and wallet does it —
      ;; never sees the initial supply and reads the whole token as zero. An empty sender means
      ;; mint, which is coin's own shape. It happens exactly once: an event missing here can
      ;; never be added later, by upgrade or otherwise.
      (map (lambda (m:object{mint-spec})
             (let ((acct (at 'account m)))
               ;; Emitted BEFORE the credit, matching coin. Ordering within a transaction is
               ;; what an indexer sees, so it follows the reference rather than diverging.
               (emit-event (TRANSFER "" acct (at 'amount m)))
               (with-capability (CREDIT acct)
                 (credit acct (at 'guard m) (at 'amount m)))))
           [ { "account": TREASURY-ACCOUNT,    "guard": TREASURY-G,  "amount": TREASURY-TRANCHE }
             { "account": FOUNDER-ACCOUNT,     "guard": FOUNDER-G,   "amount": FOUNDER-TRANCHE }
             { "account": LIQUIDITY-ACCOUNT,   "guard": LIQUIDITY-G, "amount": LIQUIDITY-TRANCHE }
             { "account": LAUNCH-RESERVE-PIN, "guard": launch-guard,   "amount": LAUNCH-TRANCHE } ])
      ;; ---- INLINED TRANCHE LOCKS -------------------------------------------------------
      ;; The pre-committed release calendar — rows plus disclosure events, atomic with the mint,
      ;; and inlined for the same reason the mint is: a lambda body is not a callable function,
      ;; so there is no named writer for a forged capability to reach.
      ;; 🔴 THE BENEFICIARY RULES ARE NOT APPLIED HERE, and that is correct rather than merely
      ;; redundant: they validate CEREMONY-supplied identity, the only ceremony rows are the
      ;; founder ones (validated above over this same list, before any write), and the two fixed
      ;; rows below would be REJECTED outright, since a reserve principal is not a k:/w: one.
      ;; 🔴 IF A FUTURE ROW EVER TAKES A CEREMONY-SUPPLIED BENEFICIARY, IT MUST BE VALIDATED IN
      ;; ITS OWN LIST'S BLOCK — this loop validates nothing.
      (let ((t0 (curr-time)))
        (map (lambda (k:object{tranche-spec})
               (let ((cliff-end (add-time t0 (days (at 'cliff-days k))))
                     (vest-end  (add-time t0 (days (at 'vest-days k)))))
                 (enforce (< cliff-end vest-end) "cliff must precede vest end")
                 (insert tranche-locks (at 'tranche k)
                   { "beneficiary": (at 'beneficiary k)
                   , "total": (at 'total k), "released": 0.0
                   , "cliff-end": cliff-end, "vest-end": vest-end })
                 (emit-event (TRANCHE-LOCKED (at 'tranche k) (at 'beneficiary k)
                                             (at 'total k) cliff-end vest-end))))
             (+ (map (lambda (f:object{founder-alloc})
                       { "tranche": (+ TRANCHE-FOUNDER-PREFIX (at 'account f))
                       , "beneficiary": (at 'account f)
                       , "total": (at 'amount f)
                       , "cliff-days": FOUNDER-CLIFF-DAYS, "vest-days": FOUNDER-VEST-DAYS })
                     founders)
                ;; MODULE-HELD. `beneficiary` records WHERE THE TOKENS ARE — the reserve
                ;; account itself — which is the only honest value when there is no external
                ;; recipient. It is NOT a payout destination: the release refuses these two keys
                ;; outright, and a disbursement takes its target from the caller, never from
                ;; this field.
                [ { "tranche": TRANCHE-TREASURY,  "beneficiary": TREASURY-ACCOUNT
                  , "total": TREASURY-TRANCHE,    "cliff-days": TREASURY-CLIFF-DAYS,  "vest-days": TREASURY-VEST-DAYS }
                  { "tranche": TRANCHE-LIQUIDITY, "beneficiary": LIQUIDITY-ACCOUNT
                  , "total": LIQUIDITY-TRANCHE,   "cliff-days": LIQUIDITY-CLIFF-DAYS, "vest-days": LIQUIDITY-VEST-DAYS } ])))
      (insert init-state INIT-KEY { "initialized": true })
      "supply initialized"))

  (defun init:string (launch-guard:guard)
    @doc "One time per chain, on every chain except 0: create state and the KDA accounts, with no minting. The supplied guard must be the one that derives the pinned launch reserve principal."
    (with-capability (ADMIN-GOV)
      (enforce (!= (at 'chain-id (chain-data)) "0") "Use init-supply on chain 0")
      (enforce-not-initialized)
      (enforce-launch-reserve launch-guard)
      (insert state STATE-KEY
        { "reward-per-token": 0.0, "circulating-supply": 0.0
        , "rounds-applied": 0
        , "total-distributed": 0.0, "sum-pending": 0.0, "sum-debt": 0.0
        ;; Generation 0 = nothing has ever sealed, so `declare-round` refuses until a record
        ;; date has been scheduled AND has landed.
        , "snap-gen": 0, "snap-at": EPOCH, "snap-settled": false, "snap-corr": 0.0
        , "runway-seconds": MIN-RUNWAY })
      (insert prop-count PROP-COUNT-KEY { "n": 0 })
      (insert round-count ROUND-COUNT-KEY { "n": 0 })
      (ensure-coin-account FUNDING-ACCOUNT FUNDING-G)
      (ensure-coin-account POOL-ACCOUNT POOL-G)
      (insert init-state INIT-KEY { "initialized": true })
      "chain initialized"))

  ;; ---- AWARDS — GLOBAL ACCRUAL VIA DECLARED ROUNDS -----------------------------------------
  ;; A round is a rate in KDA per token, effective at a timestamp, declared once and replicated
  ;; to EVERY chain with identical parameters. Funding is decoupled: it only ensures a chain's
  ;; pool holds the KDA to cover its own holders.
  ;;
  ;; 🔴 THESE ACCESSORS EXIST BECAUSE THEIR ABSENCE IS A FREEZE DEFECT. Every other table here
  ;; has a row accessor; `award-rounds` reads are all internal, and every exported reader
  ;; returns a SCALAR SUM. Without an accessor, a single round is reachable only through MODULE
  ;; ADMIN — and the upgrade gate refuses that on a frozen module BEFORE it ever checks a
  ;; keyset, so NO KEY HELPS: the row becomes unreadable while the aggregate readers keep
  ;; working. What that breaks is not hypothetical: the per-round verification across all 20
  ;; chains is the ONLY detector of a partial declaration, a divergence that is detectable but
  ;; NOT self-correcting.
  ;; 🔴 `exists` IS NOT DECORATION — MISSING AND RETRACTED ARE DIFFERENT STATES, because a
  ;; retraction zeroes the rate rather than deleting the row (Pact has no row deletion). An
  ;; accessor that aborted on a missing index could not be used by a comparator at all, and one
  ;; returning a zero row would report retracted and absent identically — exactly the
  ;; divergence the comparator exists to find.
  ;; The same trap applies off-chain: reading this module's tables directly also needs module
  ;; admin, so it breaks at the freeze in the same way and is then unfixable.
  (defun get-rounds-applied:integer ()
    @doc "How many declared rounds THIS chain has folded into its reward-per-token. A value below get-round-count means this chain has declared rounds it has not applied yet."
    (at 'rounds-applied (read state STATE-KEY)))

  (defun get-round:object{round-record} (i:integer)
    @doc "THIS chain's round at index i; never aborts, returning exists false outside 1..get-round-count. A retracted round reads exists true with rate 0.0, so exists false means never declared, not retracted."
    (let ((n (get-round-count)))
      (if (and (> i 0) (<= i n))
        (with-read award-rounds (rkey i) { "rate" := rate, "effective-at" := eff }
          { "index": i, "exists": true, "rate": rate, "effective-at": eff })
        { "index": i, "exists": false, "rate": 0.0, "effective-at": EPOCH })))

  ;; Rounds already effective but not yet folded into this chain's stored rpt.
  (defun outstanding-rate:decimal ()
    @doc "Sum of the rates, in KDA per token, of declared rounds effective at or before now but not yet applied on THIS chain."
    (with-read state STATE-KEY { "rounds-applied" := applied }
      (let ((n (get-round-count)) (now (curr-time)))
        (if (>= applied n) 0.0
          (fold (+) 0.0
            (map (lambda (i:integer)
                   (with-read award-rounds (rkey i) { "rate" := rate, "effective-at" := eff }
                     (if (<= eff now) rate 0.0)))
                 (enumerate (+ applied 1) n)))))))

  ;; ---- THE RECORD-DATE LIFECYCLE -----------------------------------------------------------
  (defun advance-snapshot:string ()
    @doc "Permissionless and idempotent: settles this chain's pending correction, and seals a record instant that has passed, latching the float. Returns settled, sealed, settled+sealed or no-seal."
    (with-read state STATE-KEY
      { "snap-gen" := g, "snap-at" := due, "snap-settled" := settled
      , "circulating-supply" := circ }
      (let* ((now (curr-time))
             (rpt (get-rpt))
             (seal-due (if (= due EPOCH) false (>= now due)))
             ;; FINAL means the generation's correction can no longer change: it carries a
             ;; round and that round is effective. A generation with no round yet is not final
             ;; on its own, but IS final once a seal is due, because declaring refuses while a
             ;; record date is pending and scheduling refuses while a round is not yet
             ;; effective.
             ;; 🔴 NESTED `if`, NOT `and`/`or`, AND THAT IS A CONTROL-FLOW REQUIREMENT. As a
             ;; boolean chain the guard does NOT short-circuit the table read, and this aborts
             ;; at generation 0 on a missing row. Do not "simplify" it back — a table read that
             ;; must not happen is control flow, not style.
             (final (if (= g 0) false
                      (if settled false
                        (if seal-due true
                          (with-read snapshots (gkey g) { "base" := b, "rate" := r }
                            (if (> r 0.0) (>= rpt (+ b r)) false))))))
             (corr (if final (snap-open rpt) 0.0)))
        ;; 🔴 BOTH RESULTS ARE IN THE RETURN VALUE. Reporting only the seal branch makes a call
        ;; that SETTLED without sealing answer "no-seal", and a reader concludes nothing
        ;; happened when the chain's whole correction has just been folded.
        (let ((did-settle
                (if final
                  (with-read state STATE-KEY { "snap-corr" := sc }
                    (update state STATE-KEY { "snap-corr": (+ sc corr), "snap-settled": true })
                    (emit-event (SNAPSHOT-SETTLED g (this-chain) corr))
                    "settled")
                  "no-settle"))
              (did-seal
                (if seal-due
                  (let ((ng (+ g 1)))
                    ;; INSERT, never write: a generation is sealed exactly once, and an insert
                    ;; on a duplicate key aborts rather than silently re-latching a float that
                    ;; has moved.
                    (insert snapshots (gkey ng) { "circ": circ, "base": rpt, "rate": 0.0 })
                    (update state STATE-KEY
                      { "snap-gen": ng, "snap-at": EPOCH, "snap-settled": false })
                    (emit-event (SNAPSHOT-SEALED ng (this-chain) circ rpt))
                    "sealed")
                  "no-seal")))
          (if (= did-settle "settled")
            (if (= did-seal "sealed") "settled+sealed" "settled")
            did-seal)))))

  ;; ---- WHY `schedule-snapshot` AND `cancel-snapshot` SIT AT ADMIN-OPS ----------------------
  ;; By the tier rule — operating within a limit is ops, CHANGING a limit is governance — and
  ;; not by analogy:
  ;;   - it moves NO value and creates no obligation — a record date carries no rate;
  ;;   - it CHANGES no limit; it operates within them;
  ;;   - it is REVERSIBLE by the same tier, alone: `cancel-snapshot` takes one key, and holds
  ;;     for any scheduled date more than MIN-RETRACT-LEAD away, however far in the future.
  ;; The tiers FREEZE, so a placement is permanent and it is stated here rather than assumed.
  ;;
  ;; 🔴 THE GRIEFING SURFACE IS NAMED: a scheduled-and-unsealed record date BLOCKS every award
  ;; declaration, so one key can stall the award subsystem. Accepted on the same ground as
  ;; retraction — the damage is a DELAY, not a loss, the same one key cancels it, and nothing
  ;; owed to a holder is destroyed. 🔴 IF CANCELLATION EVER NEEDED THE OTHER TIER, one device
  ;; could create a stall it could not clear, and this placement would be wrong.
  (defun schedule-snapshot:string (record-at:time)
    @doc "spt-ops: name the record instant when this chain's float is latched, with no rate attached. Use the same instant on all 20 chains, and more than the runway ahead of now so it stays cancellable."
    (with-capability (ADMIN-OPS)
      ;; Settle/seal anything already due FIRST, so the checks below read current state
      ;; rather than a stale generation. Let-bound: never inside an enforce (see there).
      (let ((_ (advance-snapshot)))
        (with-read state STATE-KEY { "snap-at" := due }
          (enforce (= due EPOCH) "a record date is already scheduled")
          ;; 🔴 NO ROUND MAY BE PENDING-EFFECTIVE — this is what guarantees at most ONE
          ;; generation is open at a time. Without it two could overlap and a correction would
          ;; be measured against a base that had already moved.
          (let ((out (- (max-rpt) (get-rpt))))
            (enforce (= out 0.0)
              "SPT cannot schedule a record date while a declared round is not yet effective"))
          ;; The same LOWER bound a round gets: a record date with no cancel runway is a
          ;; decision with no remedy.
          ;; 🔴 BOTH THIS PATH AND `declare-round` READ THE SAME SETTABLE RUNWAY, deliberately —
          ;; a record date and the round it carries are ONE decision to an operator, and two
          ;; runways that could diverge would let a legal record date host a round that is not
          ;; declarable, or the reverse.
          (let* ((runway (get-runway))
                 (earliest (add-time (curr-time) runway)))
            (enforce (> record-at earliest)
              "SPT record date must leave at least two retraction leads of runway"))
          ;; 🔴 NO UPPER BOUND ON `record-at`, deliberately: a far-future typo stays cancellable
          ;; for that whole time, so it is recoverable by the operator alone. The cost meanwhile
          ;; is that declarations are blocked — a jam of the company's OWN scheduler, with no
          ;; holder losing money they are owed. If that reasoning is ever rejected, the bound
          ;; belongs HERE, not in `declare-round`: only this path has a cancel.
          (update state STATE-KEY { "snap-at": record-at })
          (emit-event (SNAPSHOT-SCHEDULED record-at))
          "record date scheduled"))))

  (defun cancel-snapshot:string ()
    @doc "spt-ops: cancel the scheduled record date, legal only while it is more than MIN-RETRACT-LEAD away. Replicate to all 20 chains and verify: a partial cancellation locks the divergence in."
    (with-capability (ADMIN-OPS)
      (with-read state STATE-KEY { "snap-at" := due }
        (enforce (!= due EPOCH) "SPT there is no scheduled record date to cancel")
        (let ((deadline (add-time (curr-time) MIN-RETRACT-LEAD)))
          (enforce (> due deadline)
            "SPT record date is too close to landing to be cancelled"))
        (update state STATE-KEY { "snap-at": EPOCH })
        (emit-event (SNAPSHOT-CANCELLED due))
        "record date cancelled")))

  (defschema funding-need required:decimal pool:decimal shortfall:decimal)

  (defun funding-needed:object{funding-need} (rate:decimal)
    @doc "Required, pool and shortfall in KDA for a round at rate on this chain, as of NOW, covering awards unclaimed from earlier rounds. It is the bar declare-round will enforce ONLY while no further record date seals in between — declare-round settles and seals first. Fund all 20 chains before declaring, and re-read if a record date was scheduled."
    (let* ((required (round-funding-bar rate))
           (pool (try 0.0 (coin.get-balance POOL-ACCOUNT)))
           (gap (- required pool)))
      { "required": required, "pool": pool
      , "shortfall": (if (> gap 0.0) gap 0.0) }))

  (defschema chain-report-row
    @doc "The object chain-report returns for one chain: tokens-on-chain and circulating, funding and pool KDA, liability, surplus, rpt and max-rpt, the sealed generation, its float and rate, the scheduled record date, settled and total-distributed."
    tokens-on-chain:decimal circulating:decimal funding:decimal pool:decimal
    liability:decimal surplus:decimal rpt:decimal max-rpt:decimal
    generation:integer sealed-float:decimal snapshot-rate:decimal
    record-date:time settled:bool total-distributed:decimal)

  (defun chain-report:object{chain-report-row} ()
    @doc "Per-chain read of float, funding, pool, liability, rpt, generation and record date in one call. tokens-on-chain includes the excluded reserves; circulating is the float that earns."
    (let* ((circ (get-circulating))
           (lr (try "" (get-launch-reserve)))
           (bal-of (lambda (a:string) (try 0.0 (get-balance a))))
           (reserves (+ (+ (bal-of TREASURY-ACCOUNT) (bal-of FOUNDER-ACCOUNT))
                        (+ (bal-of LIQUIDITY-ACCOUNT)
                           (if (= lr "") 0.0 (bal-of lr))))))
      (with-read state STATE-KEY
        { "snap-gen" := g, "snap-at" := due, "snap-settled" := settled
        , "total-distributed" := td }
        { "tokens-on-chain": (+ circ reserves)
        , "circulating": circ
        , "funding": (try 0.0 (coin.get-balance FUNDING-ACCOUNT))
        , "pool": (try 0.0 (coin.get-balance POOL-ACCOUNT))
        , "liability": (award-liability)
        , "surplus": (pool-surplus)
        , "rpt": (get-rpt)
        , "max-rpt": (max-rpt)
        , "generation": g
        , "sealed-float": (snapshot-circulating)
        , "snapshot-rate": (if (= g 0) 0.0 (at 'rate (read snapshots (gkey g))))
        , "record-date": due
        , "settled": settled
        , "total-distributed": td })))

  (defun round-funding-bar:decimal (rate:decimal)
    @doc "The KDA this chain's pool must hold for a round at rate against the CURRENTLY sealed generation: declared-liability plus rate times that sealed float, floored to 12 decimals. It covers awards unclaimed from earlier rounds. declare-round seals before it prices, so a record date landing in between moves this number."
    (floor (+ (declared-liability) (* rate (snapshot-circulating))) MINIMUM-PRECISION))

  (defun declare-round:string (id:string rate:decimal effective-at:time)
    @doc "spt-gov: declare an award round of rate KDA per token against this chain's sealed record date, its pool already covering round-funding-bar. Replicate the same id, rate and effective-at to all 20 chains."
    ;; 🔴 GOV, NOT OPS. Declaring a round CREATES A PAYMENT OBLIGATION the contract
    ;; must honour and `retract-round` can only undo before it takes effect — value out, and
    ;; irreversible after that instant. The rate has no ceiling but the funding bar, so the
    ;; AUTHORITY is what bounds it. Scheduled, not hot.
    ;; 🔴 `retract-round` deliberately STAYS at ops: it REDUCES the obligation. A safety brake must
    ;; never be harder to reach than the thing it stops.
    (with-capability (ADMIN-GOV)
      (enforce (> rate 0.0) "rate must be positive")
      (enforce-unit rate)
      ;; ---- A ROUND NEEDS A SEALED RECORD DATE ----------------------------------------
      ;; 🔴 ONE MODE, ONE CODE PATH, NO HYBRID. There is deliberately no "declare without a
      ;; record date" fallback — a fallback is what lets a moving denominator back in through
      ;; the door marked convenience, and after the freeze it could never be removed.
      (let ((_ (advance-snapshot)))
        (with-read state STATE-KEY { "snap-gen" := g, "snap-at" := due }
          ;; 🔴 THE PENDING CHECK GOES FIRST, AND THE ORDER IS LOAD-BEARING. Reversed, the very
          ;; common case — scheduled the first record date, then declared before it landed —
          ;; reports "no record date has sealed", a true sentence that sends the operator to
          ;; schedule a SECOND one, which is the opposite of what that state needs.
          (enforce (= due EPOCH)
            "SPT cannot declare a round while a record date is scheduled and unsealed")
          (enforce (> g 0)
            "SPT no record date has sealed on this chain; schedule one before declaring")
          (let ((grate (at 'rate (read snapshots (gkey g)))))
            ;; 🔴 ONE ROUND PER GENERATION. Without it a duplicate declaration — an operator
            ;; re-running a leg they believe failed — is accepted and silently DOUBLES the
            ;; chain's rate.
            (enforce (= grate 0.0)
              "SPT this record date already carries a declared round"))))
      ;; ---- effective-at MUST BE STRICTLY IN THE FUTURE, BY A FULL RUNWAY --------------
      ;; 🔴 Accrual is stamped at CREDIT time, not accrued over the period a round names, so a
      ;; round naming a PAST window pays whoever holds tokens AT DECLARATION rather than the
      ;; holders during that window. Measured without this bound: a buyer acquiring tokens nine
      ;; days AFTER the named effective date is paid in full the instant the round is declared
      ;; — a real misallocation, admin-reachable, and permanent once frozen.
      ;; Strict `>`, not `>=`: equality is the "effective right now" case, which is the
      ;; retroactive hazard at its boundary.
      ;;
      ;; 🔴 THE FLOOR IS THE RUNWAY, NOT MERELY "now", AND THE RUNWAY IS TWO RETRACTION LEADS.
      ;; A bare "must be future" floor is weaker than the retraction precondition, so a round
      ;; could be IRREVERSIBLE THE INSTANT IT WAS WRITTEN, in one transaction — measured: the
      ;; declaration is accepted, retraction is refused, and once effective the pool cannot
      ;; cover it, surplus recovery is rejected and claims report insufficient funds.
      ;; ONE lead is not enough either, because declaring and retracting measure against
      ;; different `now`: measured on a single-lead floor, the real remedy window collapsed to
      ;; SIXTY SECONDS. With the doubled floor it is at least a full lead wide for EVERY round.
      ;; This bound implies "must be future", so a separate check would be a branch that can
      ;; never fail. (This module DOES deliberately keep several such branches elsewhere, each
      ;; labelled where it sits — do not cite this line to delete one.)
      ;; It CONVERTS the replication window rather than closing it — do not write "closes by
      ;; construction". If effective-at passes mid-replication the remaining chains can never
      ;; receive that round with identical parameters and the operator must recover: strictly
      ;; better than a wrong payment, but not self-executing, so the operating rule is a
      ;; generous lead and all 20 legs declared before funding.
      (let* ((runway (get-runway))
             (earliest (add-time (curr-time) runway)))
        (enforce (> effective-at earliest)
          "award round effective-at must leave at least two retraction leads of runway"))
      ;; 🔴 NO UPPER BOUND ON `effective-at`, deliberately: a far-future typo is a true undo
      ;; here, because retraction rewinds the timestamp as well as the rate. 🔴 THE LOWER BOUND
      ;; ABOVE IS THE LOAD-BEARING ONE — with no cap on the rate, that runway is the only
      ;; remedy for a wrong rate the pool already covers.
      (let* ((prev (get-round-count))
             (slot (+ prev 1)))
        ;; ---- MONOTONIC effective-at: NEVER OBSERVED TO FIRE, AND KEPT ANYWAY -------------
        ;; Three other refusals appear to force the order already, so the condition is
        ;; satisfied by construction on every path anyone has managed to build. THAT IS NOT A
        ;; PROOF: a probe cannot enumerate, and the argument runs through THREE other functions
        ;; rather than anything local.
        ;; 🔴 KEPT because `apply-round` FOLDS AGAINST THIS ORDER — its consecutive-effective
        ;; prefix is the effective-unapplied set only BECAUSE the timestamps are non-decreasing.
        ;; Deleting the local guard would leave a money invariant resting on a non-local chain
        ;; of reasoning, inside a module that can never be patched.
        ;; 🔴 SO DO NOT WRITE A NEGATIVE TEST FOR IT. Any such test is satisfied by one of the
        ;; other refusals — green by accident, and it would keep passing if this were deleted.
        ;; Its absence from the suite is deliberate.
        (if (> prev 0)
          (let ((prev-eff (at 'effective-at (read award-rounds (rkey prev)))))
            (enforce (>= effective-at prev-eff)
              "effective-at must be >= the previous round's (declare rounds in time order)"))
          true)
        ;; ---- PROVE THE MONEY, THEN MAKE THE PROMISE ------------------------------------
        ;; The declaration is what creates the liability, so the money is proven first: a round
        ;; cannot be declared unless this chain's pool already covers what it will owe.
        ;;
        ;; 🔴 THE DENOMINATOR IS THE SEALED FLOAT, NOT THE LIVE ONE, and that one token is what
        ;; makes this bar EXACT rather than a floor. The sealed float is IMMUTABLE, so the
        ;; denominator cannot move between the declaration and the round taking effect. The
        ;; live float still grows inside that window — purchases, permissionless tranche
        ;; releases, inbound cross-chain legs — but the round owes against the sealed one, which
        ;; none of them can touch. Measured on a live-float bar instead: a pool funded exactly,
        ;; one stranger's ordinary purchase inside the window, and the true debt runs 150% past
        ;; the pool — which all-or-nothing claims turn into a race an honest holder can lose.
        ;; 🔴 NOT VACUOUS AT ZERO FLOAT, and NOT because zero cannot happen: a generation CAN
        ;; seal with no float, and then the bar is zero — but so is the payout, so a vacuous bar
        ;; covers a vacuous debt. On a live-float bar the bar is zero while the DEBT is not.
        ;;
        ;; The bar is FLOORED to the token's precision for the same reason funding is: claims
        ;; pay floored amounts, so the floored liability is the EXACT maximum that can ever
        ;; leave the pool, not a relaxation — and it is the only bar an operator can hit
        ;; exactly, since a coin balance carries 12 decimals while the liability can carry dust
        ;; from prior claims.
        ;;
        ;; 🔴 PLACED LAST, AND BEFORE EVERY WRITE. Last because it is the only check here that
        ;; reads chain state: every cheap input-only bound above must reject FIRST, or its own
        ;; negative test would be satisfied by THIS failure instead. Before the writes because a
        ;; refused call must leave no counter row behind.
        ;;
        ;; AN UNDER-FUNDED CHAIN IS STILL RECOVERABLE, and that residual is accepted because
        ;; nothing is lost: awards accumulate forever and funding tops the chain up. Merging
        ;; the two calls would remove that top-up path — the one forgiving property this
        ;; subsystem has. There is deliberately NO margin constant: funding with headroom is an
        ;; operational rule, and a margin frozen into the module could never be corrected.
        (let* ((owed (round-funding-bar rate))
               (poolbal (try 0.0 (coin.get-balance POOL-ACCOUNT))))
          (enforce (>= poolbal owed)
            "SPT award pool does not cover the liability this round declares"))
        ;; Bind the generation's rate to the generation. 🔴 BOTH SIDES OR NEITHER — the
        ;; award-rounds row drives the accrual and this row drives the CORRECTION, so a round
        ;; written to one and not the other pays on the wrong denominator forever.
        (update snapshots (gkey (get-snapshot-gen)) { "rate": rate })
        ;; Appended at the next index; the id lives in the event only, since rounds are
        ;; index-addressed.
        (insert award-rounds (rkey slot) { "rate": rate, "effective-at": effective-at })
        (update round-count ROUND-COUNT-KEY { "n": slot }))
      (emit-event (ROUND-DECLARED id rate effective-at))
      "round declared"))

  (defun retract-round:string (id:string)
    @doc "spt-ops: zero the last declared round's rate, once, and only more than MIN-RETRACT-LEAD before it takes effect. No earlier round is reachable, so retract on all 20 chains before declaring the next."
    (with-capability (ADMIN-OPS)
      (let ((n (get-round-count)))   ; let-bound: the read-only-mode rule
        (enforce (> n 0) "there is no declared award round to retract")
        (with-read award-rounds (rkey n) { "rate" := rate, "effective-at" := eff }
          ;; Idempotence is deliberately NOT offered: a second retraction means the operator
          ;; believes a round exists that does not, and this module fails closed.
          (enforce (> rate 0.0) "the last declared award round is already retracted")
          (let ((deadline (add-time (curr-time) MIN-RETRACT-LEAD)))
            (enforce (> eff deadline)
              "award round is too close to taking effect to be retracted"))
          ;; 🔴 ZERO THE RATE — do NOT decrement the count and do NOT delete the row. Pact has
          ;; no row deletion, and decrementing would free the index for reuse, forcing the
          ;; declaration from an insert to a write and giving up the property that a round can
          ;; never be silently overwritten. Zeroing keeps the index append-only and gap-free,
          ;; which is the invariant the fold depends on. A zero-rate round is inert everywhere
          ;; by construction.
          ;; COST, recorded rather than hidden: the applied counter cannot advance past a
          ;; retracted round on its own, so it keeps being enumerated until a later real round
          ;; is applied.
          ;; 🔴 REWIND effective-at TOO, not just the rate. The monotonicity check anchors to
          ;; the LAST row, so a retracted round's timestamp left in place would govern every
          ;; future declaration — measured, a retracted round dated far in the future rejects
          ;; every sane round forever. Rewinding makes the floor track the last LIVE round, and
          ;; makes a retraction a TRUE undo rather than a partial one.
          (let ((prev-eff (if (> n 1)
                            (at 'effective-at (read award-rounds (rkey (- n 1))))
                            EPOCH)))
            (update award-rounds (rkey n) { "rate": 0.0, "effective-at": prev-eff }))
          ;; 🔴 REWIND THE GENERATION'S RATE TOO — BOTH SIDES OR NEITHER. One row drives the
          ;; ACCRUAL and the other the CORRECTION, so zeroing only the round leaves every
          ;; account checkpointed in that generation with a live correction against a round
          ;; that no longer pays — paying out on money nobody funded.
          ;; The generation is left SEALED and re-declarable, so a rate typo can be fixed onto
          ;; the SAME record date without re-running the ceremony.
          (update snapshots (gkey (get-snapshot-gen)) { "rate": 0.0 })
          ;; The event carries the values as they were BEFORE the retraction — the row itself
          ;; keeps no history. 🔴 `id` is an operator-supplied LABEL: the table stores no id, so
          ;; it cannot be checked against the row being zeroed. Never read it as evidence of
          ;; which round was retracted; the index and rate are module-read and truthful.
          (emit-event (ROUND-RETRACTED id n rate eff))))
      "round retracted"))

  (defun apply-round:string (id:string)
    @doc "Permissionless: folds this chain's effective rounds into stored rpt so get-rpt stays O(1); rounds take effect on time whether or not it runs. id is a label carried into the event only."
    (with-read state STATE-KEY { "reward-per-token" := folded, "rounds-applied" := applied }
      (let ((n (get-round-count)) (now (curr-time)))
        ;; Guard the empty range before enumerating.
        (enforce (< applied n) "no newly-effective rounds to apply")
        ;; One pass: extend the prefix and sum its rate only while each next round is
        ;; CONSECUTIVE and effective.
        (let* ((acc (fold (lambda (a:object{apply-acc} k:integer)
                            (with-read award-rounds (rkey k) { "rate" := rate, "effective-at" := eff }
                              (if (and (= (at 'i a) (- k 1)) (<= eff now))
                                { "i": k, "rate": (+ (at 'rate a) rate) }
                                a)))
                          { "i": applied, "rate": 0.0 }
                          (enumerate (+ applied 1) n)))
               (new-applied (at 'i acc))
               (extra (at 'rate acc)))
          (enforce (> extra 0.0) "no newly-effective rounds to apply")
          (update state STATE-KEY
            { "reward-per-token": (+ folded extra)
            , "rounds-applied": new-applied })
          (emit-event (ROUND-APPLIED id (this-chain) extra))
          "round applied"))))

  (defun fund-awards:string (pool-amount:decimal)
    @doc "spt-gov: move pool-amount KDA from this chain's funding into its award pool, which must then cover the chain's liability. Installing a capability voids unscoped signatures for the rest of the transaction."
    (with-capability (FUND-AWARDS)
      (enforce (> pool-amount 0.0) "pool-amount must be positive")
      (let* ((circ (get-circulating))          ; let-bound: the read-only-mode rule
             (liability (award-liability))
             (fl (floor liability MINIMUM-PRECISION))
             ;; 0.0 when the pool account does not exist on this chain yet; the deposit below
             ;; is transfer-CREATE, so it materialises on first funding.
             (poolbal (try 0.0 (coin.get-balance POOL-ACCOUNT))))
        ;; FUNDABILITY: a chain is fundable with live float OR a payable stranded liability
        ;; (every holder left, but their crystallized pending is still claimable here). Only
        ;; BOTH being zero is rejected — a dead chain, where the no-exit pool would strand the
        ;; cash forever.
        (enforce (or (> circ 0.0) (> fl 0.0))
          "nothing fundable: no circulating float and no payable liability on this chain")
        ;; EXACT solvency: after this deposit the pool must cover the chain's TRUE unclaimed
        ;; liability, which counts the crystallized pending of tokens that have LEFT the chain.
        ;; So "funding succeeded" is a hard guarantee that every claim here is payable. The
        ;; bound is FLOORED to coin precision for the same reason claims are: any payable
        ;; amount is at most the floored liability, and the sub-precision dust is unpayable by
        ;; construction and re-covered by the next funding.
        ;;

        ;; ---- THIS BRANCH IS NOT KNOWN TO BE REACHABLE, AND IS NOT PROVEN UNREACHABLE -------
        ;; Every attempt to fire it lands on an accepted deposit instead, each one measured.
        ;; 🔴 IT STAYS BECAUSE `pool >= liability` IS HELD BY FOUR SEPARATE MECHANISMS IN THREE
        ;; FUNCTIONS, none of them local to this line and none provable from here — and this
        ;; module FREEZES. If any one of them is ever wrong, this enforce is what stops an
        ;; operator funding a chain that cannot pay. The abort is free and grants no new power.
        ;; 🔴 SO DO NOT WRITE A NEGATIVE TEST FOR IT. On today's module such a test is green for
        ;; the wrong reason, or red for one. The suite's silence here is deliberate — it is the
        ;; finding, not an omission.
        (enforce (>= (+ poolbal pool-amount) fl)
          "pool underfunded: pool + deposit must cover this chain's award liability"))
      ;; the funding account's module guard is satisfied because this spend runs inside the
      ;; module — there is no capability to forge
      (install-capability (coin.TRANSFER FUNDING-ACCOUNT POOL-ACCOUNT pool-amount))
      (coin.transfer-create FUNDING-ACCOUNT POOL-ACCOUNT POOL-G pool-amount)
      (with-read state STATE-KEY { "total-distributed" := td }
        (update state STATE-KEY { "total-distributed": (+ td pool-amount) }))
      (emit-event (AWARD-FUNDED pool-amount))
      "awards funded"))

  (defun claim-awards:decimal (account:string)
    @doc "Permissionless: pay an account's accrued awards in KDA to the principal of its stored guard, not a like-named coin account. Pays the 12 decimal floor, carries dust forward, and returns the amount paid."
    ;; 🔴 THE SNAPSHOT ADVANCE HERE IS FOR LIVENESS, NOT FOR THE ACCOUNTING. Omitting it would
    ;; not move a cent — measured, and the cancellation is structural rather than luck. It
    ;; stays so that a chain whose only activity is CLAIMS still seals a due record date on
    ;; time, without waiting on a human to call the permissionless helper by hand.
    ;; 🔴 Do NOT re-write this into a correctness claim without a test that goes RED.
    (let* ((_ (advance-snapshot))
           (rpt (get-rpt)))
      (with-read accounts account
        { "balance" := bal, "guard" := g, "reward-debt" := rd, "pending-awards" := pend
        , "snap-index" := si, "snap-balance" := sb }
        ;; 🔴 PAY THE FLOOR AND CARRY THE DUST. The accrual product can carry up to 24 decimals
        ;; while coin refuses anything finer than 12, so paying the raw value would revert EVERY
        ;; claim whose owed amount is sub-precision, stranding a correctly-owed award forever.
        ;; Nothing is lost: the remainder stays as pending and the next round's accrual sweeps
        ;; it up, and the liability identity stays exact.
        ;; The balance does not move here, but the checkpoint still fires if a NEWER generation
        ;; has sealed since — a claim is a write like any other.
        (let* ((cp (plan-snap si sb bal bal rd rpt))
               (cp-corr (at 'corr cp))
               (raw (if (excluded? account) 0.0
                      (+ (+ pend (* bal (- rpt rd))) cp-corr)))
               (payout (floor raw MINIMUM-PRECISION))
               (dust (- raw payout))
               (recipient (create-principal g)))
          (enforce (> payout 0.0) "nothing to claim")   ; excluded or dust-only => rejected
          (update accounts account
            { "reward-debt": rpt, "pending-awards": dust
            , "snap-index": (at 'index cp), "snap-balance": (at 'balance cp) })
          ;; Exact solvency: the counters move by exactly what left the pool.
          (with-read state STATE-KEY
            { "sum-pending" := sp, "sum-debt" := sd, "snap-corr" := sc }
            (update state STATE-KEY
              { "sum-pending": (+ (- sp pend) dust)
              , "sum-debt": (+ sd (* bal (- rpt rd)))
              , "snap-corr": (+ sc (at 'd-corr cp)) }))
          ;; the pool's module guard is satisfied because this payout runs inside the module
          (install-capability (coin.TRANSFER POOL-ACCOUNT recipient payout))
          (coin.transfer-create POOL-ACCOUNT recipient g payout)
          (emit-event (AWARD-CLAIMED account payout))
          payout))))

  (defun recover-pool-surplus:string (amount:decimal)
    @doc "spt-gov: move KDA owed to nobody from this chain's award pool to the funding account, bounded by pool-surplus. Never call between funding and declaring on a chain: the funding reads as surplus."
    ;; 🔴 THIS EXISTS BECAUSE THE POOL HAS NO OTHER EXIT FOR MONEY OWED TO NOBODY, AND IT MUST
    ;; SURVIVE THE FREEZE. Claims pay only what is owed, so anything beyond the liability has
    ;; no way out; and the only other recovery — module admin — is destroyed FOREVER at the
    ;; freeze, because the upgrade gate refuses first. The amounts are real: measured, funding
    ;; far above a small liability leaves nearly all of it owed to nobody.
    ;; Over-funding is not the only way in: coin credits an EXISTING account without consulting
    ;; its guard, so ANY third party can push KDA into the pool and the module cannot refuse it
    ;; (measured), and claim dust accumulates there too. Bounding the deposit instead is NOT a
    ;; substitute — it addresses only operator error, leaves donations and dust stranded, and
    ;; would force every funding call to hit an exact figure.
    ;; It survives the freeze because its capability carries no frozen-module clause and both
    ;; accounts are module-guarded, so nothing here ever reaches module admin. Proven against a
    ;; module compiled frozen, not assumed.
    (with-capability (RECOVER-SURPLUS amount)
      ;; 🔴 THE WORDING IS DELIBERATE AND NOT THE MODULE'S USUAL PHRASE: coin's own message
      ;; CONTAINS the shorter form, so a negative written against it passes even when this
      ;; check is deleted. Measured: with the shorter message, deleting this enforce left the
      ;; suite green.
      (enforce (> amount 0.0) "recovery amount must be positive")
      (let ((surplus (pool-surplus)))   ; let-bound: the read-only-mode rule
        (enforce (<= amount surplus)
          "amount exceeds the award pool's unowed surplus"))
      ;; transfer-CREATE so a chain whose funding account was never materialised is
      ;; recoverable too.
      (install-capability (coin.TRANSFER POOL-ACCOUNT FUNDING-ACCOUNT amount))
      (coin.transfer-create POOL-ACCOUNT FUNDING-ACCOUNT FUNDING-G amount)
      ;; total-distributed is the NET funding->pool flow, so a recovery subtracts.
      (with-read state STATE-KEY { "total-distributed" := td }
        (update state STATE-KEY { "total-distributed": (- td amount) }))
      (emit-event (POOL-SURPLUS-RECOVERED amount))
      "pool surplus recovered"))

  ;; ---- FUNDING -----------------------------------------------------------------------------
  (defun receive-funding:string (from:string amount:decimal)
    @doc "Permissionless: deposit KDA into this module's funding account, signed by from as a normal coin transfer. The from account must not be one of this module's protocol accounts."
    (enforce (> amount 0.0) "SPT funding amount must be positive")
    ;; A protocol account can never be the SOURCE of a funding deposit.
    (enforce (not (protocol-account? from))
      "SPT protocol accounts cannot be the source of a funding deposit")
    ;; transfer-CREATE, so the funding account materialises on first receipt even on a chain
    ;; where init never created it.
    (coin.transfer-create from FUNDING-ACCOUNT FUNDING-G amount)
    (emit-event (FUNDING-RECEIVED from amount))
    "funding received")

  ;; ---- CHANGING the runway, as opposed to operating under it -------------------------------
  ;; 🔴 GOV, NOT OPS. Declaring operates WITHIN this limit; moving the limit takes two devices.
  ;; From the ops tier, one key could shorten the runway and then declare inside it —
  ;; reassembling, from two individually legal steps, exactly the state where a mistake leaves
  ;; seconds to reach the remedy. Pinned by a NAMED negative.
  ;; 🔴 THE FLOOR IS THE POINT, AND IT IS ASYMMETRIC. Raising the runway is always safe; only
  ;; lowering is a decision, and it stops at a floor that FREEZES. With no rate caps, that floor
  ;; is the ONLY remedy for a wrong rate the pool already covers.
  ;; BOUNDARY: this changes FUTURE declarations only. It does not touch a round or record date
  ;; already declared, does not change the retraction lead, and cannot lower the floor itself.
  ;; 🔴 IT IS PER-CHAIN. A runway changed on one chain and not the other 19 is a divergence
  ;; nothing on chain can detect — replicate all 20 and verify before relying on it.
  (defun set-runway:string (new-runway:integer)
    @doc "spt-gov: set how much notice, in seconds, a new round or record date must leave; refused below MIN-RUNWAY, and already declared ones are unaffected. Per-chain state, so replicate it on every chain."
    (with-capability (ADMIN-GOV)
      (enforce (>= new-runway MIN-RUNWAY)
        (format "SPT runway must be at least {} seconds" [MIN-RUNWAY]))
      ;; 🔴 AN UPPER BOUND, BECAUSE `add-time` WRAPS SILENTLY. A huge runway lands hundreds of
      ;; thousands of years in the PAST rather than erroring, which makes a past effective-at
      ;; declarable — with the retraction window already expired, so the one way back is gone at
      ;; the moment it is needed. The floor above never sees it, because the value is enormous
      ;; rather than small. This is a fat-finger abort, not a policy dial.
      (enforce (<= new-runway MAX-RUNWAY)
        (format "SPT runway must be at most {} seconds" [MAX-RUNWAY]))
      (update state STATE-KEY { "runway-seconds": new-runway })
      "runway updated"))

  (defun withdraw-funding:string (to:string amount:decimal)
    @doc "spt-gov: move amount KDA from the funding account to an external coin account. That account must already exist, since this transfers and never creates."
    (with-capability (WITHDRAW-FUNDING to amount)
      (enforce (> amount 0.0) "SPT funding amount must be positive")
      ;; the funding account is module-guarded; there is no capability to forge
      (install-capability (coin.TRANSFER FUNDING-ACCOUNT to amount))
      (coin.transfer FUNDING-ACCOUNT to amount)
      (emit-event (FUNDING-WITHDRAWN to amount))
      "funding withdrawn"))

  ;; ---- TRANCHE TIME-LOCKS — founder / treasury / liquidity ---------------------------------
  ;; Permissionless, pre-committed, linear-from-cliff releases on chain 0, where the supply was
  ;; minted. Released SPT enters the float exactly like any credit: counted as circulating,
  ;; accruing awards from NOW with no retroactivity, and credited UNVOTED.
  (defun tranche-vested:decimal (total:decimal cliff-end:time vest-end:time t:time)
    @doc "Pure vesting curve: 0 before cliff-end, linear from cliff-end to vest-end floored to 12 decimals, and exactly total at or after vest-end."
    (if (< t cliff-end) 0.0
      (if (>= t vest-end) total
        (floor (/ (* total (diff-time t cliff-end)) (diff-time vest-end cliff-end))
               MINIMUM-PRECISION))))

  (defun get-tranche:object{tranche-lock} (tranche:string) (read tranche-locks tranche))

  (defun tranche-releasable:decimal (tranche:string)
    @doc "Read-only, any tranche: what is vested at current chain time minus everything already paid out. That is what release-tranche pays now or disburse-tranche may send; the tranche rows exist on chain 0."
    (with-read tranche-locks tranche
      { "total" := tot, "released" := rel, "cliff-end" := ce, "vest-end" := ve }
      (- (tranche-vested tot ce ve (curr-time)) rel)))

  (defun tranche-available:decimal (tranche:string)
    @doc "Read-only, chain 0: how much of the treasury or liquidity tranche the admin may disburse right now, that is the vested amount minus everything already disbursed. Any other tranche is refused."
    (enforce (or (= tranche TRANCHE-TREASURY) (= tranche TRANCHE-LIQUIDITY))
      "SPT only the treasury and liquidity tranches have a disbursable balance")
    (tranche-releasable tranche))

  (defun release-tranche:decimal (tranche:string)
    @doc "Permissionless, chain 0: credit the newly vested part of a founder allocation to its stored beneficiary. Treasury and liquidity are refused, and the beneficiary token account must already exist."
    (with-read tranche-locks tranche
      { "beneficiary" := ben, "total" := tot, "released" := rel
      , "cliff-end" := ce, "vest-end" := ve }
      (enforce (= (take (length TRANCHE-FOUNDER-PREFIX) tranche) TRANCHE-FOUNDER-PREFIX)
        "SPT only founder allocations are released; treasury and liquidity are disbursed")
      (let ((amount (- (tranche-vested tot ce ve (curr-time)) rel)))
        (enforce (> amount 0.0) "nothing releasable")
        ;; ---- INLINED RESERVE DEBIT ---------------------------------------------------
        ;; 🔴 INLINED RATHER THAN ROUTED THROUGH THE SHARED `debit`, which hard-rejects these
        ;; reserves outright — so this path cannot go through it, and does not need to. It
        ;; acquires NO capability at all, because nothing here is caller-chosen: the beneficiary
        ;; is read from the frozen lock row and the amount comes from the immutable vesting
        ;; schedule. That is what keeps the trigger safely PERMISSIONLESS.
        ;; The reserves are excluded from the float, so the debit is balance-only.
        ;;
        ;; 🔴 THE BENEFICIARY'S ACCOUNT MUST ALREADY EXIST, AND THAT CHECK IS NOT OPTIONAL.
        ;; Crediting a missing account CREATES it under whatever guard it is handed, so without
        ;; this a mistyped founder address silently mints an account nobody holds the keys to,
        ;; and those tokens are stranded forever.
        ;; 🔴 THE FAILURE MODE INVERTS, AND THAT IS THE POINT: refusing leaves the tokens in the
        ;; excluded reserve — outside the float, accruing nothing, owed to nobody — and anyone
        ;; can retry the moment the account exists. Nothing is lost. Paying them to an address
        ;; nobody controls loses them permanently.
        ;; The message names the remedy because the founder is the only one who can apply it,
        ;; and whoever triggers this permissionless release may not be them.
        (let ((exists (with-default-read accounts ben
                        { "balance": -1.0 } { "balance" := b } (!= b -1.0))))
          (enforce exists
            "SPT founder account does not exist yet — the founder must create it, then this release can be retried"))
        (let ((reserve FOUNDER-ACCOUNT))
          (with-read accounts reserve { "balance" := rbal }
            (enforce (<= amount rbal) "insufficient reserve balance")
            (update accounts reserve { "balance": (- rbal amount) }))
          ;; 🔴 ORDER IS LOAD-BEARING: the reserve was just debited by exactly this amount, so
          ;; the credit is backed by a real movement of existing supply rather than by a
          ;; capability token. NEVER REORDER THE DEBIT BELOW THIS BLOCK.
          (let ((g (account-guard ben)))
            ;; The guard half of the beneficiary rules, run HERE because here is where a guard
            ;; exists; the address half already ran at the ceremony.
            (enforce-beneficiary ben g)
            (with-capability (CREDIT ben)
              (credit ben g amount)))
          (update tranche-locks tranche { "released": (+ rel amount) })
          ;; A release MOVES existing supply between two real ledger accounts, so it is a normal
          ;; two-sided TRANSFER — NOT the empty-sender mint shape. The tranche event stays
          ;; alongside it, carrying the vesting detail no fungible event can.
          (emit-event (TRANSFER reserve ben amount))
          (emit-event (TRANCHE-RELEASED tranche ben amount (+ rel amount)))
          amount))))

  ;; ---- DISBURSEMENT — the module-held treasury and liquidity tranches ----------------------
  ;; 🔴 THIS IS THE ONE DISCRETIONARY POWER OVER MOST OF SUPPLY, AND IT IS DELIBERATE. As those
  ;; tranches vest they simply become available, and this is how an admin names a target and an
  ;; amount within that availability. That level of control is intended and approved — do not
  ;; re-litigate it in code.
  ;; WHAT IS BOUNDED, AND WHAT IS NOT:
  ;;   * BOUNDED — the CALENDAR. The amount can never exceed what has vested, computed from the
  ;;     same source constants as every other tranche. The admin chooses WHERE and
  ;;     WHEN-AFTER-VESTING, never SOONER, and nothing here can accelerate.
  ;;   * NOT BOUNDED — WHO. Any existing non-protocol account, any number of times, for the
  ;;     whole vested amount. That is the intended decision and the founder-facing docs say so
  ;;     in those words.
  ;;   * 🔴 NO REVERSAL, EVER. A wrong disbursement stays wrong. Every protection here is a
  ;;     REFUSAL at this call site; none is an undo, and none may be added.
  ;;
  ;; 🔴 THE TARGET MUST ALREADY EXIST, and that settles the recipient-key question: the guard is
  ;; not a parameter, it is READ FROM THE TARGET'S OWN LEDGER ROW. So a disbursement can never
  ;; create an account, and therefore never mints one under a keyset nobody can satisfy; the
  ;; recipient having created their own account IS the proof that it works; and the guard cannot
  ;; disagree with the name, because nobody supplies it. A recipient without an account creates
  ;; one first, with their own keys — their step, and a remedy they can exercise alone.
  (defun disburse-tranche:decimal (tranche:string target:string amount:decimal)
    @doc "spt-gov, chain 0: send amount from the treasury or liquidity tranche to target, capped at tranche-available. Target must already exist and be an ordinary holder; sign scoped to DISBURSE."
    (with-capability (DISBURSE tranche target amount)
      ;; 🔴 Only the two module-held tranches. A founder allocation has a NAMED owner and a
      ;; permissionless release, so letting the admin redirect one would be theft of a vested
      ;; allocation — the refusal is first and unconditional.
      (enforce (or (= tranche TRANCHE-TREASURY) (= tranche TRANCHE-LIQUIDITY))
        "SPT only the treasury and liquidity tranches are disbursed")
      (enforce (> amount 0.0) "SPT disbursement amount must be positive")
      (enforce-unit amount)
      ;; The reserves may not receive on ANY path: a deposit into one has no exit, forever.
      ;; The holder transfer path carries this check separately; this one does not go through
      ;; it, so it carries its own.
      (enforce (not (protocol-account? target))
        "SPT protocol accounts cannot receive a disbursement")
      ;; 🔴 AND NOT AN EXCLUDED ACCOUNT EITHER — the protocol-account test is NOT a superset. It
      ;; deliberately OMITS the launch reserve, which must stay DEBITABLE for the sale to
      ;; deliver, so relying on it alone here would let the admin send treasury or liquidity
      ;; tokens INTO that reserve: recoverable only through the sale module's admin, WHICH DIES
      ;; AT FREEZE, and then sellable by anyone at a floor calibrated for a fixed reserve size.
      ;; 🔴 AND ON THE 19 SPOKES IT IS NOT RECOVERABLE AT ALL: the sale is deployed on the hub only,
      ;; so the reserve's debit guard names a module that does not exist there. Measured on a spoke
      ;; world — `transfer-create` INTO the pin succeeds, the debit then fails "Cannot find module".
      ;; The reserve is a permanent one-way SPT sink on every chain but chain 0.
      ;; Measured on that shape, one permissionless call took 89,100 SPT for 891 KDA. That was
      ;; the only escape from the approved envelope, and this enforce closes it.
      ;; The whole excluded CLASS is refused rather than one address, for a reason that outlives
      ;; that attack: disbursed tokens are ORDINARY tokens that vote and earn, and an excluded
      ;; account silently holds neither.
      ;; 🔴 RESIDUAL, named rather than left to be discovered: an ordinary holder can still
      ;; transfer tokens INTO the launch reserve, for the same debitability reason. That loss
      ;; lands on the holder who acted, with their own tokens — but it means the launch reserve
      ;; is not bounded at its initial size by construction.
      ;; 🔴 LET-BOUND, NOT INLINE — this reads `state`, and no test can catch the inline form.
      (let ((target-excluded (excluded? target)))
        (enforce (not target-excluded)
          "SPT disbursement target must not be an excluded account"))
      (with-read tranche-locks tranche
        { "total" := tot, "released" := rel, "cliff-end" := ce, "vest-end" := ve }
        ;; 🔴 THE CALENDAR BOUND — the single line that keeps a disbursement a WHERE-decision
        ;; and not a WHEN-decision. Removing it would let one transaction empty a reserve YEARS
        ;; EARLY, which is precisely the pre-commitment the tranche locks exist to make.
        (let ((avail (- (tranche-vested tot ce ve (curr-time)) rel)))
          (enforce (<= amount avail) "SPT disbursement exceeds the vested available amount")
          (let ((reserve (if (= tranche TRANCHE-TREASURY) TREASURY-ACCOUNT LIQUIDITY-ACCOUNT)))
            ;; 🔴 THE TARGET IS RESOLVED BEFORE ANYTHING MOVES, and the order is load-bearing:
            ;; this read aborts if the account does not exist, which is the intended refusal.
            ;; Nothing may move before every refusal has had its chance.
            ;; It is read AFTER the availability bound on purpose, so a pre-cliff call with a
            ;; typo'd target still fails on the CALENDAR — the more important refusal.
            (with-read accounts target { "guard" := tg }
            ;; ---- INLINED RESERVE DEBIT + PAIRED CREDIT ---------------------------------
            ;; 🔴 Same shape and the same ORDER as the release above: the reserve is debited
            ;; FIRST, so the credit is backed by a real movement of existing supply. NEVER
            ;; REORDER. Inlined rather than shared because Pact has no private functions, so a
            ;; NAMED reserve-mover is reachable by anything that can satisfy its gate.
            ;; The balance enforce below is STRUCTURALLY UNREACHABLE and kept as a backstop,
            ;; with its OWN message so the two paths can never mask each other in a mutation
            ;; sweep. It is deliberately not claimed as covered by a negative test.
              (with-read accounts reserve { "balance" := rbal }
                (enforce (<= amount rbal) "SPT disbursement exceeds the reserve balance")
                (update accounts reserve { "balance": (- rbal amount) }))
              ;; The target's OWN stored guard — read above, never supplied.
              (with-capability (CREDIT target)
                (credit target tg amount)))
            (update tranche-locks tranche { "released": (+ rel amount) })
            ;; Two-sided TRANSFER — existing supply moving between real accounts, not a mint —
            ;; plus the disclosure event carrying what no fungible event can: which tranche,
            ;; and the running total sent.
            (emit-event (TRANSFER reserve target amount))
            (emit-event (TRANCHE-DISBURSED tranche target amount (+ rel amount)))
            amount)))))
)

;; Deploy footer. A FRESH deploy creates every table; an UPGRADE must create ONLY tables new to
;; the version being upgraded FROM, because re-running create-table for an existing table ABORTS
;; THE WHOLE TRANSACTION. Either branch aborts on the first table that already exists, so a
;; branch creating the wrong set is not a partial upgrade — it is no upgrade path at all.
;; `upgrade` is a REQUIRED, EXPLICIT input, deliberately: on a one-way door the operator states
;; the case rather than a default silently picking wrong. It also gates the keyset definitions,
;; so an upgrade can never rotate the admin keysets.
;;
;; 🔴 READ THIS BEFORE ADDING A FIELD OR A TABLE. "This version adds no new tables" is a FACT
;; ABOUT THIS VERSION, not a law. A future upgrade adding a table MUST create it here, and one
;; adding a FIELD needs its own one-shot migration KEYED ON THE FIELD — a default covers a
;; missing ROW, never a missing FIELD, and there is no general migration hook here.
;; 🔴 KEY THAT MIGRATION ON THE FIELD, NEVER ON A ROW: a migration gated on a row every chain
;; writes at init can never fire, because the row is there from day one.
;; ---- FOOTER REPLACED BY run-tests.sh gen_frozen_blessed (upgrade-only fixture) ----
(if (read-msg 'upgrade) ["frozen fixture: no new tables"] ["frozen fixture: upgrade-only"])
