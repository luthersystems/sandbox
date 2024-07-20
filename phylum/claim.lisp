(in-package 'sandbox)

;; TODO: set MSPID on request
;; TODO move methods into single class

;; mk-claim implements handler
(defun mk-claim (claim)
  (unless claim (error 'missing-claim "missing claim"))
  (labels
    ;; TODO: handle returns a transition (new obj to save, events)
    ;; TODO: implement claim state machine
    ([handle
       (resp)
       (cc:infof resp "got connector resp")])

    (lambda (op &rest args)
        (cond ((equal? op 'resp) (apply handle args))
              (:else (error 'unknown-operation op))))))

;; mk-claims implements factory
(defun mk-claims ()
  (labels
    ([name () "claim"]

     [mk-claim-storage-key
       (claim-id)
       (join-index-cols "sandbox" "claim"  claim-id)]

     [storage-put-claim
       (claim)
       (sidedb:put (mk-claim-storage-key (get claim "claim_id")) claim)]

     [storage-get-claim
       (claim-id)
       (thread-first
         (mk-claim-storage-key claim-id)
         (sidedb:get)
         (mk-claim))]

     [storage-del-claim
       (claim-id)
       (sidedb:del (mk-claim-storage-key claim-id))])

    (lambda (op &rest args)
        (cond ((equal? op 'name) (apply name args))
              ((equal? op 'get) (apply storage-get-claim args))
              ((equal? op 'del) (apply storage-del-claim args))
              ((equal? op 'put) (apply storage-put-claim args))
              (:else (error 'unknown-operation op))))))

(set 'claims (singleton mk-claims))

(register-connector-factory claims)
