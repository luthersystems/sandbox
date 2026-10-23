;; Copyright © 2025 Luther Systems, Ltd. All right reserved.
;; ----------------------------------------------------------------------------
;;
;; This file contains unit tests for the claim connector object.
;; It exercises core functionality including:
;; - Claim creation and persistence
;; - State transitions and event triggering
;; - Connector event simulation and response handling
;;
;; Run with:
;;   make test
;; ----------------------------------------------------------------------------
(in-package 'sandbox)
(use-package 'testing)

;; mk-test-claimant returns a map with mock claimant details.
;; Used to simulate an inbound claim submission.
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

;; populate-test-claimant! mutates the given claim to add a test claimant.
;; Used to simulate user input collected from the portal.
(defun populate-test-claimant! (claim)
  (let* ([claimant (mk-test-claimant)])
    (assoc! claim "claimant" claimant)))

;; Basic storage test for claim lifecycle:
;; - Ensures claim can be created
;; - Ensures it has valid state and ID
;; - Verifies it can be fetched from storage
(test "claims"
  (let* ([claim (create-claim)]
         [_ (assert (not (nil? claim)))])
    (assert (not (nil? (get claim "state"))))
    (assert (not (nil? (get claim "claim_id"))))
    (let*
      ([claim-id (get claim "claim_id")]
       [got-claim (claims 'get claim-id)])
      (assert (not (nil? got-claim))))))

(use-package 'connector)
(use-package 'connector-test)

;;
;; connector tests
;;

;; start-new-event-loop creates a new claim and triggers the first event.
;; Used to simulate an end-to-end claim submission.
(defun start-new-event-loop ()
  (let* ([claim (create-claim)]) 
    (cc:debugf (sorted-map "claim" claim) "start-new-event-loop")
    (assert (not (nil? claim)))
    (assert (not (nil? (get claim "claim_id"))))
    (populate-test-claimant! claim)
    (trigger-claim (get claim "claim_id") (get claim "claimant"))))

;; assert-no-more-events verifies that no connector events remain to process.
;; Use after all expected events have been handled.
(defun assert-no-more-events ()
  (assert-equal 0 (length (test-pending-events))))

;; process-single-event-empty-response simulates a connectorhub callback with
;; an empty response body for the first pending event.
;; Used to advance the state machine during tests.
(defun process-single-event-empty-response ()
  (assert-equal 1 (length (test-pending-events)))
  ;; resets the pending events (a new tx) and runs the real callback
  (test-respond-empty))

;; process-event-loop advances the claim state machine by simulating connector
;; responses across `iters` iterations.
;;
;; Parameters:
;; - iters: number of iterations (connector responses) to simulate
;; - start: if true, starts a new claim first
(defun process-event-loop (iters &optional start)
  (when start (start-new-event-loop))
  (if (<= iters 0)
    (assert-no-more-events)
    (progn
      (process-single-event-empty-response)
      (process-event-loop (- iters 1)))))

;; Integration test for full claim processing loop.
;; Runs 7 connector event cycles from new claim to DONE state.
(test "test-claim-factory" (process-event-loop 7 true))
