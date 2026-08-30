;; camunda_transitions.lisp
;; ------------------------
;; Defines high-level transition builders for Camunda connector.
;; Uses mk-camunda-start-req and wraps into standard transition events
;; via build-camunda-event (from invoice_transition.lisp).

(in-package 'sandbox)

(use-package 'connector)

(defun mk-camunda-start-transition (invoice pdk &optional vars-map)
  ;; Start a Camunda workflow and emit an event.
  (build-camunda-event
    invoice
    (mk-camunda-start-req pdk vars-map)
    "start workflow"))