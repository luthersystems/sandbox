(in-package 'sandbox)

(use-package 'connector)

(defun make-state-chain (chain first-state last-state)
  (let* ([result (sorted-map)]
         [states (append! chain last-state)]
         [build-chain 
           (lambda (current remaining)
              (when (not (empty? remaining))
                (let ([next (first remaining)])
                  (assoc! result current next)
                  (build-chain next (rest remaining)))))])
      (build-chain first-state states)
      result))

(set 'state-transitions
     (make-state-chain (vector
                         "CLAIM_STATE_LOECLAIM_DETAILS_COLLECTED"
                         "CLAIM_STATE_LOECLAIM_ID_VERIFIED"
                         "CLAIM_STATE_OOECLAIM_REVIEWED"
                         "CLAIM_STATE_OOECLAIM_VALIDATED"
                         "CLAIM_STATE_LOEFIN_INVOICE_ISSUED"
                         "CLAIM_STATE_OOEFIN_INVOICE_REVIEWED"
                         "CLAIM_STATE_OOEFIN_INVOICE_APPROVED"
                         "CLAIM_STATE_OOEPAY_PAYMENT_TRIGGERED")
                       "CLAIM_STATE_NEW"
                       "CLAIM_STATE_DONE"))

(set 'sys-msp-map
  ;; map from system names to responsible connector MSP IDs
  ;; TODO: for now it's all 1 connector, but in final version each connector
  ;; is run by a separate org (participant).
  ;; IMPORTANT: these system names MUST match the connectorhub.yaml names!
  (sorted-map
    "CLAIMS_PORTAL_UI"   "Org1MSP"
    "EQUIFAX_ID_VERIFY"  "Org1MSP"
    "POSTGRES_CLAIMS_DB" "Org1MSP"
    "CAMUNDA_WORKFLOW"   "Org1MSP"
    "INVOICE_NINJA"      "Org1MSP"
    "CAMUNDA_TASKLIST"   "Org1MSP"
    "EMAIL"              "Org1MSP"
    "STRIPE_PAYMENT"     "Org1MSP"))

(defun event-desc-record (sys eng)
  (denil-map (sorted-map "msp" (default (get sys-msp-map sys) "Org1MSP")
                         "sys" sys
                         "eng" eng)))

(set 'claims-state-event-desc
  ;; human description of the triggered event for the state:
  (sorted-map 
    "CLAIM_STATE_UNSPECIFIED"                ()
    "CLAIM_STATE_NEW"                        (event-desc-record "CLAIMS_PORTAL_UI"   "input claim details")
    "CLAIM_STATE_LOECLAIM_DETAILS_COLLECTED" (event-desc-record "EQUIFAX_ID_VERIFY"  "verify customer identity") 
    "CLAIM_STATE_LOECLAIM_ID_VERIFIED"       (event-desc-record "CAMUNDA_WORKFLOW"   "collect policy details")
    "CLAIM_STATE_OOECLAIM_REVIEWED"          (event-desc-record "POSTGRES_CLAIMS_DB" "verify policy")
    "CLAIM_STATE_OOECLAIM_VALIDATED"         (event-desc-record "INVOICE_NINJA"      "generate invoice")
    "CLAIM_STATE_LOEFIN_INVOICE_ISSUED"      (event-desc-record "CAMUNDA_TASKLIST"   "approve invoice")
    "CLAIM_STATE_OOEFIN_INVOICE_REVIEWED"    (event-desc-record "EMAIL"              "email invoice")
    "CLAIM_STATE_OOEFIN_INVOICE_APPROVED"    (event-desc-record "STRIPE_PAYMENT"     "make payment")
    "CLAIM_STATE_OOEPAY_PAYMENT_TRIGGERED"   ()
    "CLAIM_STATE_DONE"                       ()))

(defun mk-claim (claim)
  ;; mk-claim implements claims handler logic
  (unless claim (error 'missing-claim "missing claim"))
  (let* ([events (vector)])
    (labels
      (
       ;; id returns the ID of the claim.
       [id () (get claim "claim_id")]

       ;; get-state returns the current state of the claim.
       [get-state () (default (get claim "state") "")]

       [add-event (event-req)
         (let* ([desc (get claims-state-event-desc (get-state))]
                [event (sorted-map
                         "oid" (id)
                         "key" (mk-uuid)
                         "pdc" "private"
                         "msp" (default (get desc "msp") "Org1MSP")
                         "sys" (get desc "sys")
                         "eng" (get desc "eng")
                         "req" event-req)])
           (when event-req (append! events event)))]

       ;; next-state upates `claim` to the next state.
       [next-state ()
         (let* ([new-state (get state-transitions (get-state))])
           (assoc! claim "state" new-state)
           new-state)]

       ;; ret-save returns a map that the connector hub API can use to store 
       ;; new data for the object, and raise events for subsequent processing.
       [ret-save ()
                 (next-state)
                 (sorted-map "put" claim "events" events)]

       [init ()
         (assoc! claim "state" "CLAIM_STATE_NEW")
         (ret-save)]
       
       [data () claim]

       [handle (resp)
         (let* ([resp-body (get resp "response")]
                [resp-err (get resp "error")]
                [state (get-state)])
           (when resp-err 
             (set-exception-unexpected
               (format-string "unhandled response error: {}" resp-err)))
           (cc:infof (assoc resp-body "state" state) "handle")
           (cond
             ((equal? state "CLAIM_STATE_LOECLAIM_DETAILS_COLLECTED")
              (add-event (mk-equifax-req resp)))

             ((equal? state "CLAIM_STATE_LOECLAIM_ID_VERIFIED")
              (add-event (mk-camunda-start-req "a1" (sorted-map "x" "fnord"))))

             ((equal? state "CLAIM_STATE_OOECLAIM_REVIEWED") 
              (add-event (mk-psql-req "SELECT 1;")))

             ((equal? state "CLAIM_STATE_OOECLAIM_VALIDATED")
              (add-event (mk-invoice-ninja-email-req
                           (sorted-map "invoice_id" "mock_invoice_id"))))

             ((equal? state "CLAIM_STATE_LOEFIN_INVOICE_ISSUED")
              (add-event (mk-camunda-inspect-req "a1" "true")))

             ((equal? state "CLAIM_STATE_OOEFIN_INVOICE_REVIEWED")
              (add-event (mk-email-req 
                          "sam.wood@luthersystems.com"
                          "Test Email" 
                          "Hello, this is a test email")))

             ((equal? state "CLAIM_STATE_OOEFIN_INVOICE_APPROVED")
              (add-event (mk-stripe-charge-req
                           (sorted-map
                             "customer_id" "mock_customer_id"
                             "amount"      2000
                             "currency"    "usd"
                             "source_id"   "mock_source_id"
                             "description" "Test Stripe charge"))))

             ((equal? state "CLAIM_STATE_OOEFIN_INVOICE_TRIGGERED")
              ; done
             )))
         (ret-save)])
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

(defun trigger-claim (claim-id resp)
  (trigger-connector-object claims claim-id resp))

(defun create-claim ()
  ; create claim allocates storage for a new claim, sets the ID and state.
  (new-connector-object claims))
