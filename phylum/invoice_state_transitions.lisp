
;; -----------------------------------------------------------------------------
;; Example state handlers (invoice)
;; -----------------------------------------------------------------------------

;; INVOICE_STATE_NEW -> INVOICE_STATE_S3_UPLOADED
(defun invoice-new-state-handler ()
  (labels
    ;; parse: validate + extract fields for this step (not persisted unless staged)
    ([parse (resp entity)
      (let* ([file-content (get resp "file_content")]
             [file-name    (get resp "file_name")]
             [bucket-name  (get resp "bucket_name")])
        (sorted-map
          "file_content" file-content
          "file_name"    file-name
          "bucket_name"  bucket-name))]

     ;; ephemeral: keep raw file content until we see S3 upload succeed
     [stage-ephemeral (entity parsed accessors)
      (vector
        (sorted-map :key "file_content"
                    :value (get parsed "file_content")
                    :drop-state "INVOICE_STATE_S3_UPLOADED"))]

     ;; durable: persist metadata
     [stage-durable (entity parsed accessors)
      (sorted-map
        "file_name"   (get parsed "file_name")
        "bucket_name" (get parsed "bucket_name"))]

     ;; events:  S3 upload using parsed content + durable metadata
     [create-events (entity parsed accessors)
      (let* ([file-name   (get entity "file_name")]
             [bucket-name (get entity "bucket_name")]
             [content     (get parsed "file_content")])
        (vector
          (mk-s3-upload-event entity content file-name bucket-name)))])
    (mk-state-handler
      :next            "INVOICE_STATE_S3_UPLOADED"
      :parse           parse
      :stage-ephemeral stage-ephemeral
      :stage-durable   stage-durable
      :create-events   create-events)))


;; INVOICE_STATE_S3_UPLOADED -> INVOICE_STATE_S3_RETRIEVED
(defun invoice-s3-uploaded-state-handler ()
  (labels
    ;; parse S3 upload response (domain helper)
    ([parse (resp entity)
      (parse-s3-resp resp)]

     ;; no new ephemerals
     [stage-ephemeral (entity parsed accessors) ()]

     ;; no durable changes
     [stage-durable (entity parsed accessors) ()]

     ;; events: request S3 GET; demonstrate ephem-get before purge
     [create-events (entity parsed accessors)
      (let* ([entity-id    (get entity "invoice_id")]
             [get-ephem    (get accessors :get-ephem)]
             [file-content (get-ephem "file_content")])
        (vector (mk-s3-get-event entity)))])
  (mk-state-handler
    :next            "INVOICE_STATE_S3_RETRIEVED"
    :parse           parse
    :stage-ephemeral stage-ephemeral
    :stage-durable   stage-durable
    :create-events   create-events)))


;; INVOICE_STATE_S3_RETRIEVED -> INVOICE_STATE_MYSQL_VALIDATED
(defun invoice-s3-retrieved-state-handler ()
  (labels
    ;; parse GET response (string/bytes → string)
    ([parse (resp entity)
      (parse-s3-resp resp)]

     ;; keep raw S3 body temporarily, drop once MySQL update succeeds
     [stage-ephemeral (entity parsed accessors) ()]

     ;; durable: extract invoice_number
     [stage-durable (entity parsed accessors)
      (let* ([j (json:load-string parsed)]
             [inv-num (get j "invoice_number")])
        (sorted-map "invoice_number" inv-num))]

     ;; events: validate invoice in MySQL
     [create-events (entity parsed accessors)
      (vector
        (mk-mysql-select-invoices-by-numbers-event
          entity
          (list (get entity "invoice_number"))))])
  (mk-state-handler
    :next            "INVOICE_STATE_MYSQL_VALIDATED"
    :parse           parse
    :stage-ephemeral stage-ephemeral
    :stage-durable   stage-durable
    :create-events   create-events)))


;; INVOICE_STATE_MYSQL_VALIDATED -> INVOICE_STATE_MYSQL_UPDATED
(defun invoice-mysql-validated-state-handler ()
  (labels
    ;; parse MySQL SELECT response
    ([parse (resp entity)
      (parse-mysql-select resp)]

     ;; no ephemerals here
     [stage-ephemeral (entity parsed accessors) ()]

     ;; no durable changes
     [stage-durable (entity parsed accessors) ()]

     ;; events: update invoice status in MySQL
     [create-events (entity parsed accessors)
      (vector
        (mk-mysql-update-invoice-status-event
          entity
          (list (get entity "invoice_number"))))])
  (mk-state-handler
    :next            "INVOICE_STATE_MYSQL_UPDATED"
    :parse           parse
    :stage-ephemeral stage-ephemeral
    :stage-durable   stage-durable
    :create-events   create-events)))


;; INVOICE_STATE_MYSQL_UPDATED -> INVOICE_STATE_DONE
(defun invoice-mysql-updated-state-handler ()
  (labels
    ;; parse MySQL UPDATE/EXEC response
    ([parse (resp entity)
      (parse-mysql-exec resp)]

     ;; final cleanups if any (none here)
     [stage-ephemeral (entity parsed accessors) ()]

     ;; no durable changes
     [stage-durable (entity parsed accessors) ()]

     ;; no further events
     [create-events (entity parsed accessors)
      (vector)])
  (mk-state-handler
    :next            "INVOICE_STATE_DONE"
    :parse           parse
    :stage-ephemeral stage-ephemeral
    :stage-durable   stage-durable
    :create-events   create-events)))
