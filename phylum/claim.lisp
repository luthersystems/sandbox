(in-package 'sandbox)

;; TODO: set MSPID on request
;; TODO move methods into single class
;;
;; State Machine:
;;
;;  CLAIM_STATE_LOECLAIM_COLLECTED_DETAILS = 1;
;;  CLAIM_STATE_LOECLAIM_ID_VERIFIED = 2;
;;  CLAIM_STATE_OOECLAIM_REVIEWED = 3;
;;  CLAIM_STATE_OOECLAIM_VALIDATED = 4;
;;  CLAIM_STATE_LOEFIN_INVOICE_ISSUED = 5;
;;  CLAIM_STATE_OOEFIN_INVOICE_REVIEWED = 6;
;;  CLAIM_STATE_OOEFIN_INVOICE_APPROVED = 7;
;;  CLAIM_STATE_OOEPAY_PAYMENT_TRIGGERED = 8;
;;

;; mk-claim implements handler
(defun mk-claim (claim)
  (unless claim (error 'missing-claim "missing claim"))
  (labels
    ([handle
       (resp)
       (let* ([resp-body (get resp "response")]
              [resp-err (get resp "error")])
         (if resp-err
           (cc:errorf resp-err "response error")
           (cc:infof resp "got connector resp"))
         ;; TODO: implement claim state machine
         (sorted-map 
           "put" ()
           "del" false
           "events" ()))])

    (lambda (op &rest args)
        (cond ((equal? op 'handle) (apply handle args))
              (:else (error 'unknown-operation op))))))

;; mk-claims implements factory
(defun mk-claims ()
  (labels
    ([name () "claim"]

     [mk-claim-storage-key
       (claim-id)
       (join-index-cols "sandbox" "claim"  claim-id)]

     [storage-put-claim
       (claim)
       (sidedb:put (mk-claim-storage-key (get claim "claim_id")) claim)]

     [new-claim ()
                (let ([claim (sorted-map "claim_id" (mk-uuid))])
                  (storage-put-claim)
                  claim)]

     [storage-get-claim
       (claim-id)
       (thread-first
         (mk-claim-storage-key claim-id)
         (sidedb:get)
         (mk-claim))]

     [storage-del-claim
       (claim-id)
       (sidedb:del (mk-claim-storage-key claim-id))])

    (lambda (op &rest args)
        (cond ((equal? op 'name) (apply name args))
              ((equal? op 'new) (apply new-claim args))
              ((equal? op 'get) (apply storage-get-claim args))
              ((equal? op 'del) (apply storage-del-claim args))
              ((equal? op 'put) (apply storage-put-claim args))
              (:else (error 'unknown-operation op))))))

(set 'claims (singleton mk-claims))

(register-connector-factory claims)

;;(defun create-claim ()
;;(let ([claim (claims 'new')]
;;      [id (get claim "claim_id")]
;;      [req-id (mk-uuid)]
;;      [event-req (sorted-map
;;                   "request_id" req-id)]
;;      [event (sorted-map
;;               "oid" id
;;               "msp" "Org1MSP"
;;               "key" req-id
;;               "pdc" "private"
;;               "req" event-req)])
;;  (add-connector-event event "claim")
;;  claim))
