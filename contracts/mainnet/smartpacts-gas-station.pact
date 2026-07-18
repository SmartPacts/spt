;; ===========================================================================
;; MAINNET RELEASE CANDIDATE — NOT DEPLOYED. FOR REVIEW.
;;
;; This file is the lineage a mainnet deployment would use. No mainnet
;; deployment exists; nothing here implies one is scheduled. The candidate
;; becomes final only at the pre-mainnet freeze, after a full re-audit.
;;
;; UNLIKE the other two modules, this one is NOT the testnet06 system minus
;; cosmetics: the gas station was REDESIGNED — registry-driven sponsorship
;; replaces the compiled-in allowlist of ../testnet06/. The differences are
;; enumerated in docs/TESTNET-VS-MAINNET.md and mechanically checked:
;;   cd scripts && node compare-lineages.mjs
;; The next testnet deployment will use THIS lineage. Full documentation for
;; outside readers: docs/GAS-STATION.md.
;; ===========================================================================
;; ===========================================================================
;; smartpacts-gas-station — THE Smart Pacts gas station: ONE station sponsors
;; gas for a REGISTRY of approved operations — shareholder actions (vote,
;; claim) AND internal/platform operations, across all current and future
;; Smart Pacts modules. Same module name, same station account, same guard
;; machinery as the constant-allowlist design it replaces; the sponsorship
;; policy moved from a compiled-in constant list to admin-managed on-chain
;; data with per-entry budgets.
;;
;; WHAT CHANGED vs the constant-allowlist design (../testnet06/):
;;   * allowlist defconst -> `registry` TABLE: granting sponsorship to a new
;;     function/module = ONE admin tx (set-entry), no module upgrade. Rows
;;     carry per-network prefixes, so no deployment needs a source edit.
;;   * per-ENTRY gas-limit ceilings + per-ENTRY epoch caps + spend counters:
;;     every operation has its own bounded budget (public grief on one entry
;;     cannot starve the others) and its own on-chain accounting.
;;   * EXEC-ONLY: cont (defpact-continuation) sponsorship is GONE. A cont
;;     carries no exec-code to allowlist, so the prior design could only
;;     bound it with the aggregate cap; this design refuses it entirely.
;;   * the global epoch meter is RETAINED as a total backstop on top of the
;;     per-entry caps.
;;
;; TRUST MODEL (explicit): the registry is admin-keyset-mutable FOREVER —
;; REGISTRY-ADMIN deliberately carries NO frozen gate, so a future
;; FROZEN-MODULE freeze locks the station's CODE while the EXISTING rows
;; (and new registrations within the MAX-REGISTRY-ROWS bound) stay
;; admin-tunable. Freeze note: the bound freezes with the code — it must be
;; confirmed (or raised) BEFORE any freeze, because afterwards no
;; bound-raising upgrade is possible. The admin can therefore sponsor
;; anything; this grants NO new power — the same keyset already owns the KDA
;; float the station spends. Every registry change emits ENTRY-SET (publicly
;; auditable policy history).
;;
;; DRAIN DEFENSE (unchanged in kind, per-entry in granularity): exec-only +
;; single-call + exact-prefix allowlist (trailing-space token boundary) +
;; global gas-price ceiling + per-entry gas-limit ceiling + per-entry epoch
;; cap + global epoch cap, all fail-closed, epoch reset on BLOCK-TIME only.
;; Griefing (validly-shaped txs that fail their own keyset check downstream)
;; burns sponsored gas but is bounded per entry per epoch and self-healing.
;; ===========================================================================
(namespace (read-msg 'ns))

(module smartpacts-gas-station GOVERNANCE
  @doc "Registry-driven gas station: pays coin.GAS for admin-registered      \
       \noperation prefixes. Per-entry gas-limit + epoch-cap + accounting;   \
       \nglobal epoch backstop; exec-only; single-call; fail-closed."

  (implements gas-payer-v1)
  (use coin)

  ;; ========================================================================
  ;; CONSTANTS
  ;; ========================================================================
  ;; The admin keyset name is DERIVED from the deploy transaction's namespace
  ;; — no per-network source edit, no substitution step at deploy time.
  (defconst ADMIN-KS (format "{}.spt-admin" [(read-msg 'ns)]))   ; shared admin keyset (defined by smartpacts-shares)
  ;; Set true and redeploy to permanently freeze upgrades. The REGISTRY stays
  ;; admin-mutable after a freeze BY DESIGN (policy is data, not code).
  (defconst FROZEN-MODULE false)

  ;; Global price ceiling: every sponsored tx must bid at or below this.
  (defconst MAX-GAS-PRICE:decimal 0.000001)
  ;; Hard ceiling on any entry's per-tx gas limit (well under the 150k tx
  ;; ceiling; big enough for a ~10k one-tx operator flow if one is ever
  ;; registered). Module deploys/upgrades are NOT sponsored.
  (defconst MAX-ENTRY-GAS-LIMIT:integer 15000)
  ;; Registry row bound: keeps the sponsored-path prefix scan small and the
  ;; worst-case policy surface enumerable. Raise via module upgrade if ever hit.
  (defconst MAX-REGISTRY-ROWS:integer 32)
  ;; Entry epoch lengths must be sane: 1h .. 7d.
  (defconst MIN-EPOCH-LEN:integer 3600)
  (defconst MAX-EPOCH-LEN:integer 604800)

  ;; Global backstop: total KDA sponsored per global epoch across ALL entries.
  ;; Sized for the whole ecosystem (shareholder vote/claim + platform
  ;; operations) with headroom; an entry's epoch-cap may never exceed it.
  (defconst GLOBAL-EPOCH-CAP:decimal 2.0)
  (defconst GLOBAL-EPOCH-LEN:integer 86400)
  (defconst METER-KEY "meter")
  (defconst EPOCH-ZERO:time (time "1970-01-01T00:00:00Z"))

  ;; ========================================================================
  ;; SCHEMAS / TABLES
  ;; ========================================================================
  ;; Global meter — same row shape as the prior constant-allowlist deployment,
  ;; so the meter row SURVIVES an in-place upgrade from it.
  (defschema meter-row
    epoch-start:time             ; block-time this global epoch began
    spent:decimal)               ; KDA sponsored so far this global epoch
  (deftable meter:{meter-row})

  ;; THE REGISTRY — one row per sponsored operation, keyed by the exact
  ;; function-call prefix (must start "(" and end with a space: the trailing
  ;; space is the whole-token boundary, and it makes any two distinct keys
  ;; non-overlapping — at most one row can ever prefix-match a given code).
  (defschema reg-entry
    max-gas-limit:integer        ; per-tx gas-limit ceiling for this operation
    epoch-cap:decimal            ; KDA sponsored per epoch for this entry
    epoch-len:integer            ; this entry's epoch length (seconds)
    enabled:bool                 ; kill switch (Pact has no row deletion)
    epoch-start:time             ; block-time this entry's epoch began
    spent-epoch:decimal          ; KDA sponsored this epoch (this entry)
    spent-total:decimal)         ; lifetime KDA sponsored (this entry)
  (deftable registry:{reg-entry})

  ;; SINGLETON PREFIX INDEX — the sponsored hot path must never scan the
  ;; table ((keys) on 32 rows measured 40k gas): one bounded list row holds
  ;; every registered prefix.
  ;; Maintained by set-entry; MAX-REGISTRY-ROWS bounds its length.
  (defschema idx-row prefixes:[string])
  (deftable prefix-index:{idx-row})
  (defconst IDX-KEY "idx")

  ;; ========================================================================
  ;; GOVERNANCE / ADMIN CAPS / EVENTS
  ;; ========================================================================
  (defcap GOVERNANCE ()
    @doc "Upgrade gate. FROZEN-MODULE=true permanently blocks upgrades."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset ADMIN-KS))

  (defcap REGISTRY-ADMIN ()
    @doc "Gate for registry policy writes. Deliberately NO frozen gate: the  \
         \nregistry must stay mutable after a code freeze (future modules    \
         \nonboard by admin tx, never by upgrade)."
    (enforce-keyset ADMIN-KS))

  (defcap ENTRY-SET (prefix:string max-gas-limit:integer epoch-cap:decimal epoch-len:integer enabled:bool)
    @doc "Every sponsorship-policy change is a public event."
    @event true)

  ;; ========================================================================
  ;; STATION ACCOUNT — guard machinery IDENTICAL across station upgrades, so
  ;; the funded, deployed account keeps working. The predicate function names
  ;; below are load-bearing: the deployed station account's guard resolves
  ;; them BY NAME — renaming `station-guard-pred` or `gas-payer-pred` in any
  ;; future upgrade would brick the funded account.
  ;; ========================================================================
  (defcap ALLOW_GAS () @doc "internal gas-buy permission token" true)

  (defcap METER ()
    @doc "Internal permission token for charging the meters. Weak body is    \
         \nSAFE: composed ONLY by GAS_PAYER after its checks; never callable \
         \nexternally — so nobody can exhaust the caps at zero cost."
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

  (defun create-gas-payer-guard:guard ()
    (create-user-guard (station-guard-pred)))

  (defconst GAS_STATION:string
    (create-principal (create-user-guard (station-guard-pred))))

  ;; ========================================================================
  ;; GAS CEILINGS (chain-data envelope — protocol-injected, not attacker data)
  ;; Both bounds enforced: positive (a non-positive gas price/limit is rejected
  ;; by Chainweb before it reaches here, so this is defense-in-depth — the
  ;; contract does not rely on that external invariant) AND at-or-below the
  ;; ceiling. Reads are (at 'k (chain-data)), not table reads, so they are
  ;; safe inside enforce on-node.
  ;; ========================================================================
  (defun enforce-below-or-at-gas-price:bool (gas-price:decimal)
    (enforce (> (at 'gas-price (chain-data)) 0.0) "Gas price must be positive")
    (enforce (<= (at 'gas-price (chain-data)) gas-price)
      (format "Gas price must be <= {}" [gas-price])))

  (defun enforce-below-or-at-gas-limit:bool (gas-limit:integer)
    (enforce (> (at 'gas-limit (chain-data)) 0) "Gas limit must be positive")
    (enforce (<= (at 'gas-limit (chain-data)) gas-limit)
      (format "Gas limit must be <= {}" [gas-limit])))

  ;; ========================================================================
  ;; REGISTRY ADMIN
  ;; ========================================================================
  (defun set-entry:string (prefix:string max-gas-limit:integer epoch-cap:decimal epoch-len:integer enabled:bool)
    @doc "ADMIN: create/update a sponsored operation. Upsert preserves the   \
         \nrow's meters; enabled=false is the kill switch (no row deletion). \
         \nPrefix rules make prefix-matches UNIQUE: start '(' + end ' '."
    (with-capability (REGISTRY-ADMIN)
      (enforce (= "(" (take 1 prefix)) "prefix must start with '('")
      (enforce (= " " (take -1 prefix)) "prefix must end with a space (whole-token boundary)")
      (enforce (>= (length prefix) 10) "prefix too short to be a qualified call")
      ;; EXACTLY one space (the trailing one): an internal space would let one
      ;; registered prefix contain another, breaking the at-most-one-match
      ;; invariant — enforced here so the invariant holds by construction.
      (let ((spaces (fold (lambda (n:integer c:string) (if (= " " c) (+ n 1) n))
                          0 (str-to-list prefix))))
        (enforce (= 1 spaces) "prefix must contain exactly one space (the trailing one)"))
      (enforce (and (> max-gas-limit 0) (<= max-gas-limit MAX-ENTRY-GAS-LIMIT))
        (format "max-gas-limit must be in 1..{}" [MAX-ENTRY-GAS-LIMIT]))
      (enforce (and (> epoch-cap 0.0) (<= epoch-cap GLOBAL-EPOCH-CAP))
        "epoch-cap must be > 0 and <= the global epoch cap")
      (enforce (and (>= epoch-len MIN-EPOCH-LEN) (<= epoch-len MAX-EPOCH-LEN))
        "epoch-len must be within 1h..7d")
      (let ((idx (index-prefixes)))
        (with-default-read registry prefix
          { "epoch-start": EPOCH-ZERO, "spent-epoch": 0.0, "spent-total": 0.0, "max-gas-limit": -1 }
          { "epoch-start" := es, "spent-epoch" := se, "spent-total" := st, "max-gas-limit" := existing }
          ;; -1 sentinel = no row yet (a real row always carries a positive limit)
          (if (= existing -1)
            (let ((n (length idx)))
              (enforce (< n MAX-REGISTRY-ROWS) "registry full — disable/reuse an entry or raise the bound via upgrade")
              (write prefix-index IDX-KEY { "prefixes": (+ idx [prefix]) }))
            "existing row — index unchanged")
          (write registry prefix
            { "max-gas-limit": max-gas-limit, "epoch-cap": epoch-cap
            , "epoch-len": epoch-len, "enabled": enabled
            , "epoch-start": es, "spent-epoch": se, "spent-total": st })))
      (emit-event (ENTRY-SET prefix max-gas-limit epoch-cap epoch-len enabled))
      (format "set {}" [prefix])))

  ;; ========================================================================
  ;; MATCHING
  ;; ========================================================================
  (defun index-prefixes:[string] ()
    @doc "The registered prefixes (one bounded singleton-row read, no scan)."
    (with-default-read prefix-index IDX-KEY { "prefixes": [] } { "prefixes" := ps } ps))

  (defun match-entry:[string] (code:string)
    @doc "Registered prefixes matching CODE (0 or 1 by key construction:     \
         \nevery prefix ends with a space, so no two keys can match one code)."
    (filter (lambda (p:string) (= p (take (length p) code))) (index-prefixes)))

  (defun allowlisted?:bool (code:string)
    @doc "True iff CODE matches exactly one ENABLED sponsored entry."
    (let ((m (match-entry code)))
      (if (= 1 (length m))
        (at 'enabled (read registry (at 0 m)))
        false)))

  ;; ========================================================================
  ;; METER CHARGES (internal; METER-gated; the meter write happens inside the
  ;; node's gas-purchase phase — deliberately NOT inside an enforce, because
  ;; read-only mode forbids DML)
  ;; ========================================================================
  (defun charge-entry:bool (prefix:string mgl:integer)
    @doc "Charge this entry's worst-case tx cost against its epoch cap;      \
         \nroll the entry epoch on BLOCK-TIME; fail closed at the cap."
    (require-capability (METER))
    (let ((now (at 'block-time (chain-data)))
          (cost (* MAX-GAS-PRICE (dec mgl))))
      (with-read registry prefix
        { "epoch-cap" := cap, "epoch-len" := elen
        , "epoch-start" := es, "spent-epoch" := se, "spent-total" := st }
        (let* ((rolled (>= (diff-time now es) (dec elen)))
               (base   (if rolled 0.0 se))
               (start  (if rolled now es))
               (spent* (+ base cost)))
          (enforce (<= spent* cap)
            "entry epoch cap reached — sponsorship for this operation paused until its next epoch")
          (update registry prefix
            { "epoch-start": start, "spent-epoch": spent*, "spent-total": (+ st cost) })
          true))))

  (defun charge-global:bool (mgl:integer)
    @doc "Charge the same worst-case cost against the GLOBAL epoch backstop."
    (require-capability (METER))
    (let ((now (at 'block-time (chain-data)))
          (cost (* MAX-GAS-PRICE (dec mgl))))
      (with-default-read meter METER-KEY
        { "epoch-start": EPOCH-ZERO, "spent": 0.0 }
        { "epoch-start" := es, "spent" := sp }
        (let* ((rolled (>= (diff-time now es) (dec GLOBAL-EPOCH-LEN)))
               (base   (if rolled 0.0 sp))
               (start  (if rolled now es))
               (spent* (+ base cost)))
          (enforce (<= spent* GLOBAL-EPOCH-CAP)
            "gas station global epoch cap reached — sponsorship paused until the next epoch")
          (write meter METER-KEY { "epoch-start": start, "spent": spent* })
          true))))

  ;; ========================================================================
  ;; GAS_PAYER — the sponsorship policy (gas-payer-v1)
  ;; ========================================================================
  (defcap GAS_PAYER:bool (user:string limit:integer price:decimal)
    @doc "Sponsor gas iff: an exec of exactly one registry-matched, ENABLED  \
         \ncall, within the global price ceiling and the entry's gas-limit   \
         \nceiling, and within the entry + global epoch caps. Cap args       \
         \n(user/limit/price) are attacker-controllable and NOT used as auth \
         \n— every check reads the protocol-trusted chain-data/tx envelope."
    ;; tx-type / exec-code are injected by Chainweb from the REAL parsed payload
    ;; (not from tx `data`); missing/ill-typed aborts fail-closed (no gas paid).
    (let ((tx-type:string (read-msg "tx-type")))
      (enforce (= "exec" tx-type)
        "gas station sponsors exec transactions only (no cont)"))
    (compose-capability (METER))
    (let ((codes:[string] (read-msg "exec-code")))
      (enforce (= 1 (length codes)) "gas station funds exactly one sponsored call per tx")
      (let* ((code (at 0 codes))
             (m (match-entry code)))
        (enforce (= 1 (length m)) "Not a sponsored call")
        (let ((prefix (at 0 m)))
          (with-read registry prefix { "enabled" := en, "max-gas-limit" := mgl }
            (enforce en "sponsorship for this operation is disabled")
            (enforce-below-or-at-gas-price MAX-GAS-PRICE)
            (enforce-below-or-at-gas-limit mgl)
            (charge-entry prefix mgl)
            (charge-global mgl)))))
    (compose-capability (ALLOW_GAS)))

  ;; ========================================================================
  ;; INIT + READS
  ;; ========================================================================
  (defun init ()
    @doc "ADMIN: create the station coin account on this chain (fresh deploy \
         \nonly; the deploy footer calls it under the admin deploy sig).     \
         \nAdmin funds it out-of-band; seeds the global meter. The gate is   \
         \ndefense-in-depth: on a live station both writes fail closed, and  \
         \nthe account guard is hardcoded to this module's own guard."
    (with-capability (GOVERNANCE)
      (coin.create-account GAS_STATION (create-gas-payer-guard))
      (insert meter METER-KEY { "epoch-start": EPOCH-ZERO, "spent": 0.0 })))

  (defun get-epoch-spent:decimal ()
    @doc "Read-only: KDA sponsored in the current GLOBAL epoch (monitoring)."
    (at 'spent (read meter METER-KEY)))

  (defun get-entry:object{reg-entry} (prefix:string)
    (read registry prefix))

  (defun list-entries:[object] ()
    @doc "Read-only, ops/monitoring: every entry + its meters (index-driven)."
    (map (lambda (k:string)
           (let ((row (read registry k))
                 (tag { "prefix": k }))
             (+ tag row)))
         (index-prefixes)))
)

;; Deploy footer — three modes via tx data:
;;   upgrade:false                  FRESH deploy: all tables + station account.
;;   upgrade:true, migrate-v1:true  IN-PLACE upgrade FROM a live constant-
;;                                  allowlist deployment: create ONLY the new
;;                                  tables (meter + account already exist).
;;   upgrade:true                   re-deploy of THIS design (tuning/freeze):
;;                                  touch nothing.
(if (read-msg 'upgrade)
  (if (try false (read-msg 'migrate-v1))
    [ (create-table registry)
      (create-table prefix-index) ]
    [ "upgrade" ])
  [ (create-table meter)
    (create-table registry)
    (create-table prefix-index)
    (init) ])
