;; ===========================================================================
;; smartpacts-ipo — fixed-price IPO for SPT
;; Buyer pays KDA -> receives SPT from the capability-guarded IPO reserve.
;; No per-buyer cap. Owns the IPO reserve (SPT) + sales income (KDA) accounts.
;; Reads/transfers via smartpacts-shares.
;; ===========================================================================
(namespace (read-msg 'ns))

(module smartpacts-ipo GOVERNANCE
  @doc "Fixed-price IPO. Delivers SPT from the IPO reserve against KDA payment; \
       \nno per-buyer cap. IPO reserve is funded by smartpacts-shares.init-supply."

  ;; ========================================================================
  ;; SCHEMAS / TABLES
  ;; ========================================================================
  (defschema sale-config active:bool price:decimal)   ; price = KDA per SPT
  (deftable config:{sale-config})                      ; singleton "config"

  (defschema init-schema initialized:bool)
  (deftable init-state:{init-schema})

  ;; ========================================================================
  ;; CONSTANTS
  ;; ========================================================================
  (defconst ADMIN-KS "n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.spt-admin")
  (defconst CONFIG-KEY "config")
  (defconst INIT-KEY "init")
  (defconst FROZEN-MODULE false)

  ;; ========================================================================
  ;; EVENTS / GOVERNANCE
  ;; ========================================================================
  (defcap SHARES-PURCHASED (buyer:string amount:decimal price:decimal) @event true)
  (defcap PROCEEDS-WITHDRAWN (to:string amount:decimal) @event true)

  (defcap GOVERNANCE ()
    @doc "Upgrade gate. FROZEN-MODULE=true permanently blocks upgrades."
    (enforce (not FROZEN-MODULE) "Module is frozen — no further upgrades")
    (enforce-keyset ADMIN-KS))

  (defcap ADMIN () @doc "admin operations gate" (enforce-keyset ADMIN-KS))

  ;; ========================================================================
  ;; INTERNAL ACCOUNTS (capability-guarded)
  ;; ========================================================================
  (defcap IPO-RESERVE-CAP () @doc "guards the IPO reserve SPT account" true)
  (defcap SALES-INCOME-CAP () @doc "guards the sales income KDA account" true)

  (defconst IPO-RESERVE-G (create-capability-guard (IPO-RESERVE-CAP)))
  (defconst IPO-RESERVE-ACCOUNT (create-principal IPO-RESERVE-G))
  (defconst SALES-INCOME-G (create-capability-guard (SALES-INCOME-CAP)))
  (defconst SALES-INCOME-ACCOUNT (create-principal SALES-INCOME-G))

  ;; ========================================================================
  ;; HELPERS / READS
  ;; ========================================================================
  (defun get-price:decimal () (at 'price (read config CONFIG-KEY)))
  (defun is-active:bool () (at 'active (read config CONFIG-KEY)))
  (defun reserve-account:string () IPO-RESERVE-ACCOUNT)
  (defun income-account:string () SALES-INCOME-ACCOUNT)

  (defun enforce-not-initialized ()
    (with-default-read init-state INIT-KEY { "initialized": false } { "initialized" := i }
      (enforce (not i) "sale already initialized")))

  ;; ========================================================================
  ;; INIT (per chain). IPO reserve SPT account is funded by smartpacts-shares.init-supply
  ;; (chain 0) using IPO-RESERVE-ACCOUNT + IPO-RESERVE-G.
  ;; ========================================================================
  (defun init:string (price:decimal)
    (with-capability (ADMIN)
      (enforce-not-initialized)
      (enforce (> price 0.0) "price must be positive")
      (insert config CONFIG-KEY { "active": false, "price": price })
      (coin.create-account SALES-INCOME-ACCOUNT SALES-INCOME-G)
      (insert init-state INIT-KEY { "initialized": true })
      "sale initialized"))

  ;; ========================================================================
  ;; PURCHASE (permissionless; buyer signs the KDA payment)
  ;; ========================================================================
  (defun buy-shares:string (buyer:string buyer-guard:guard amount:decimal)
    @doc "Buyer pays amount*price KDA and receives `amount` SPT from the IPO reserve."
    (with-read config CONFIG-KEY { "active" := active, "price" := price }
      (enforce active "sale is not active")
      (enforce (> amount 0.0) "amount must be positive")
      (smartpacts-shares.enforce-unit amount)
      (let ((cost (floor (* amount price) (coin.precision))))
        (enforce (> cost 0.0) "cost must be positive")
        ;; 1) buyer pays KDA into sales income (buyer authorizes coin.TRANSFER)
        (coin.transfer-create buyer SALES-INCOME-ACCOUNT SALES-INCOME-G cost)
        ;; 2) deliver SPT from the IPO reserve (authorized by this module's cap)
        (with-capability (IPO-RESERVE-CAP)
          (install-capability (smartpacts-shares.TRANSFER IPO-RESERVE-ACCOUNT buyer amount))
          (smartpacts-shares.transfer-create IPO-RESERVE-ACCOUNT buyer buyer-guard amount))
        (emit-event (SHARES-PURCHASED buyer amount price))
        "shares purchased")))

  ;; ========================================================================
  ;; ADMIN
  ;; ========================================================================
  (defun set-price:string (new-price:decimal)
    (with-capability (ADMIN)
      (enforce (> new-price 0.0) "price must be positive")
      (update config CONFIG-KEY { "price": new-price })
      "price updated"))

  (defun pause:string ()
    (with-capability (ADMIN) (update config CONFIG-KEY { "active": false }) "sale paused"))

  (defun resume-sale:string ()   ; NOT `resume` — that shadows the defpact native (load error)
    (with-capability (ADMIN) (update config CONFIG-KEY { "active": true }) "sale resumed"))

  (defun withdraw-proceeds:string (to:string amount:decimal)
    @doc "Admin: move KDA sales proceeds to an external account."
    (with-capability (ADMIN)
      (enforce (> amount 0.0) "amount must be positive")
      (with-capability (SALES-INCOME-CAP)
        (install-capability (coin.TRANSFER SALES-INCOME-ACCOUNT to amount))
        (coin.transfer SALES-INCOME-ACCOUNT to amount))
      (emit-event (PROCEEDS-WITHDRAWN to amount))
      "proceeds withdrawn"))
)

;; Deploy footer. On a FRESH deploy create every table; on an UPGRADE
;; (tx data upgrade: true) skip them — re-running create-table for an
;; existing table aborts the whole tx.
(if (read-msg 'upgrade)
  ["upgrade"]
  [ (create-table config)
    (create-table init-state)
  ])
