;; Copyright © 2025 Luther Systems, Ltd. All right reserved.
;; ----------------------------------------------------------------------------
;; The claim process, written as a durable flow (defflow).
;;
;; A claim waits for the claimant's details, then calls seven systems in a
;; fixed order through the Connector Hub. Each call happens in its own
;; transaction, so the process can wait minutes or days for a reply.
;;
;; Why defflow, and not a hand-written state machine: the order of the steps
;; is the order of the code below. Substrate stores the claim between
;; transactions, sends each request, routes each reply back to the claim,
;; and makes the endpoints. Before defflow this file kept a table of states,
;; a table of events per state, a `cond` on the current state and its own
;; storage code (luthersystems/sandbox#162).
;;
;; See "Durable flows (defflow)" in the substrate API reference.
;; ----------------------------------------------------------------------------
(in-package 'sandbox)

(use-package 'connector)
(use-package 'defflow)

;; claim-event wraps a connector request for the system sys.
;;
;; key is the step key of the await that sends the event, (flow:step-key
;; ctx). It is the same for every retry and replay of one step, so a vendor
;; that reads it (a payment provider, for example) does the work once even
;; when the Connector Hub sends the request again. The runtime stamps it on
;; the event too; putting it in the event here makes that explicit, and the
;; flow-event-without-key lint checks for it.
;;
;; Every request goes to Org1MSP because a flow has one :connector-msp: the
;; organization whose Connector Hub answers. The sandbox runs all of its
;; connectors under that one organization. In a network where each
;; connector belongs to a different organization, split the process into
;; one flow per organization and join them with await-flow.
(defun claim-event (sys req key)
  (assoc (mk-event sys req :msp "Org1MSP") "idempotency_key" key))

;; claimant-schema is the JSON schema of the claimant input. Substrate checks
;; it before the input reaches the flow and refuses a bad input with a
;; "schema" error that commits nothing. It requires every field the
;; identity check reads (mk-equifax-req needs forename, surname and dob),
;; so a bad claimant is refused at the API, not failed inside the flow.
(set 'claimant-schema
     (json:dump-string
       (sorted-map "type" "object"
                   "required" (vector "forename" "surname" "dob" "nationality")
                   "properties" (sorted-map
                                  "forename" (sorted-map "type" "string" "minLength" 1)
                                  "surname" (sorted-map "type" "string" "minLength" 1)
                                  "dob" (sorted-map "type" "string" "minLength" 1)
                                  "nationality" (sorted-map "type" "string"
                                                            "pattern" "^NATIONALITY_[A-Z]+$")))))

;; claim is the claim process. details is the body of the create_claim
;; request: date_of_accident, damage_amount and claim_reason.
;;
;; The :endpoints option keeps the endpoint names of the earlier API, so the
;; oracle still calls create_claim, add_claimant and get_claim.
;;
;; A connector error at any step fails the run, with the error as the
;; reason. That is the behaviour of the old state machine, which raised an
;; unexpected exception on an error reply.
(defflow claim (ctx details)
  (:connector-msp "Org1MSP"
                  :start-from ("Org1MSP")
                  :admin-from ("Org1MSP")
                  :connector-timeout "1h"
                  :expose ("details" "claimant")
                  :endpoints (:start "create_claim" :get "get_claim" claimant "add_claimant"))
  (let* ([claimant (await-input 'claimant :from ("Org1MSP") :schema claimant-schema)]
         ;; Equifax expects "GB", not the API's enum name "NATIONALITY_GB".
         [person (assoc claimant "nationality"
                        (string:trim-prefix (get claimant "nationality") "NATIONALITY_"))])
    (await-connector 'verify-identity
                     (claim-event "EQUIFAX_ID_VERIFY"
                                  (mk-equifax-req person)
                                  (flow:step-key ctx)))
    (await-connector 'collect-policy
                     (claim-event "CAMUNDA_WORKFLOW"
                                  (mk-camunda-start-req "a1" (sorted-map "x" "fnord"))
                                  (flow:step-key ctx)))
    (await-connector 'verify-policy
                     (claim-event "POSTGRES_CLAIMS_DB"
                                  (mk-psql-req "SELECT 1")
                                  (flow:step-key ctx)))
    (await-connector 'issue-invoice
                     (claim-event "INVOICE_NINJA"
                                  (mk-invoice-ninja-email-req
                                    (sorted-map "invoice_id" "mock_invoice_id"))
                                  (flow:step-key ctx)))
    (await-connector 'approve-invoice
                     (claim-event "CAMUNDA_TASKLIST"
                                  (mk-camunda-inspect-req "a1" "true")
                                  (flow:step-key ctx)))
    (await-connector 'email-invoice
                     (claim-event "EMAIL"
                                  (mk-email-req "sam.wood@luthersystems.com"
                                                "Test Email"
                                                "Hello, this is a test email")
                                  (flow:step-key ctx)))
    ;; A payment gets a longer deadline than the other steps. When a
    ;; deadline passes, the outcome of the request is unknown: the charge may
    ;; have gone through. Here the claim fails and an operator checks it. A
    ;; production flow would add :on-error and ask the payment provider for
    ;; the charge's status with the same step key, (flow:step-key ctx 'pay).
    (await-connector 'pay
                     (claim-event "STRIPE_PAYMENT"
                                  (mk-stripe-charge-req
                                    (sorted-map "customer_id" "mock_customer_id"
                                                "amount"      2000
                                                "currency"    "usd"
                                                "source_id"   "mock_source_id"
                                                "description" "Test Stripe charge"))
                                  (flow:step-key ctx))
                     :timeout "24h")
    ;; The result is the finished claim. It reads details and claimant, so
    ;; both stay saved at every wait and get_claim can show them (:expose).
    (sorted-map "details"  details
                "claimant" claimant
                "status"   "STATUS_PAID")))
