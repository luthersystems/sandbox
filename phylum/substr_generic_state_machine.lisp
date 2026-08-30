(in-package 'sandbox)
(use-package 'connector)

;; -----------------------------------------------------------------------------
;; Sandbox Entity State Machine Framework
;; -----------------------------------------------------------------------------
;;
;; Core runtime + ephemeral storage layer for declarative state machines.
;;
;; Per-step flow:
;;   parse(resp, entity)
;;   → stage-ephemeral(entity, parsed)   ; vector of ephemeral intents
;;   → stage-durable(entity, parsed)     ; partial or full durable updates
;;   → create-events(entity, parsed)     ; emit connector events (no mutation)
;;   → persist ephemerals (default drop-state = :next)
;;   → advance durable entity state to :next
;;   → purge ephemerals scheduled for the state we just entered
;;
;; Ephemeral storage in SideDB:
;;   sandbox:<entity>:ephem:bucket:<entityId>:<dropState>  ; value buckets (map key→value)
;;   sandbox:<entity>:ephem:router:<entityId>:<key>        ; router key → dropState
;;   sandbox:<entity>:ephem:index:<entityId>:<dropState>   ; list of keys for drop-state
;;
;; Each ephemeral intent is a map:
;;   { :key <string> :value <any> :drop-state <string-STATE> }
;; Data survives until the entity enters that drop-state; then it's purged.
;;
;; State specs (registered in global `state-spec`) are built with (mk-state-handler)
;; and define: :parse, :stage-ephemeral, :stage-durable, :create-events, and :next.
;; -----------------------------------------------------------------------------


;; -----------------------------------------------------------------------------
;; Entity Manager
;; -----------------------------------------------------------------------------
;; Builds a manager for a domain entity to create/load/save/delete instances.
;;
;; API (returned closure):
;;   ('name)                 -> entity-name
;;   ('new)                  -> transition map { "put": entity, "events": [...] }
;;   ('get  <id>)            -> entity-instance | ()
;;   ('put  <entity-map>)    -> ()
;;   ('del  <id>)            -> ()
;;
(defun mk-entity-manager (entity-name entity-key initial-state states)
  (lambda ()
    (labels
      ([name () entity-name]

       ;; Key in PDC: "sandbox:<entity-name>:<entity-id>"
       [mk-storage-key (entity-id)
         (join-index-cols "sandbox" entity-name entity-id)]

       ;; persistence (PDC)
       [storage-put (entity-doc)
         (sidedb:put (mk-storage-key (get entity-doc entity-key)) entity-doc)]

       [storage-get (entity-id)
         (let* ([key (mk-storage-key entity-id)]
                [entity-doc (sidedb:get key)])
           (when entity-doc
             (mk-entity-instance entity-name entity-key initial-state states entity-doc)))]

       [storage-del (entity-id)
         (sidedb:purge (mk-storage-key entity-id))]

       ;; constructor
       [new-instance ()
         (let* ([doc      (sorted-map entity-key (mk-uuid))]
                [instance (mk-entity-instance entity-name entity-key initial-state states doc)])
           (instance 'init))]
           
      [ephemeral-get (entity-id ekey)
         (ephem-get entity-name entity-id ekey)])

      (lambda (op &rest args)
        (cond ((equal? op 'name) (apply name args))
              ((equal? op 'new)  (apply new-instance args))
              ((equal? op 'get)  (apply storage-get args))
              ((equal? op 'del)  (apply storage-del args))
              ((equal? op 'put)  (apply storage-put args))

              ((equal? op 'ephem-get)           (apply ephemeral-get args))
              (:else (error 'unknown-operation op)))))))


;; -----------------------------------------------------------------------------
;; Entity Instance
;; -----------------------------------------------------------------------------
;; Instance with:
;;   ('init)   -> { "put": entity, "events": [] }
;;   ('handle) -> advance one step given a connector response
;;
(defun mk-entity-instance (entity-name entity-key initial-state states entity)
  (labels
    ([init ()
       (when (nil? (get entity entity-key)) (assoc! entity entity-key (mk-uuid)))
       (when (nil? (get entity "state"))     (assoc! entity "state" initial-state))
       (sorted-map "put" entity "events" (vector))]

     [handle (resp)
       (run-state-step entity-name entity-key entity resp)])

    (lambda (op &rest args)
      (cond ((equal? op 'init)   (apply init args))
            ((equal? op 'handle) (apply handle args))
            (:else (error 'unknown-entity-op op))))))


;; -----------------------------------------------------------------------------
;; Step runner (no process-local ephemeral; uses staged ephemerals API)
;; -----------------------------------------------------------------------------
(defun run-state-step (entity-name entity-key instance resp)
  (let* ([state   (get instance "state")]
         [spec    (lookup-state-spec state)]

         ;; 1) parse
         [parsed  ((spec-parse spec) resp instance)]

         ;; Look ahead to next state (constant per spec)
         [next-state (spec-next spec)]

          ;; Prepare ctx for handlers that need ephems/id/state/next
         [entity-id0 (get instance entity-key)]
         [accessors (sorted-map
                :state     state
                :next      next-state
                :entity-id entity-id0
                :get-ephem (lambda (k) (ephem-get entity-name entity-id0 k)))]

          ;; 2) stage-ephemeral (pure; can use ctx for dynamic drop-state/reads)
         [staged-ephemeral ((spec-stage-ephemeral spec) instance parsed accessors)]

         ;; 3) stage-durable (pure)
         [staged-durable   ((spec-stage-durable   spec) instance parsed accessors)]

         ;; Merge durable updates into the current entity.
         [durable-entity
           (cond
             ((and (sorted-map? staged-durable)
                   (key? staged-durable entity-key)) staged-durable) ; full entity
             ((sorted-map? staged-durable) (make-mergemap instance staged-durable)) ; diff
             (:else instance))]

          ;; 4) events (pure; may read ephems via ctx)
         [events ((spec-create-events spec) durable-entity parsed accessors)]

         [next-state (spec-next spec)]
         [entity-id  (get durable-entity entity-key)])

    ;; persist staged ephemerals for the default drop-state = next-state
    (when (and entity-id (> (length staged-ephemeral) 0))
      (ephem-persist-staged! entity-name entity-id next-state staged-ephemeral))

    ;; advance state on the durable entity
    (assoc! durable-entity "state" next-state)

    ;; purge ephemerals scheduled for the state we just entered
    (when entity-id
      (ephem-purge-for-state! entity-name entity-id next-state))

    ;; return transition payload
    (sorted-map
      "put"    durable-entity
      "events" (if (vector? events) events (vector)))))


;; ---------------- Spec builder + defaults + accessors ----------------

(defun mk-state-handler (&key next parse stage-durable stage-ephemeral create-events)
  (sorted-map
    :next            (or next "STATE_UNKNOWN")
    :parse           (or parse _noop-parse)
    :stage-durable   (or stage-durable _noop-stage-durable)
    :stage-ephemeral (or stage-ephemeral _noop-stage-ephemeral)
    :create-events   (or create-events _noop-create-events)))

;; safe defaults
(defun _noop-parse (resp entity) resp)

;; return a vector of ephemeral intents (empty by default)
(defun _noop-stage-ephemeral (entity parsed accessors) (vector))

;; no durable changes by default
(defun _noop-stage-durable (entity parsed accessors) ())

;; no events by default
(defun _noop-create-events (entity parsed accessors) (vector))

;; registry / lookup
(defun lookup-state-spec (state)
  (or (get state-spec state) (sorted-map)))

;; accessors (with fallbacks)
(defun spec-next (spec)              (or (get spec :next) "STATE_UNKNOWN"))
(defun spec-parse (spec)             (or (get spec :parse) _noop-parse))
(defun spec-stage-ephemeral (spec)   (or (get spec :stage-ephemeral) _noop-stage-ephemeral))
(defun spec-stage-durable (spec)     (or (get spec :stage-durable) _noop-stage-durable))
(defun spec-create-events (spec)     (or (get spec :create-events) _noop-create-events))