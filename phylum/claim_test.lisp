;; Copyright © 2024 Luther Systems, Ltd. All right reserved.

(in-package 'sandbox)
(use-package 'testing)

 ;; overwrite return from cc:creator such that tests can complete
(set 'cc:creator (lambda () "Org1MSP"))

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

;; get the request corresponding to the event ctx.
(defun get-connector-event-req (ctx)
  (let* ([key (get ctx "key")]
         [pdc (get ctx "pdc")]
         [event-bytes (if pdc 
                        (cc:storage-get-private pdc key) 
                        (cc:storage-get key))]
         [event (json:load-bytes event-bytes)])
    event))

;; lookup the event ctx for a request ID.
(defun get-connector-event-ctx (rid)
  (get (connector-handlers 'get-callback-state rid) "ctx"))

;; get all the events within a tx, recursively.
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

;; get all the events raised within the tx.
(defun get-connector-event-reqs ()
  (let* ([m (get-tx-metadata)]
         [output (sorted-map)])
    (get-connector-event-recurse m 0 output)
    (vals output)))

;;
;; connector tests
;;

(defun start-new-event-loop ()
  (let* ([claim (create-claim)]) 
    (cc:debugf (sorted-map "claim" claim) "start-new-event-loop")
    (assert (not (nil? claim)))
    (assert (not (nil? (get claim "claim_id")))) 
    (trigger-claim (get claim "claim_id") (sorted-map))))

(defun assert-no-more-events ()
  (let* ([event-reqs (get-connector-event-reqs)])
    ;; done, no more events! 
    (assert-equal (length event-reqs) 0)))

(defun process-single-event-empty-response ()
  (let* ([event-reqs (get-connector-event-reqs)]
         [_ (assert-equal 1 (length event-reqs))]
         [req (first event-reqs)]
         [req-id (get req "request_id")]
         [resp (sorted-map "request_id" req-id)])
      ;; simulate a new tx by resetting existing events
      (connector-events 'reset)
      ;; simulate the connectorhub callback
      (connector-handlers 'call-handler-with-body resp)))

(defun process-event-loop (iters &optional start)
  (when start (start-new-event-loop))
  (if (<= iters 0)
    (assert-no-more-events)
    (progn
      (process-single-event-empty-response)
      (process-event-loop (- iters 1)))))

(test "test-claim-factory" (process-event-loop 7 true))
