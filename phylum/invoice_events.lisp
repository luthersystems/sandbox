;; invoice_transition.lisp
;; -----------------------
;; Core transition builder utilities for invoice state machines.
;;
;; Defines `build-event`, a generic helper that wraps an invoice object
;; and a connector request/response (`resp`) into a transition map:
;;
;;   {
;;     "put":    <updated invoice>
;;     "events": [<connector event>]
;;   }
;;
;; Each event includes:
;;   - "oid": invoice_id
;;   - "key": unique event key (UUID)
;;   - "pdc": "private"   (data collection)
;;   - "msp": "Org1MSP"   (organization identity)
;;   - "sys": connector system name (e.g. "AWSS3", "MYSQL", "CAMUNDA")
;;   - "eng": human-readable action (e.g. "upload file", "insert doc")
;;   - "req": connector request payload
;;
;; System-specific wrappers (build-s3-event, build-mysql-event,
;; build-camunda-event) are provided for convenience and consistency.
;;
;; New connectors should follow the same pattern:
;;   (defun build-<system>-transition (invoice resp action)
;;     (build-event invoice resp action "<SYSTEM-NAME>"))


(in-package 'sandbox)

(use-package 'connector)

;; Build a generic connector event with common metadata.
(defun build-event (invoice resp action sys-name)
  (sorted-map
    "oid" (get invoice "invoice_id")
    "key" (mk-uuid)
    "pdc" "private"
    "msp" "Org1MSP"
    "sys" sys-name
    "eng" action
    "req" resp))

;; Build an event targeting AWS S3
(defun build-s3-event (invoice resp action)
  (build-event invoice resp action "AWSS3"))

;; Build an event targeting MYSQL
(defun build-mysql-event (invoice resp action)
  (build-event invoice resp action "MYSQL"))

;; Build an event targeting Camunda workflow
(defun build-camunda-event (invoice resp action)
  (build-event invoice resp action "CAMUNDA"))
