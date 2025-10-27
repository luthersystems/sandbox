(in-package 'sandbox)

(use-package 'connector)

;; ======================
;;  S3 request builders
;; ======================

(defun mk-s3-req (op args)
  ;; Wrap args inside an "args" map for mk-connector-req
  (mk-connector-req
    (sorted-map
      "kind" "KIND_AWS_S3"
      "operation" op
      "args" args)))

(defun parse-s3-resp (resp)
  (parse-generic-resp resp))

(defun mk-s3-upload-req (file-content file-name bucket-name)
  (mk-s3-req "put_object"
    (sorted-map
      "body" (json:dump-string file-content)
      "key" file-name
      "bucket_name" bucket-name)))

(defun mk-s3-get-req (file-name bucket-name)
  (mk-s3-req "get_object"
    (sorted-map
      "key" file-name
      "bucket_name" bucket-name)))


(defun mk-s3-del-req (file-name bucket-name)
  (mk-s3-req "delete_object"
    (sorted-map
      "key" file-name
      "bucket_name" bucket-name)))


;; ======================
;;  High-level transitions
;; ======================


(defun mk-s3-upload-event (invoice file-content file-name bucket-name)
  ;; Build an upload transition (put_object + event)
  (build-s3-event
    invoice
    (mk-s3-upload-req file-content file-name bucket-name)
    "upload file"))

(defun mk-s3-get-event (invoice)
  ;; Build a get transition (get_object + event).
  (let* ([file-name   (get invoice "file_name")]
         [bucket-name (get invoice "bucket_name")])
    (build-s3-event
      invoice
      (mk-s3-get-req file-name bucket-name)
      "get file")))

(defun mk-s3-del-event (invoice)
  ;; Build a delete transition (del_object + event).
  (let* ([file-name   (get invoice "file_name")]
         [bucket-name (get invoice "bucket_name")])
    (build-s3-event
      invoice
      (mk-s3-del-req file-name bucket-name)
      "delete file")))