;; ============================================================================================
;; SPT-launch — ANNOTATED SOURCE. THIS IS NOT THE FILE THAT IS DEPLOYED.
;;
;; The deployed payload is `deploy-bytes/SPT-launch.pact`, which is this file with every `;;` comment
;; removed. Both carry module hash
;;     RMn_SApRndMLn4b0MGIm-CE2zWRsU3m5t4e-EnHpyTY
;; because a Pact module hash excludes `;;` comments — so the annotations below are provably
;; absent from the program that runs, and the program that runs is provably the one reviewed.
;; `VERIFY.md` shows how to check that yourself rather than take it on trust.
;; ============================================================================================
;; SPT-launch — fixed-price launch for SPT.
;; Owns the launch reserve (SPT) and the sales proceeds (KDA) account; moves SPT via
;; SPT. Price and active state are per chain.
(namespace (read-msg 'ns))

(module SPT-launch GOVERNANCE
  @doc "Fixed-price token launch: buyers pay KDA and receive SPT from the launch reserve. Price and active state are per chain, and there is no per-buyer cap."

  ;; ---- SCHEMAS / TABLES ------------------------------------------------------------------
  ;; Three price levels, deliberately: `price` is what a buyer pays; `min-price` is a settable
  ;; floor under it; MIN-PRICE-FLOOR is a defconst hard minimum under that, and it freezes.
  (defschema sale-config
    @doc "Singleton row keyed config, one per chain: active is whether buying is open, price is the KDA a buyer pays per SPT, and min-price is the settable floor that price must respect. Read it via is-active, get-price, get-min-price."
    active:bool price:decimal min-price:decimal)   ; price = KDA per SPT
  (deftable config:{sale-config})                      ; singleton "config"

  (defschema init-schema
    @doc "Singleton row keyed init: initialized is set true by init and is never reset, so a chain can be initialized only once. Written only by init and read only by enforce-not-initialized."
    initialized:bool)
  (deftable init-state:{init-schema})

  ;; ---- CONSTANTS -------------------------------------------------------------------------
  ;; Both keysets are DEFINED by SPT's deploy footer; this module only references
  ;; them. The namespace inside these literals is patched at deploy time.
  ;; Placement rule for anything added later: OPERATING within a limit = OPS-KS; CHANGING a
  ;; limit, or moving value out = GOV-KS.
  ;; 🔴 The ops predicate is `keys-any`, NOT `keys-1`: Pact has no `keys-1`. `define-keyset`
  ;; ACCEPTS the name and fails only at the first `enforce-keyset`, so a wrong predicate
  ;; deploys clean and bricks every ops operation forever.
  (defconst GOV-KS "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
  (defconst OPS-KS "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-ops")
  (defconst CONFIG-KEY "config")
  (defconst INIT-KEY "init")
  (defconst FROZEN-MODULE true)

  ;; ---- A PRICE FLOOR, AND DELIBERATELY NO CEILING -----------------------------------------
  ;; 🔴 THE FLOOR IS LOAD-BEARING. Bounded only by "positive + precision", a price of 1e-12
  ;; lets ONE permissionless `buy` take the whole reserve for 0.00000002 KDA — one mistyped
  ;; exponent, no second signature, no undo. The tempting dismissal, that `(enforce (> cost
  ;; 0.0))` already catches it, is FALSE: cost floors to near-zero-but-POSITIVE and passes.
  ;;
  ;; 🔴 NO MAXIMUM PRICE, because the two ends are not symmetric. Too LOW hands a stranger the
  ;; reserve. Too HIGH harms nobody: the buyer's own purchase fails on the buyer's own funds,
  ;; and the operator can both SEE it (no sales happen) and fix it alone. A ceiling would buy
  ;; nothing and freeze forever.
  ;;
  ;; MIN-PRICE-FLOOR is a FAT-FINGER guard, never a solvency guarantee — at the floor itself
  ;; the whole 20,000-SPT reserve costs 0.2 KDA. It sits far below the operating price on
  ;; purpose: a hard minimum set AT the working value is not a floor, it IS the value. The real
  ;; protection is `min-price` in the config row, which spt-gov can move as KDA appreciates.
  ;; 🔴 This constant can never be raised after the freeze, so it errs low.
  (defconst MIN-PRICE-FLOOR 0.00001)    ; KDA per SPT — the hard minimum under `min-price`
  ;; The minimum acceptable OPENING price: `init` validates against it and never stores it.
  ;; The stored floor starts at the opening price; from there only `set-min-price` moves it.
  (defconst MIN-PRICE-INITIAL 0.01)     ; KDA per SPT

  ;; 🔴 THE PARAMETER IS `price-floor`, NOT `floor`: `floor` is a Pact native and the module
  ;; REFUSES TO LOAD if a binding shadows one. A load-time error, so it cannot reach a chain.
  (defun enforce-price:bool (price:decimal price-floor:decimal)
    @doc "Enforces a candidate sale price: it must be at least price-floor and must not exceed KDA precision."
    (enforce (>= price price-floor)
      (format "price below the {} KDA/SPT floor" [price-floor]))
    ;; more precision than KDA can express would silently truncate the cost computed in `buy`
    (enforce (= (floor price (coin.precision)) price)
      "price must respect KDA precision"))

  ;; ---- EVENTS / GOVERNANCE ---------------------------------------------------------------
  ;; PROCEEDS-WITHDRAWN carries a BODY, so a withdrawal record cannot be fabricated: on a
  ;; sale of this kind, an empty body would make a fake one free to anyone.
  ;;
  ;; TOKENS-PURCHASED is deliberately weak, and therefore forgeable. `buy` is PERMISSIONLESS,
  ;; so no holder exists to require, and requiring the token TRANSFER cap instead would lock
  ;; out the legitimate emitter (it is released before this line runs) — a liveness
  ;; regression, not a hardening. 🔴 READ THE TABLE, NOT THE STREAM.
  (defcap TOKENS-PURCHASED (buyer:string amount:decimal price:decimal) @event true)
  (defcap PROCEEDS-WITHDRAWN (to:string amount:decimal)
    @event
    (require-capability (WITHDRAW-PROCEEDS to amount)))

  (defcap GOVERNANCE ()
    @doc "Upgrade gate: requires GOV-KS, and refuses every upgrade once FROZEN-MODULE is true."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset GOV-KS))

  ;; ---- WHICH ADMIN FUNCTION SITS ON WHICH TIER --------------------------------------------
  ;; ONE key (ops): pause, resume-sale — each operates within a limit it cannot change, and
  ;; each is undone by the operator alone.
  ;; TWO keys (gov): init, set-price, set-min-price, withdraw-proceeds — one-shot, or naming
  ;; what a buyer pays, or moving a limit, or moving KDA out.
  ;; 🔴 Both tiers freeze, so a misplacement here is permanent.
  (defcap ADMIN-GOV ()
    @doc "Governance tier: requires GOV-KS. Gates operations that are irreversible or move value out."
    (enforce-keyset GOV-KS))

  (defcap ADMIN-OPS ()
    @doc "Operations tier: requires OPS-KS. Gates reversible day-to-day operation within limits it cannot change."
    (enforce-keyset OPS-KS))

  ;; ---- WHY THIS ONE CAPABILITY IS PARAMETERISED -------------------------------------------
  ;; `ADMIN-GOV` takes no arguments, so ONE signature naming it carries EVERY gov operation in
  ;; this module. Naming WITHDRAW-PROCEEDS instead authorizes one destination and one amount.
  ;; `init` and `set-min-price` stay on the argument-free tier deliberately: neither moves
  ;; value out, and MIN-PRICE-FLOOR bounds set-min-price below whatever a signature says.
  ;; 🔴 ENFORCE `GOV-KS` DIRECTLY here. Do NOT `compose-capability (ADMIN-GOV)` — that puts the
  ;; argument-free tier back on the stack and reinstates the unscoped reach this exists to
  ;; remove.
  ;; 🔴 THE MANAGED IDENTITY EXCLUDES THE MANAGED PARAMETER, so it is `(to)`: one approved
  ;; total per destination, spendable in parts, never exceeded. Without @managed an unscoped
  ;; gov signature moves KDA with an empty clist — measured on a node, mined.
  (defcap WITHDRAW-PROCEEDS (to:string amount:decimal)
    @doc "spt-gov, managed on amount: the signature MUST name this capability and the amount it approves for this destination is a real spending limit that cannot be exceeded. ONE call per destination per transaction — a second call to the same destination is refused by the inner coin transfer, not by this capability. An unscoped signature cannot drive it at all."
    @managed amount WITHDRAW-PROCEEDS-mgr
    (enforce-keyset GOV-KS))

  (defun WITHDRAW-PROCEEDS-mgr:decimal (managed:decimal requested:decimal)
    @doc "Manager for WITHDRAW-PROCEEDS: managed is the KDA still approved for that one destination, requested is this withdrawal, and the return value is the remainder. Pact runs it on each acquisition; over-spending aborts the transaction."
    (let ((remainder (- managed requested)))
      (enforce (>= remainder 0.0)
        (format "WITHDRAW-PROCEEDS exceeded: {} requested of {} managed" [requested managed]))
      remainder))

  ;; ---- INTERNAL ACCOUNTS (module-guarded) --------------------------------------------------
  ;; These two accounts hold the unsold SPT reserve and the KDA a buyer pays. Both are guarded
  ;; by a MODULE guard rather than a capability guard: both rows live in OTHER modules (the SPT
  ;; token, and coin), so the guard is evaluated from outside this module and is satisfied only
  ;; while SPT-launch is genuinely on the call stack. Any other caller falls through to
  ;; this module's admin keyset: a STRANGER fails there, and module GOVERNANCE succeeds — which
  ;; is not a hole, because a gov signer can already redeploy the module.
  ;; 🔴 SAY "A STRANGER FAILS", NEVER "IT FAILS".
  ;; 🔴 THIS IS A PERMANENT CHOICE, NOT A STOPGAP, and it is not reversible: swapping to
  ;; capability guards changes each account's PRINCIPAL, so the door closes at FIRST FUNDING —
  ;; earlier than the freeze. Accepted residual: `create-module-guard` is deprecated, and if it
  ;; is ever removed these accounts cannot be migrated.
  ;; 🔴 NEVER RENAME THIS MODULE AFTER DEPLOY — the principals derive from guards naming it.
  ;; `create-module-guard` must run inside a module FUNCTION frame, hence the defun wrappers.
  (defun launch-reserve-guard:guard ()
    @doc "Builds the module guard that owns the launch reserve, the SPT account holding the unsold tokens. It is satisfied while a call runs inside this module; outside it a stranger fails and only module governance passes."
    (create-module-guard "SPT-launch-reserve"))
  (defun sales-proceeds-guard:guard ()
    @doc "Builds the module guard that owns the sales proceeds, the KDA account every buyer pays into. It is satisfied while a call runs inside this module; outside it a stranger fails and only module governance passes."
    (create-module-guard "SPT-launch-proceeds"))

  (defconst LAUNCH-RESERVE-G (launch-reserve-guard))
  (defconst LAUNCH-RESERVE-ACCOUNT (create-principal LAUNCH-RESERVE-G))
  (defconst SALES-PROCEEDS-G (sales-proceeds-guard))
  (defconst SALES-PROCEEDS-ACCOUNT (create-principal SALES-PROCEEDS-G))

  ;; ---- HELPERS / READS ---------------------------------------------------------------------
  (defun get-price:decimal ()
    @doc "Permissionless read: the current sale price in KDA per SPT. Buying N SPT costs N times this, floored to KDA precision; the call fails on a chain where the sale was never initialized."
    (at 'price (read config CONFIG-KEY)))
  ;; Readable on purpose: a limit nobody can read back is one nobody can verify was set.
  (defun get-min-price:decimal ()
    @doc "Permissionless read: the current price floor in KDA per SPT. set-price cannot go under it and the sale cannot be opened under it; it is readable so anyone can verify the floor that was actually set."
    (at 'min-price (read config CONFIG-KEY)))
  (defun is-active:bool ()
    @doc "Permissionless read: true when the sale is open for buy on this chain. It starts closed at init; only spt-ops opens it with resume-sale or closes it with pause, and the read fails where the sale was never initialized."
    (at 'active (read config CONFIG-KEY)))
  (defun reserve-account:string ()
    @doc "Permissionless read: the SPT account holding the unsold launch reserve that buy delivers from; its balance is what is left to sell. Its address derives from this module's guard, not configuration, so read it rather than hard-code it."
    LAUNCH-RESERVE-ACCOUNT)
  (defun proceeds-account:string ()
    @doc "Permissionless read: the KDA account every buyer's payment lands in, and the account withdraw-proceeds pays out of. Its address derives from this module's guard, not from configuration, so read it here rather than hard-coding it."
    SALES-PROCEEDS-ACCOUNT)

  (defun enforce-not-initialized ()
    @doc "Aborts with sale already initialized once init has run on this chain; a missing row counts as not initialized. It is the one-shot check inside init, and calling it directly only reads state and grants nothing."
    (with-default-read init-state INIT-KEY { "initialized": false } { "initialized" := i }
      (enforce (not i) "sale already initialized")))

  ;; ---- INIT (once per chain) ---------------------------------------------------------------
  ;; The reserve's SPT is minted into it by SPT.init-supply on chain 0.
  (defun init:string (price:decimal)
    @doc "spt-gov: one-time per-chain sale init, starting inactive; price must respect KDA precision and be at least MIN-PRICE-INITIAL. Requires SPT initialized on this same chain first."
    (with-capability (ADMIN-GOV)
      (enforce-not-initialized)
      ;; Validated against MIN-PRICE-INITIAL, a constant and not a stored value: the config row
      ;; does not exist yet, so there is no stored floor to read.
      (enforce-price price MIN-PRICE-INITIAL)
      ;; The token module records the reserve account at ITS init and cannot derive it — a
      ;; reference back to this module would be a load-time cycle. So the check runs from this
      ;; direction, which is legal, and asserts the token was given THIS module's reserve guard
      ;; rather than some other well-formed principal. A mismatch on any chain stops that
      ;; chain's init loudly, before a token or KDA moves.
      ;; 🔴 WHAT MAKES THIS CHECK STRONG: it compares against the token's hard-coded PIN, not
      ;; against a value the token was HANDED at its own init. Comparing against a handed-in value
      ;; would only prove the two inits agreed with each other, which a single mistyped argument
      ;; satisfies. Comparing against the pin makes this the on-chain half of the
      ;; pin-versus-derivation check: it fires if the hand-built literal and this module's
      ;; `create-principal` ever disagree. That is exactly what makes a hand-built principal
      ;; legitimate rather than a guess, and it runs on the hub at sale init.
      ;; 🔴 Let-bound before the enforce — see the read-only-mode rule in `set-price`.
      (let ((recorded (SPT.get-launch-reserve)))
        (enforce (= recorded LAUNCH-RESERVE-ACCOUNT)
          "SPT was initialized with a different launch reserve account"))
      ;; 🔴 AND THE TOKEN MUST ACTUALLY BE INITIALIZED ON THIS CHAIN — ASSERTED, NOT INCIDENTAL.
      ;; The check above cannot carry this. `SPT.get-launch-reserve` returns a code constant and
      ;; touches no table, so it answers identically on a chain where the token has never run its
      ;; own init — which would let the sale initialize against a token with no state row, on a
      ;; chain where nothing can then be bought. The ordering must therefore be asserted here
      ;; rather than inherited from a read that happens to hit the database. A named test fails
      ;; if this assertion is removed.
      ;; `get-circulating` reads the `state` singleton, so it is the honest probe for "the token
      ;; ran its own init here". Let-bound, like every other pre-enforce read.
      (let ((tok-circ (SPT.get-circulating)))
        (enforce (>= tok-circ 0.0)
          "SPT is not initialized on this chain"))
      ;; 🔴 THE FLOOR SEEDS FROM THE PRICE, NEVER FROM A CONSTANT. Seeding a constant would
      ;; leave a sale opened at 1.0 with a floor at one hundredth of its own price — a bound
      ;; attached to nothing. Seeding AT the price needs no magic ratio and means the sale can
      ;; only be repriced upward until someone deliberately lowers the floor.
      (insert config CONFIG-KEY { "active": false, "price": price, "min-price": price })
      ;; 🔴 IDEMPOTENT ON PURPOSE. The guard is a public constant, so a stranger can create
      ;; this coin row first, unsigned; a plain create-account would then abort and brick `init`
      ;; on that chain forever. Tolerating an existing row is safe because coin binds an `m:`
      ;; principal to the guard that derives it, so a squatted row carries the same guard.
      (SPT.ensure-coin-account SALES-PROCEEDS-ACCOUNT SALES-PROCEEDS-G)
      (insert init-state INIT-KEY { "initialized": true })
      "sale initialized"))

  ;; ---- PURCHASE (permissionless; the buyer signs only the KDA payment) ---------------------
  (defun buy:string (buyer:string buyer-guard:guard amount:decimal)
    @doc "Buys amount SPT from the launch reserve while the sale is active; amount must respect SPT precision. The buyer signs a coin.TRANSFER for amount times price, floored to KDA precision."
    (with-read config CONFIG-KEY { "active" := active, "price" := price }
      (enforce active "sale is not active")
      (enforce (and (!= buyer LAUNCH-RESERVE-ACCOUNT) (!= buyer SALES-PROCEEDS-ACCOUNT))
        "SPT sale accounts cannot buy tokens")
      (enforce (> amount 0.0) "SPT token amount must be positive")
      (SPT.enforce-unit amount)
      (let ((cost (floor (* amount price) (coin.precision))))
        (enforce (> cost 0.0) "cost must be positive")
        ;; 1) buyer pays KDA into sales proceeds
        (coin.transfer-create buyer SALES-PROCEEDS-ACCOUNT SALES-PROCEEDS-G cost)
        ;; 2) deliver SPT from the reserve. No capability to acquire: the reserve's module
        ;;    guard is satisfied because this spend runs inside SPT-launch.
        (install-capability (SPT.TRANSFER LAUNCH-RESERVE-ACCOUNT buyer amount))
        (SPT.transfer-create LAUNCH-RESERVE-ACCOUNT buyer buyer-guard amount)
        (emit-event (TOKENS-PURCHASED buyer amount price))
        "tokens purchased")))

  ;; ---- ADMIN -------------------------------------------------------------------------------
  (defun set-price:string (new-price:decimal)
    @doc "spt-gov: sets the price a buyer pays. Allowed only while the sale is paused, and only at or above the current price floor and within KDA precision."
    ;; Two keys, because the sale is a one-time launch and the price is set once — the second
    ;; device costs nothing here. `pause` stays at one key deliberately: it is the brake, and a
    ;; brake must never be harder to reach than the thing it stops.
    (with-capability (ADMIN-GOV)
      ;; 🔴 THE HOUSE RULE, AND IT APPLIES EVERYWHERE IN BOTH MODULES: let-bind a table read,
      ;; then enforce on the BINDING. A read inside an enforce condition trips read-only mode
      ;; on some nodes, and the REPL cannot see it — so a test suite stays green either way.
      (let ((active (is-active)))
        (enforce (not active) "SPT price is locked while the sale is active"))
      (let ((price-floor (get-min-price)))
        (enforce-price new-price price-floor))
      (update config CONFIG-KEY { "price": new-price })
      "price updated"))

  ;; ---- CHANGING the floor, as opposed to operating under it -------------------------------
  ;; 🔴 GOV, NOT OPS. `set-price` operates WITHIN the limit; this MOVES it. Reachable from the
  ;; ops tier, the design collapses to "one device can do anything": a single key could lower
  ;; the floor, then lower the price through it, reassembling the drain the floor exists to
  ;; stop out of two individually legal steps. A named negative pins this tier.
  ;;
  ;; 🔴 ONLY WHILE THE SALE IS CLOSED. Raising the floor over a live price would leave the sale
  ;; running below its own floor — harmless to a buyer, but the protection the operator thinks
  ;; they just bought is not in force and they cannot see that.
  ;;
  ;; BOUNDARY: this constrains FUTURE prices only. It does not reprice a live sale, does not
  ;; touch `active`, and cannot raise MIN-PRICE-FLOOR, which freezes with the code.
  (defun set-min-price:string (new-min:decimal)
    @doc "spt-gov: sets the price floor that set-price must respect. Refused below MIN-PRICE-FLOOR, and refused while the sale is active or outside KDA precision."
    (with-capability (ADMIN-GOV)
      (let ((active (is-active)))     ; let-bound: see the read-only-mode rule in `set-price`
        (enforce (not active) "SPT price floor is locked while the sale is active"))
      (enforce (>= new-min MIN-PRICE-FLOOR)
        (format "SPT price floor must be at least {} KDA/SPT" [MIN-PRICE-FLOOR]))
      (enforce (= (floor new-min (coin.precision)) new-min)
        "SPT price floor must respect KDA precision")
      (update config CONFIG-KEY { "min-price": new-min })
      "price floor updated"))

  (defun pause:string ()
    @doc "spt-ops: close the sale. Buying stops immediately; the price and the unsold reserve are untouched, and set-price requires this state."
    (with-capability (ADMIN-OPS) (update config CONFIG-KEY { "active": false }) "sale paused"))

  (defun resume-sale:string ()   ; NOT `resume` — that shadows the defpact native (load error)
    @doc "spt-ops: open the sale at the current price, which must be at or above the price floor. The sale ships closed, so buying is impossible until this is called."
    ;; 🔴 WITHOUT THIS ENFORCE THE SALE CAN RUN LIVE BELOW ITS OWN FLOOR, and this is the only
    ;; entrance to that state: pause (one key), raise the floor above the live price (legal
    ;; while paused), then reopen with nothing re-checking the band. Measured on a node at price
    ;; 0.5 against floor 5.0, a buyer took 10 SPT for 5 KDA — a tenfold underpay.
    ;; WHY HERE AND NOT IN `buy`: this is the root cause, not a symptom. Guarding `buy` would
    ;; charge every buyer gas for an operator mistake and leave the bad state reachable.
    ;; NOT A FREEZE DEFECT: if it ever refuses, `set-price` still works on a frozen module while
    ;; paused, so the operator raises the price and reopens. The remedy is theirs alone.
    (with-capability (ADMIN-OPS)
      (let ((c (read config CONFIG-KEY)))   ; let-bound: read-only-mode rule, see `set-price`
        (enforce (>= (at 'price c) (at 'min-price c))
          "SPT sale cannot open below its own price floor"))
      (update config CONFIG-KEY { "active": true })
      "sale resumed"))

  (defun withdraw-proceeds:string (to:string amount:decimal)
    @doc "spt-gov: moves amount KDA of proceeds to an existing coin account. The signature must name WITHDRAW-PROCEEDS, and the amount it approves for this destination is a spending limit the contract enforces — an unscoped signature cannot drive this at all."
    (with-capability (WITHDRAW-PROCEEDS to amount)
      (enforce (> amount 0.0) "SPT proceeds amount must be positive")
      ;; the proceeds account's module guard is satisfied because this spend runs inside
      ;; SPT-launch — there is no capability to forge
      (install-capability (coin.TRANSFER SALES-PROCEEDS-ACCOUNT to amount))
      (coin.transfer SALES-PROCEEDS-ACCOUNT to amount)
      (emit-event (PROCEEDS-WITHDRAWN to amount))
      "proceeds withdrawn"))
)

;; Deploy footer. Fresh deploy creates both tables; an in-place upgrade must create NOTHING,
;; because re-running create-table aborts the upgrade transaction.
;; ---- FOOTER REPLACED BY run-tests.sh gen_frozen (upgrade-only fixture) ----
(if (read-msg 'upgrade) ["frozen fixture: no new tables"] ["frozen fixture: upgrade-only"])
