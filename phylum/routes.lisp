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

;; example endpoint triggering an event in stateDB
(defendpoint "start" (event-req)
  (let* ([event (sorted-map
                  "key" "fnord" 
                  "req" event-req)])
    (add-connector-event event "claim")
    (route-success event)))

;; example endpoint triggering an event in sideDB
(defendpoint "start-pvt" (event-req)
  (let* ([event (sorted-map
                  "msp" "Org1MSP"
                  "key" "fnord"
                  "pdc" "private"
                  "req" event-req)])
    (add-connector-event event "claim")
    (route-success event)))

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
