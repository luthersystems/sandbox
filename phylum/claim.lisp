;; Copyright © 2025 Luther Systems, Ltd. All right reserved.
;; ----------------------------------------------------------------------------
;; Core business logic for claim processing.
;; Implements the state machine, connector event generation, and handlers for
;; individual claim objects.
;;
;; Defines:
;; - A claim lifecycle as a state transition chain
;; - A mapping of states to system-triggered events
;; - The `mk-claim` function, which returns a stateful handler for a claim
;; - The `claims` connector factory to manage persisted claim objects
;; ----------------------------------------------------------------------------
(in-package 'sandbox)

(use-package 'connector)

;; make-state-chain builds a linear map of state transitions from first to last.
;; Used to model the claim lifecycle as a state machine.
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

;; state-transitions defines the allowed sequence of states for a claim.
;; Used by `next-state` in mk-claim to determine the next processing step.
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

;; sys-msp-map maps system names to the MSP ID responsible for handling
;; connector events. These must match the connectorhub.yaml definitions.
(set 'sys-msp-map
  ;; map from system names to responsible connector MSP IDs
  ;; TODO: for now it's all 1 connector, but in final version each connector
  ;; is run by a separate org (participant).
  (sorted-map
    "CLAIMS_PORTAL_UI"   "Org1MSP"
    "EQUIFAX_ID_VERIFY"  "Org1MSP"
    "POSTGRES_CLAIMS_DB" "Org1MSP"
    "CAMUNDA_WORKFLOW"   "Org1MSP"
    "INVOICE_NINJA"      "Org1MSP"
    "CAMUNDA_TASKLIST"   "Org1MSP"
    "EMAIL"              "Org1MSP"
    "STRIPE_PAYMENT"     "Org1MSP"))

;; event-desc-record returns metadata describing the system and action to trigger.
;; Used when building connector events for a specific state.
(defun event-desc-record (sys eng)
  (denil-map (sorted-map "msp" (default (get sys-msp-map sys) "Org1MSP")
                         "sys" sys
                         "eng" eng)))

;; claims-state-event-desc maps claim states to connector event metadata.
;; Each state may trigger a system action (e.g., ID check, invoice).
(set 'claims-state-event-desc
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

;; mk-verify-policy-req creates a request to verify a policy
;; For now, just returns a simple health check query
(defun mk-verify-policy-req (policy-id)
  (mk-psql-req "SELECT 1"))


;; mk-claim returns a stateful handler for a claim.
;; Supports operations:
;; - 'init: initialize the claim in a NEW state
;; - 'handle: process a connector response and advance state
;; - 'data: retrieve claim data
;;
;; Internally tracks raised events and manages state transitions.
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

       ;; add-event appends a connector event to the current claim.
       ;; Builds the full event map using the current state and the provided
       ;; request (`event-req`), including metadata like system, msp, and engine.
       ;; If `event-req` is nil, no event is added.
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

       ;; init initializes a new claim with the initial state.
       ;; Should be called only once on a newly created claim object.
       ;; Returns the result map with updated claim and any initial events.
       [init ()
         (assoc! claim "state" "CLAIM_STATE_NEW")
         (ret-save)]
       
       ;; data returns the current claim data map.
       ;; Used by external callers (e.g. endpoints) to inspect claim state.
       [data () claim]

       ;; handle processes the response from the previous connector event.
       ;; It:
       ;; - Determines the current claim state
       ;; - Interprets the connector response (resp)
       ;; - Optionally triggers the next event based on state logic
       ;; - Advances the state machine
       ;; Returns updated claim data and any new events to raise.
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
              ;; equifax event does not have NATIONALITY prefix
              (let* ([nationality (string:trim-left (get resp "nationality") "NATIONALITY_")]
                     [person (assoc resp "nationality" nationality)]) 
                (add-event (mk-equifax-req (trace person "equifax")))))

             ((equal? state "CLAIM_STATE_LOECLAIM_ID_VERIFIED")
              (add-event (mk-camunda-start-req "a1" (sorted-map "x" "fnord"))))

             ((equal? state "CLAIM_STATE_OOECLAIM_REVIEWED") 
              (add-event (mk-verify-policy-req (get resp "policy_id"))))

             ((equal? state "CLAIM_STATE_OOECLAIM_VALIDATED")
              (trace resp "ooe claim validated")
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

;; mk-claims returns a connector factory object that manages persisted claims.
;;
;; Claim objects are stored in sidedb — a persistent key-value store
;; provided by the Luther Platform. Sidedb is suitable for storing private
;; or sensitive data and supports fine-grained access control between participants.
;;
;; This factory supports:
;; - 'name: unique name for the factory
;; - 'new:  create and store a new claim
;; - 'get:  retrieve a claim by ID
;; - 'put:  update a stored claim
;; - 'del:  delete a claim from storage
(defun mk-claims ()
  (labels
    ([name () "claim"]

     ;; mk-claim-storage-key: build namespaced key for claim storage
     [mk-claim-storage-key (claim-id)
       (join-index-cols "sandbox" "claim"  claim-id)]

     ;; storage-put-claim: save claim to sidedb
     [storage-put-claim (claim)
       (sidedb:put (mk-claim-storage-key (get claim "claim_id")) claim)]

     ;; new-claim creates and initializes a new claim object.
     ;; Generates a unique claim ID and sets the initial state.
     ;; Returns the result of the initial state transition (usually includes events).
     [new-claim () 
       (let* ([claim-data (sorted-map "claim_id" (mk-uuid))]
              [claim (mk-claim claim-data)]) 
         (claim 'init))]

     ;; storage-get-claim: load claim from sidedb by ID
     [storage-get-claim (claim-id)
       (let* ([key (mk-claim-storage-key claim-id)]
              [claim-data (sidedb:get key)])
         (when claim-data (mk-claim claim-data)))]
 
     ;; storage-del-claim: remove claim from sidedb
     [storage-del-claim (claim-id)
       (sidedb:del (mk-claim-storage-key claim-id))])

    (lambda (op &rest args)
        (cond ((equal? op 'name) (apply name args))
              ((equal? op 'new) (apply new-claim args))
              ((equal? op 'get) (apply storage-get-claim args))
              ((equal? op 'del) (apply storage-del-claim args))
              ((equal? op 'put) (apply storage-put-claim args))
              (:else (error 'unknown-operation op))))))

;; Initialize the singleton instance of the claims connector factory.
;; This provides a shared object for creating, storing, and retrieving claims.
;;
;; The connector factory must be a singleton to ensure consistent access
;; to state and routing across phylum calls.
(set 'claims (singleton mk-claims))

;; Register the claims connector factory with the connector hub.
;; This allows the Luther Platform to invoke the correct logic when
;; connector events are routed to this phylum.
;;
;; The name exposed is defined by `(claims 'name)` — must be globally unique.
(register-connector-factory claims)

;; trigger-claim advances a stored claim by injecting a connector response.
;; Used during API calls or connector callbacks.
(defun trigger-claim (claim-id resp)
  (trigger-connector-object claims claim-id resp))

;; create-claim initializes and persists a new claim object.
;; Used at process start (e.g., in `create_claim` endpoint).
(defun create-claim ()
  ; create claim allocates storage for a new claim, sets the ID and state.
  (new-connector-object claims))
