(in-package 'sandbox)

(set 'claim-next-state 
  ;; claim is a linear state machine that executes in the defined order:
  (sorted-map 
    "CLAIM_STATE_UNSPECIFIED"                "CLAIM_STATE_UNSPECIFIED"
    "CLAIM_STATE_NEW"                        "CLAIM_STATE_LOECLAIM_COLLECTED_DETAILS"
    "CLAIM_STATE_LOECLAIM_COLLECTED_DETAILS" "CLAIM_STATE_LOECLAIM_ID_VERIFIED" 
    "CLAIM_STATE_LOECLAIM_ID_VERIFIED"       "CLAIM_STATE_OOECLAIM_REVIEWED"
    "CLAIM_STATE_OOECLAIM_REVIEWED"          "CLAIM_STATE_OOECLAIM_VALIDATED"
    "CLAIM_STATE_OOECLAIM_VALIDATED"         "CLAIM_STATE_LOEFIN_INVOICE_ISSUED"
    "CLAIM_STATE_LOEFIN_INVOICE_ISSUED"      "CLAIM_STATE_OOEFIN_INVOICE_REVIEWED"
    "CLAIM_STATE_OOEFIN_INVOICE_REVIEWED"    "CLAIM_STATE_OOEFIN_INVOICE_APPROVED"
    "CLAIM_STATE_OOEFIN_INVOICE_APPROVED"    "CLAIM_STATE_OOEPAY_PAYMENT_TRIGGERED"
    "CLAIM_STATE_OOEPAY_PAYMENT_TRIGGERED"   "CLAIM_STATE_DONE"
    "CLAIM_STATE_DONE"                        ()))

(set 'sys-msp-map
  ;; map from system names to responsible connector MSP IDs
  ;; TODO: for now it's all 1 connector, but in final version each connector
  ;; is run by a separate org (participant).
  (sorted-map
    "CLAIMS_PORTAL_UI"   "Org1MSP"
    "EQUIFAX_ID_VERIFY"  "Org1MSP"
    "POSTGRES_CLAIMS_DB" "Org1MSP"
    "CAMUNDA_WORKFLOW"   "Org1MSP"
    "OPENKODA_INVOICE"   "Org1MSP"
    "CAMUNDA_TASKLIST"   "Org1MSP"
    "EMAIL"              "Org1MSP"
    "GOCARDLESS_PAYMENT" "Org1MSP"))

(defun event-desc-record (sys eng)
  (denil-map (sorted-map "msp" (default (get sys-msp-map sys) "Org1MSP")
                         "sys" sys
                         "eng" eng)))

(set 'claims-state-event-desc
  ;; human description of the triggered event for the state:
  (sorted-map 
    "CLAIM_STATE_UNSPECIFIED"                ()
    "CLAIM_STATE_NEW"                        (event-desc-record "CLAIMS_PORTAL_UI"   "input claim details")
    "CLAIM_STATE_LOECLAIM_COLLECTED_DETAILS" (event-desc-record "EQUIFAX_ID_VERIFY"  "verify customer identity")
    "CLAIM_STATE_LOECLAIM_ID_VERIFIED"       (event-desc-record "POSTGRES_CLAIMS_DB" "collect policy details")
    "CLAIM_STATE_OOECLAIM_REVIEWED"          (event-desc-record "CAMUNDA_WORKFLOW"   "verify policy")
    "CLAIM_STATE_OOECLAIM_VALIDATED"         (event-desc-record "OPENKODA_INVOICE"   "generate invoice")
    "CLAIM_STATE_LOEFIN_INVOICE_ISSUED"      (event-desc-record "CAMUNDA_TASKLIST"   "approve invoice")
    "CLAIM_STATE_OOEFIN_INVOICE_REVIEWED"    (event-desc-record "EMAIL"              "email invoice")
    "CLAIM_STATE_OOEFIN_INVOICE_APPROVED"    (event-desc-record "GOCARDLESS_PAYMENT" "make payment")
    "CLAIM_STATE_OOEPAY_PAYMENT_TRIGGERED"   ()
    "CLAIM_STATE_DONE"                       ()))

(defun mk-claim (claim)
  ;; mk-claim implements claims handler logic
  (unless claim (error 'missing-claim "missing claim"))
  (let* ([claim-id (get claim "claim_id")]
         [state (or (get claim "state") "CLAIM_STATE_UNSPECIFIED")]
         [events (vector)])
    (labels
      ([add-event (event-req &optional desc)
         (let* ([req-id (mk-uuid)]
                [event (sorted-map
                         "oid" claim-id
                         "key" req-id
                         "pdc" "private"
                         "msp" (default (get desc "msp") "Org1MSP")
                         "sys" (get desc "sys")
                         "eng" (get desc "eng")
                         "req" event-req)])
           (assoc! event-req "request_id" req-id)
           (append! events event))]

       [ret-save ()
         (sorted-map "put" claim
                     "events" events)]

       [next-state! ()
         (let* ([new-state (get claim-next-state state)])
           (assoc! claim "state" new-state)
           new-state)]

       [init ()
         (let* ([state "CLAIM_STATE_NEW"] 
                [_ (assoc! claim "state" state)]
                [desc (get claims-state-event-desc state)]
                [req (sorted-map "claim_id" claim-id "desc" "request claim details")])
           (add-event req desc))
         (ret-save)]
       
       [data () claim]

       [handle (resp) 
         (let* ([new-state (or (next-state!) "")]
                [resp-body (get resp "response")]
                [resp-err (get resp "error")]
                [desc (get claims-state-event-desc new-state)]
                [req (sorted-map "claim_id" claim-id "desc" "TODO")])
           (when resp-err 
             (set-exception-unexpected "unhandled response error"))
           (cc:infof resp-body "got connector resp")
           ;; TODO: do something with the actual response
           (unless (empty? new-state)
             (add-event req desc)
             (ret-save)))])

      (lambda (op &rest args) 
        (cond ((equal? op 'init) (apply init args))
              ((equal? op 'handle) (apply handle args))
              ((equal? op 'data) (apply data args))
              (:else (error 'unknown-operation op)))))))

;; mk-claims implements factory
(defun mk-claims ()
  (labels
    ([name () "claim"]

     [mk-claim-storage-key (claim-id)
       (join-index-cols "sandbox" "claim"  claim-id)]

     [storage-put-claim (claim)
       (sidedb:put (mk-claim-storage-key (get claim "claim_id")) claim)]

     [new-claim () 
       (let* ([claim-data (sorted-map "claim_id" (mk-uuid))]
              [claim (mk-claim claim-data)]) 
         (claim 'init))]

     [storage-get-claim (claim-id)
       (let* ([key (mk-claim-storage-key claim-id)]
              [claim-data (sidedb:get key)])
         (when claim-data (mk-claim claim-data)))]
 
     [storage-del-claim (claim-id)
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

(defun create-claim ()
  ; create claim allocates storage for a new claim, sets the ID and state, and
  ; raises an event to trigger processing.
  (mk-claim (do-transition claims (claims 'new))))
