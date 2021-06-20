;; Copyright © 2021 Luther Systems, Ltd. All right reserved.

;; routes.lisp

;; This file defines all of the RPC endpoints exposed by the phylum.  This
;; package uses a simple macro to define a class of readonly endpoints but this
;; is just one approach for defining such middleware that extends all the
;; routes in an application.
(in-package 'sandbox)

;; wrap-endpoint is a simple wrapper for endpoints which allows them to call
;; set-exception and shortcircuit the endpoint handler.  wrap-endpoint may be
;; customised to add universal logging or book-keeping that should be present
;; on every transaction.
(defun wrap-endpoint (route-handler)
  (handler-bind ([set-exception-error
                  (lambda (_ exception)
                    (cc:force-no-commit-tx)
                    (route-success (sorted-map "exception" exception)))])
                (funcall route-handler)))

;; defendpoint shadows router:endpoint so that all endpoints can be wrapped
;; with logic contained in wrap-endpoint.
(defmacro defendpoint (name args &rest exprs)
  (quasiquote
    (router:defendpoint (unquote name) (unquote args)
                        (sandbox:wrap-endpoint (lambda () (unquote-splicing exprs))))))

;; defendpoint-get defines a readonly endpoint, transactions of which are not
;; allowed to be committed.  The shiroclient should automatically detect
;; readonly transactions and avoid committing them.  But defendpoint-get will
;; provide additional protection if a utility function accidentally writes to
;; statedb during these endpoints.
(defmacro defendpoint-get (name args &rest exprs)
  (quasiquote
    (sandbox:defendpoint (unquote name) (unquote args)
                         (cc:force-no-commit-tx) ; get route cannot update statedb
                         (unquote-splicing exprs))))

(set 'chaincode-version-key (format-string "{}:version" service-name))

(defendpoint "init" ()
  (let* ([prev-version (statedb:get chaincode-version-key)]
         [init? (nil? prev-version)])
    (if init?
      (cc:infof (sorted-map "phylum_version" version
                            "build_id" build-id)
                "Phylum initialized")
      (cc:infof (sorted-map "phylum_version" version
                            "phylum_version_old" prev-version
                            "build_id" build-id)
                "Phylum upgraded"))
    (statedb:put chaincode-version-key version)
    (route-success ())))

(defendpoint-get "healthcheck" ()
  (route-success
    (sorted-map "reports"
                (vector (sorted-map
                          "status"          "UP"
                          "service_version" service-version
                          "service_name"    service-name
                          "timestamp"       (cc:timestamp (cc:now)))))))


; initialize entities a and b to integer values
(defendpoint "create_account" (create)
  (let* ([acct (get create "account")])
    (if (create-account! (get acct "account_id") (get acct "current_balance"))
      (route-success ())
      (set-exception-business "account_id already exists"))))

; return the value of entity a
(defendpoint-get "get_account" (acct)
  (let* ([acct (get-account (get acct "account_id"))])
    (if (nil? acct)
      (set-exception-business "account_id not found")
      (route-success (sorted-map "account" acct)))))

; make a payment of x units from entity a to entity b
(defendpoint "transfer" (xfer)
  (let* ([payer-id (get xfer "payer_id")]
         [payee-id (get xfer "payee_id")]
         [xfer-amount (to-int (get xfer "transfer_amount"))])
    (if (account-transfer! payer-id payee-id xfer-amount)
      (route-success ())
      (set-exception-business "account does not exist"))))
