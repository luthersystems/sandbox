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

 ;; overwrite return from cc:creator such that tests can complete
(set 'cc:creator (lambda () "Org1MSP"))

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

;;
;; helper functions to interrogate the state after running the tests.
;;

;;;; get-connector-event-req retrieves the connector request from state using
;; the given connector event context.
(defun get-connector-event-req (ctx)
  (let* ([key (get ctx "key")]
         [pdc (get ctx "pdc")]
         [event-bytes (if pdc 
                        (cc:storage-get-private pdc key) 
                        (cc:storage-get key))]
         [event (json:load-bytes event-bytes)])
    event))

;;;; get-connector-event-ctx looks up the event context given a request ID.
;; Used to inspect connector request metadata.
(defun get-connector-event-ctx (rid)
  (get (connector-handlers 'get-callback-state rid) "ctx"))

;; get-connector-event-recurse recursively walks all events in the current
;; transaction metadata and builds a map of connector requests by index.
;; Used to extract all raised events for test assertions.
(defun get-connector-event-recurse (metadata i output)
  (let* ([event-ref-key (format-string "$connector_events:{}" i)])
    (when (key? metadata event-ref-key)
      (let* ([event-ref-json (get metadata event-ref-key)]
             [event-ref (json:load-string event-ref-json)]
             [rid (get event-ref "rid")]
             [ctx (get-connector-event-ctx rid)]
             [req (get-connector-event-req ctx)])
        (assoc! req "request_id" rid)
        (assoc! output (to-string i) req)
        (get-connector-event-recurse metadata (+ i 1) output)))))

;; get-connector-event-reqs returns a vector of all connector requests raised
;; during the current transaction.
(defun get-connector-event-reqs ()
  (let* ([m (get-tx-metadata)]
         [output (sorted-map)])
    (get-connector-event-recurse m 0 output)
    (vals output)))

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
  (let* ([event-reqs (get-connector-event-reqs)])
    ;; done, no more events! 
    (assert-equal (length event-reqs) 0)))

;; process-single-event-empty-response simulates a connectorhub callback with
;; an empty response body for the first pending event.
;; Used to advance the state machine during tests.
(defun process-single-event-empty-response ()
  (let* ([event-reqs (get-connector-event-reqs)]
         [_ (assert-equal 1 (length event-reqs))]
         [req (first event-reqs)]
         [req-id (get req "request_id")]
         [resp (sorted-map "request_id" req-id)])
    ;; simulate a new tx by resetting existing events
    (connector-events 'reset)
    ;; simulate the connectorhub callback
    (connector-handlers 'invoke-handler-with-body resp)))

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
