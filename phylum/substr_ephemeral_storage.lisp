(in-package 'sandbox)
(use-package 'connector)

;; ---------- helpers for safe prefix handling ----------
(defun _prefix-range (prefix)
  ;; Return [start end] range for scanning a prefixed keyspace
  (vector prefix (format-string "{}\uffff" prefix)))

(defun ephem-index-key (entity-name entity-id drop-state)
  (join-index-cols "sandbox" entity-name "ephem" "index" entity-id drop-state))

;; ---------- Ephemeral bucket/router keys ----------
(defun ephem-bucket-key (entity-name entity-id drop-state)
  ;; sandbox:<entity>:ephem:bucket:<entityId>:<dropState>
  (join-index-cols "sandbox" entity-name "ephem" "bucket" entity-id drop-state))

(defun ephem-router-key (entity-name entity-id ekey)
  ;; sandbox:<entity>:ephem:router:<entityId>:<eKey>
  (join-index-cols "sandbox" entity-name "ephem" "router" entity-id ekey))

(defun ephem-router-prefix (entity-name entity-id)
  ;; prefix for scanning all router entries for an entity
  (join-index-cols "sandbox" entity-name "ephem" "router" entity-id))

;; Read by key: router -> bucket -> value
(defun ephem-get (entity-name entity-id ekey)
  (let* ([ds (sidedb:get (ephem-router-key entity-name entity-id ekey))])
    (when ds
      (let* ([bkey   (ephem-bucket-key entity-name entity-id ds)]
             [bucket (sidedb:get bkey)])
        (and bucket (get bucket ekey))))))

;; Persist a vector of intents returned by stage-ephemeral
;; Each intent: {:key <string> :value <any> [:drop-state <string>]}
(defun ephem-persist-staged! (entity-name entity-id default-drop-state intents)
  (map ()
    (lambda (it)
      (let* ([ekey (get it :key)]
             [eval (get it :value)]
             [ds   (or (get it :drop-state) default-drop-state)]
             [bkey (ephem-bucket-key entity-name entity-id ds)]
             [bucket (or (sidedb:get bkey) (sorted-map))])

        ;; Validate the drop-state before persisting
        (validate-state-exists! ds)

        ;; write bucket first
        (assoc! bucket ekey eval)
        (sidedb:put bkey bucket)

        ;; write router
        (sidedb:put (ephem-router-key entity-name entity-id ekey) ds)

        ;; append ekey to index list
        (let* ([ikey  (ephem-index-key entity-name entity-id ds)]
       [index (or (sidedb:get ikey) (vector))])
  (append! index ekey)            ; in-place append
  (sidedb:put ikey index))))
    intents)
  (sorted-map "ok" true))

;; Purge everything whose drop-state == <drop-state>
;;  - delete the whole bucket
;;  - clean router entries whose VALUE equals <drop-state>
(defun ephem-purge-for-state! (entity-name entity-id drop-state)
  (let* ([bkey (ephem-bucket-key entity-name entity-id drop-state)]
         [ikey (ephem-index-key entity-name entity-id drop-state)]
         [ekeys (or (sidedb:get ikey) (vector))])

    ;; purge all router entries
    (map ()
      (lambda (ek)
        (sidedb:purge (ephem-router-key entity-name entity-id ek)))
      ekeys)

    ;; purge bucket + index
    (sidedb:purge bkey)
    (sidedb:purge ikey))

  (sorted-map "ok" true))
  
  (defun validate-state-exists! (state)
  (when (or (nil? state) (nil? (lookup-state-spec state)))
    (set-exception-unexpected
      (format-string "invalid or missing state name: {}" state))))
