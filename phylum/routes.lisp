;; Copyright © 2025 Luther Systems, Ltd. All right reserved.
;; ----------------------------------------------------------------------------
;;
;; Defines the RPC endpoints that are not part of the claim flow.
;;
;; The claim endpoints (create_claim, add_claimant, get_claim and the admin
;; endpoints) are not here: the defflow in claim.lisp makes them. That is
;; why this file holds only the service endpoints that every phylum needs.
;; ----------------------------------------------------------------------------
(in-package 'sandbox)

;; app-version-key stores the deployed version of this phylum in statedb.
(set 'app-version-key (format-string "{}:version" service-name))

;; init endpoint: called during a successful over-the-air update.
;; Stores the current phylum version and logs upgrade/init info.
(defendpoint "init" ()
  (let* ([prev-version (statedb:get app-version-key)])
    (if (nil? prev-version)
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
;; cc:force-no-commit-tx makes the transaction read-only: a health check
;; must never write, even if a helper it calls writes by mistake.
(defendpoint "healthcheck" ()
  (cc:force-no-commit-tx)
  (route-success
    (sorted-map "reports"
                (vector (sorted-map
                          "status"          "UP"
                          "service_version" service-version
                          "service_name"    service-name
                          "timestamp"       (cc:timestamp (cc:now)))))))
