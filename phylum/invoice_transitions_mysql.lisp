(in-package 'sandbox)

(use-package 'connector)

;; ======================
;;  MySQL request builders
;; ======================

(defun mk-mysql-req (sql)
  ;; Wrap raw SQL into connectorhub request.
  (mk-connector-req
    (sorted-map
      "kind" "KIND_MYSQL"
      "operation" "mysql_query"
      "args" (sorted-map "sql" sql))))


(defun parse-mysql-resp (resp)
  (parse-generic-resp resp))

(defun mk-mysql-insert-pos-basic-req ()
  (mk-mysql-req
    "INSERT INTO purchase_orders (po_number, vendor_id, amount, status) VALUES ('PO1004', 1, 5000.00, 'OPEN'), ('PO2005', 2, 7500.00, 'OPEN');"))

(defun mk-mysql-select-docs-req (ids)
  ;; Build a SELECT for multiple invoice_ids using IN.
  ; (let* ((id-str (string-join (map string ids) ",")))
    (mk-mysql-req "SELECT * FROM invoices WHERE invoice_id IN (1,2)"))

(defun mk-mysql-delete-doc-req (invoice-id filename)
  ;; Build a DELETE statement for a specific doc by invoice + filename.
  (mk-mysql-req
    (format-string
      "DELETE FROM invoices WHERE invoice_id='{}' AND filename='{}'"
      invoice-id filename)))


;; ======================
;;  High-level transitions
;; ======================

(defun mk-mysql-insert-doc-transition (invoice invoice-id filename bucket)
  ;; Insert a new document record and emit an event.
  (build-mysql-event
    invoice
    (mk-mysql-insert-pos-basic-req)
    "insert doc"))


(defun mk-mysql-select-docs-transition (invoice invoice-ids)
  ;; Query documents for an invoice and emit an event.
  (build-mysql-event
    invoice
    (mk-mysql-select-docs-req invoice-ids)
    "select docs"))


(defun mk-mysql-delete-doc-transition (invoice invoice-id filename)
  ;; Delete a document record and emit an event.
  (build-mysql-event
    invoice
    (mk-mysql-delete-doc-req invoice-id filename)
    "delete doc"))

(defun mk-mysql-insert-pos-basic-transition (invoice)
  (build-mysql-event
    invoice
    (mk-mysql-insert-pos-basic-req)
    "basic insert"))

(defun parse-mysql-exec (resp)
  (let* ([parsed (parse-mysql-resp resp)])
    (cc:infof (sorted-map "parsed-response" parsed) "parse-mysql-exec")
    "ok"))

(defun parse-mysql-select (resp)
  (let* ([parsed (parse-mysql-resp resp)]
         [rows   (cond
                   ((vector? parsed) parsed)
                   ((sorted-map? parsed) (vector parsed))
                   (:else (vector)))])
    rows))

(defun extract-invoice-statuses (rows)
  (when (vector? rows)
    (let* ([fn (lambda (row)
                 (format-string "{}:{}"
                                (get row "invoice_number")
                                (get row "status")))])
      (map 'vector fn rows))))

(defun mk-mysql-select-invoices-by-numbers-req (numbers)
  ;; Build a SELECT for multiple invoice_numbers using IN.
  (let* ([quoted (map 'list (lambda (n) (format-string "'{}'" n)) numbers)]
         [joined (string:join quoted ",")])
    (mk-mysql-req
      (format-string
        "SELECT * FROM invoices WHERE invoice_number IN ({})"
        joined))))

(defun mk-mysql-update-invoice-status-req (numbers)
  ;; Update invoices matching invoice_numbers from PENDING to VERIFIED.
  (let* ([quoted (map 'list (lambda (n) (format-string "'{}'" n)) numbers)]
         [joined (string:join quoted ",")])
    (mk-mysql-req
      (format-string "UPDATE invoices SET status = 'VERIFIED' WHERE invoice_number IN ({}) AND status = 'PENDING'"
        joined))))

(defun mk-mysql-select-invoices-by-numbers-event (invoice numbers)
  (build-mysql-event
    invoice
    (mk-mysql-select-invoices-by-numbers-req numbers)
    "select invoices by numbers"))

(defun mk-mysql-update-invoice-status-event (invoice numbers)
  (build-mysql-event
    invoice
    (mk-mysql-update-invoice-status-req numbers)
    "update invoice statuses"))