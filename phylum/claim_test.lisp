;; Copyright © 2025 Luther Systems, Ltd. All right reserved.
;; ----------------------------------------------------------------------------
;;
;; Unit tests for the claim flow in claim.lisp.
;;
;; The flow-test package runs each call as its own simulated transaction,
;; as the network would: a start, an input, and one Connector Hub reply per
;; step. So these tests check the same transaction boundaries as production.
;;
;; Run with:
;;   make test
;; ----------------------------------------------------------------------------
(in-package 'sandbox)
(use-package 'testing)

;; mk-test-claimant returns a claimant as the oracle sends it (proto JSON).
(defun mk-test-claimant ()
  (sorted-map "account_number"    ""
              "account_sort_code" ""
              "dob"               "1945-11-01"
              "surname"           "Smith"
              "forename"          "Raymond"
              "full_address"      "3 High Street"
              "address_number"    "3"
              "address_street1"   "High Street"
              "address_postcode"  "BA13 3BN"
              "address_post_town" "Westbury"
              "nationality"       "NATIONALITY_GB"))

;; mk-test-details returns the body of a create_claim request.
(defun mk-test-details ()
  (sorted-map "date_of_accident" "2024-01-15"
              "damage_amount"    "500000"
              "claim_reason"     "Car accident due to adverse weather conditions."))

;; claim-steps lists the connector steps of the claim flow, in order. A test
;; that walks the flow checks each label, so a reordered step fails with
;; the name of the step.
(set 'claim-steps
     (list "verify-identity" "collect-policy" "verify-policy" "issue-invoice"
           "approve-invoice" "email-invoice" "pay"))

;; start-test-claim starts a claim as Org1MSP and returns its run ID.
(defun start-test-claim (request-key)
  (flow-test:as "Org1MSP")
  (get (flow-test:start 'claim request-key (mk-test-details)) "run_id"))

;; claim-view returns the run as get_claim returns it.
(defun claim-view (run)
  (flow-test:run 'claim run))

(test "a new claim waits for the claimant"
  (let* ([run (start-test-claim "k1")]
         [view (claim-view run)])
    (assert-string= "waiting" (get view "state"))
    (assert-string= "claimant" (get view "label"))
    (assert-equal (mk-test-details) (get (get view "vars") "details"))))

(test "a claim runs every step to done"
  (let* ([run (start-test-claim "k2")])
    (flow-test:input 'claim 'claimant run (mk-test-claimant))
    (map 'list
         (lambda (step)
           (assert-string= step (get (claim-view run) "label"))
           (flow-test:reply 'claim run (sorted-map)))
         claim-steps)
    (let* ([view (claim-view run)]
           [result (get view "result")])
      (assert-string= "done" (get view "state"))
      (assert-string= "STATUS_PAID" (get result "status"))
      (assert-equal (mk-test-claimant) (get result "claimant"))
      (assert-equal (mk-test-details) (get result "details")))))

(test "a start is idempotent per request key"
  (let* ([run (start-test-claim "k3")]
         [again (start-test-claim "k3")])
    (assert-string= run again)))

(test "a claimant without a forename is refused"
  (let* ([run (start-test-claim "k4")]
         [bad (assoc (mk-test-claimant) "forename" "")]
         [gen (get (claim-view run) "gen")]
         [refusal (flow-test:rejection 'claim "in:claimant" run bad gen)])
    (assert-string= "schema" (get refusal "error"))
    ;; A refused input commits nothing: the claim still waits for it.
    (assert-string= "claimant" (get (claim-view run) "label"))))

(test "a connector error fails the claim"
  (let* ([run (start-test-claim "k5")])
    (flow-test:input 'claim 'claimant run (mk-test-claimant))
    (flow-test:reply-error 'claim run "equifax unavailable")
    (let* ([view (claim-view run)])
      (assert-string= "failed" (get view "state"))
      (assert-string= "verify-identity" (get (get view "error") "label")))))
