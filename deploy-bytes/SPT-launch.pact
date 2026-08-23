(namespace (read-msg 'ns))
(module SPT-launch GOVERNANCE
  @doc "Fixed-price token launch: buyers pay KDA and receive SPT from the launch reserve. Price and active state are per chain, and there is no per-buyer cap."
  (defschema sale-config
    @doc "Singleton row keyed config, one per chain: active is whether buying is open, price is the KDA a buyer pays per SPT, and min-price is the settable floor that price must respect. Read it via is-active, get-price, get-min-price."
    active:bool price:decimal min-price:decimal)
  (deftable config:{sale-config})
  (defschema init-schema
    @doc "Singleton row keyed init: initialized is set true by init and is never reset, so a chain can be initialized only once. Written only by init and read only by enforce-not-initialized."
    initialized:bool)
  (deftable init-state:{init-schema})
  (defconst GOV-KS "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
  (defconst OPS-KS "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-ops")
  (defconst CONFIG-KEY "config")
  (defconst INIT-KEY "init")
  (defconst FROZEN-MODULE false)
  (defconst MIN-PRICE-FLOOR 0.00001)
  (defconst MIN-PRICE-INITIAL 0.01)
  (defun enforce-price:bool (price:decimal price-floor:decimal)
    @doc "Enforces a candidate sale price: it must be at least price-floor and must not exceed KDA precision."
    (enforce (>= price price-floor)
      (format "price below the {} KDA/SPT floor" [price-floor]))
    (enforce (= (floor price (coin.precision)) price)
      "price must respect KDA precision"))
  (defcap TOKENS-PURCHASED (buyer:string amount:decimal price:decimal) @event true)
  (defcap PROCEEDS-WITHDRAWN (to:string amount:decimal)
    @event
    (require-capability (WITHDRAW-PROCEEDS to amount)))
  (defcap GOVERNANCE ()
    @doc "Upgrade gate: requires GOV-KS, and refuses every upgrade once FROZEN-MODULE is true."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset GOV-KS))
  (defcap ADMIN-GOV ()
    @doc "Governance tier: requires GOV-KS. Gates operations that are irreversible or move value out."
    (enforce-keyset GOV-KS))
  (defcap ADMIN-OPS ()
    @doc "Operations tier: requires OPS-KS. Gates reversible day-to-day operation within limits it cannot change."
    (enforce-keyset OPS-KS))
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
  (defun get-price:decimal ()
    @doc "Permissionless read: the current sale price in KDA per SPT. Buying N SPT costs N times this, floored to KDA precision; the call fails on a chain where the sale was never initialized."
    (at 'price (read config CONFIG-KEY)))
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
  (defun init:string (price:decimal)
    @doc "spt-gov: one-time per-chain sale init, starting inactive; price must respect KDA precision and be at least MIN-PRICE-INITIAL. Requires SPT initialized on this same chain first."
    (with-capability (ADMIN-GOV)
      (enforce-not-initialized)
      (enforce-price price MIN-PRICE-INITIAL)
      (let ((recorded (SPT.get-launch-reserve)))
        (enforce (= recorded LAUNCH-RESERVE-ACCOUNT)
          "SPT was initialized with a different launch reserve account"))
      (let ((tok-circ (SPT.get-circulating)))
        (enforce (>= tok-circ 0.0)
          "SPT is not initialized on this chain"))
      (insert config CONFIG-KEY { "active": false, "price": price, "min-price": price })
      (SPT.ensure-coin-account SALES-PROCEEDS-ACCOUNT SALES-PROCEEDS-G)
      (insert init-state INIT-KEY { "initialized": true })
      "sale initialized"))
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
        (coin.transfer-create buyer SALES-PROCEEDS-ACCOUNT SALES-PROCEEDS-G cost)
        (install-capability (SPT.TRANSFER LAUNCH-RESERVE-ACCOUNT buyer amount))
        (SPT.transfer-create LAUNCH-RESERVE-ACCOUNT buyer buyer-guard amount)
        (emit-event (TOKENS-PURCHASED buyer amount price))
        "tokens purchased")))
  (defun set-price:string (new-price:decimal)
    @doc "spt-gov: sets the price a buyer pays. Allowed only while the sale is paused, and only at or above the current price floor and within KDA precision."
    (with-capability (ADMIN-GOV)
      (let ((active (is-active)))
        (enforce (not active) "SPT price is locked while the sale is active"))
      (let ((price-floor (get-min-price)))
        (enforce-price new-price price-floor))
      (update config CONFIG-KEY { "price": new-price })
      "price updated"))
  (defun set-min-price:string (new-min:decimal)
    @doc "spt-gov: sets the price floor that set-price must respect. Refused below MIN-PRICE-FLOOR, and refused while the sale is active or outside KDA precision."
    (with-capability (ADMIN-GOV)
      (let ((active (is-active)))
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
  (defun resume-sale:string ()
    @doc "spt-ops: open the sale at the current price, which must be at or above the price floor. The sale ships closed, so buying is impossible until this is called."
    (with-capability (ADMIN-OPS)
      (let ((c (read config CONFIG-KEY)))
        (enforce (>= (at 'price c) (at 'min-price c))
          "SPT sale cannot open below its own price floor"))
      (update config CONFIG-KEY { "active": true })
      "sale resumed"))
  (defun withdraw-proceeds:string (to:string amount:decimal)
    @doc "spt-gov: moves amount KDA of proceeds to an existing coin account. The signature must name WITHDRAW-PROCEEDS, and the amount it approves for this destination is a spending limit the contract enforces — an unscoped signature cannot drive this at all."
    (with-capability (WITHDRAW-PROCEEDS to amount)
      (enforce (> amount 0.0) "SPT proceeds amount must be positive")
      (install-capability (coin.TRANSFER SALES-PROCEEDS-ACCOUNT to amount))
      (coin.transfer SALES-PROCEEDS-ACCOUNT to amount)
      (emit-event (PROCEEDS-WITHDRAWN to amount))
      "proceeds withdrawn"))
)
(if (read-msg 'upgrade)
  [ (SPT-launch.is-active)
    "upgrade" ]
  [ (create-table config)
    (create-table init-state) ])
