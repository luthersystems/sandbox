(in-package 'sandbox)

(use-package 'connector)

(defendpoint "upload_invoice" (req)
  (let* ([fc           (get req "file_content")]
         [file-content (or (if (string? fc) fc (json:dump-string fc))
                           (set-exception-business "missing file_content"))]
         [file-name    (or (get req "location")
                           (set-exception-business "missing location"))]
         [bucket-name  (or (get req "bucket_name")
                           (set-exception-business "missing bucket_name"))]

         ;; Build base invoice doc (durable state)
         [invoice     (new-connector-object invoice-manager)]
         [invoice-id  (get invoice "invoice_id")]
         [invoice     (assoc! invoice "state" "INVOICE_STATE_NEW")]

         ;; Emulate ConnectorHub response payload (what parse expects)
         [chresp      (sorted-map
                        "file_content" file-content
                        "file_name"    file-name
                        "bucket_name"  bucket-name)]

         ;; Run one state step (parse → stage-ephemeral → stage-durable → transition)
         [step (run-state-step "invoice" "invoice_id" invoice chresp)]
         [inv1        (get step "put")]
         [events      (get step "events")])

    ;; Persist updated durable doc and trigger connector events
    (invoice-manager 'put inv1)
    (trigger-connector-object invoice-manager invoice-id
      (sorted-map "put" inv1 "events" events))

    (route-success
      (sorted-map
        "invoice_id" invoice-id
        "state"      (get inv1 "state")))))

(defun trigger-invoice (invoice-id resp)
  (trigger-connector-object invoice-manager invoice-id resp))