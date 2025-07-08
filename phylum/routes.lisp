;; Copyright © 2025 Luther Systems, Ltd. All right reserved.
;; ----------------------------------------------------------------------------
;;
;; Defines all RPC endpoints exposed by this phylum.
;; Endpoints are declared using `defendpoint` (POST) and `defendpoint-get` (GET).
;;
;; All routes are automatically wrapped with error-handling and side-effect
;; protection to ensure consistent behavior and logging.
;;
;; Readonly GET endpoints are protected against state updates via 
;; `cc:force-no-commit-tx`.
;;
;; Each endpoint maps to a handler that interacts with the connector objects
;; defined in claim.lisp.
;; ----------------------------------------------------------------------------
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
;; This exposes an endpoint that is the equivalent of an HTTP POST.
(defmacro defendpoint (name args &rest exprs)
  (quasiquote
    (router:defendpoint (unquote name) (unquote args)
                        (sandbox:wrap-endpoint 
                          (lambda () (unquote-splicing exprs))))))

;; defendpoint-get defines a readonly endpoint, transactions of which are not
;; allowed to be committed.  The shiroclient should automatically detect
;; readonly transactions and avoid committing them.  But defendpoint-get will
;; provide additional protection if a utility function accidentally writes to
;; statedb during these endpoints.
;; This exposes an endpoint that is the equivalent of an HTTP GET.
(defmacro defendpoint-get (name args &rest exprs)
  (quasiquote
    (sandbox:defendpoint (unquote name) (unquote args)
                         (cc:force-no-commit-tx) ; get route cannot update
                         (unquote-splicing exprs))))

;; app-version-key stores the deployed version of this phylum in statedb.
(set 'app-version-key (format-string "{}:version" service-name))


;; init endpoint: called during a successful over-the-air update.
;; Stores the current phylum version and logs upgrade/init info.
(defendpoint "init" ()
  (let* ([prev-version (statedb:get app-version-key)]
         [init? (nil? prev-version)])
    (if init?
      (cc:infof (sorted-map "phylum_version" version
                            "build_id" build-id)
                "Phylum initialized")
      (cc:infof (sorted-map "phylum_version" version
                            "phylum_version_old" prev-version
                            "build_id" build-id)
                "Phylum upgraded"))
    (statedb:put app-version-key version)
    (route-success ())))

;; healthcheck endpoint: returns static service metadata and timestamp.
(defendpoint-get "healthcheck" ()
  (route-success
    (sorted-map "reports"
                (vector (sorted-map
                          "status"          "UP"
                          "service_version" service-version
                          "service_name"    service-name
                          "timestamp"       (cc:timestamp (cc:now)))))))

;; create_claim endpoint: creates a new claim and stores it.
(defendpoint "create_claim" (req)
  (route-success (sorted-map "claim" (create-claim))))

;; add_claimant endpoint: populates claim with claimant info and triggers
;; claim processing state machine.
(defendpoint "add_claimant" (req)
  (let* ([claim-id (or (get req "claim_id")
                       (set-exception-business "missing claim_id"))]
         [claimant (get req "claimant")])
    (when (or (nil? claimant) (empty? (get claimant "forename")))
      (set-exception-business "missing claimant forename"))
    (route-success (sorted-map "claim" (trigger-claim claim-id claimant)))))

;; get_claim endpoint: fetches the full data for a given claim by ID.
(defendpoint-get "get_claim" (req)
  (let* ([claim-id (or (get req "claim_id")
                       (set-exception-business "missing claim_id"))]
         [claim (or (claims 'get claim-id)
                    (set-exception-business 
                      (format-string "missing claim {}" claim-id)))]
         [data (claim 'data)])
    (route-success (sorted-map "claim" data))))
