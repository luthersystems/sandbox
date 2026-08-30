(in-package 'sandbox)

(use-package 'connector)

; -----------------------------------------------------------------------------
; Create the state machine
; -----------------------------------------------------------------------------

(set 'state-spec
  (sorted-map
    "INVOICE_STATE_NEW"             (invoice-new-state-handler)
    "INVOICE_STATE_S3_UPLOADED"     (invoice-s3-uploaded-state-handler)
    "INVOICE_STATE_S3_RETRIEVED"    (invoice-s3-retrieved-state-handler)
    "INVOICE_STATE_MYSQL_VALIDATED" (invoice-mysql-validated-state-handler)
    "INVOICE_STATE_MYSQL_UPDATED"   (invoice-mysql-updated-state-handler)))

; -----------------------------------------------------------------------------
;; Build the invoices connector from the generic factory
; -----------------------------------------------------------------------------

(set 'invoice-manager
     (singleton (mk-entity-manager
                  "invoice"
                  "invoice_id"
                  "INVOICE_STATE_NEW"
                  state-spec)))

(register-connector-factory invoice-manager)

;; Helper to create a new invoice connector object via factory
(defun create-invoice ()
  (new-connector-object invoice-manager))