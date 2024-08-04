(in-package 'sandbox)

(defun mk-connector-handler ()
  (let ([state (sorted-map)])
    (labels
      ([register-handler
         (name fn)
         (assoc! state name fn)]

       [mk-request-key 
         (req-id)
         (format-string "$cr:{}" req-id)]

       [register-request-callback
         (req-id handler-name &optional ctx)
         (let* ([ctx (default ctx (sorted-map))]
                [callback-state (sorted-map
                               "handler_name" handler-name)])
           (assoc! ctx "request_id" req-id)
           (assoc! callback-state "ctx" ctx)
           (sidedb:put (mk-request-key req-id) callback-state))]

       [unregister-request
         (req-id handler-name)
         (sidedb:purge (mk-request-key req-id))]

       [get-callback-state
         (req-id)
         (sidedb:get (or (mk-request-key req-id)
                         (error 'missing-handler "no registered handler")))]

       [call-handler
         (resp)
         (let* ([req-id (get resp "request_id")]
                [resp-body (transient:get "$ch_rep")])
           (unless req-id (error 'missing-req-id "missing request ID"))
           (unless resp-body (error 'missing-resp "missing response"))
           (let* ([callback-state (get-callback-state req-id)]
                  [handler-name (get callback-state "handler_name")]
                  [callback-ctx (get callback-state "ctx")]
                  [handler-fn (get state handler-name)])
             (if handler-fn
               (handler-fn resp-body callback-ctx)
               (error 'missing-handler 
                      (format "missing connector handler: {}" handler-name)))
             ;; TODO: handle multiple responses for single request_id (optional) 
             (unregister-request req-id)))])

    (lambda (op &rest args)
        (cond ((equal? op 'register-handler) (apply register-handler args))
              ((equal? op 'register-request-callback) (apply
                                                        register-request-callback
                                                        args))
              ((equal? op 'call-handler) (apply call-handler args))
              (:else (error 'unknown-operation op)))))))

(set 'connector-handlers (singleton mk-connector-handler))

;; internal handler called by the connector hub
(defendpoint "$ch_callback" (resp)
  (cc:infof resp "connectorhub callback")
  (connector-handlers 'call-handler resp)
  (route-success (sorted-map "status" "OK")))

(set 'add-connector-event
  ((lambda ()
    (let ([state (sorted-map "ctr" 0)])
      (lambda (event &optional handler-name)
        (let* ([ctr (get state "ctr")]
               [event-num (get state "ctr")]
               [event-body (get event "req")]
               [event-req-id (or
                               (get event-body "request_id")
                               (error 'missing-request-id
                                      "missing request ID"))]
               [event-header-msp (get event "msp")] ; msp ID for the connector
               [event-header-key (or                ; fabric key containing req
                                   (get event "key")
                                   (error 'missing-key
                                          "missing request key"))]
               [event-header-pdc (get event "pdc")] ; pdc storing key with req
               [event-header-oid (or ; ID of the object
                                   (get event "oid")
                                   (error 'missing-oid
                                          "missing object id"))]
               [ctx (sorted-map "oid" event-header-oid)]
               [event-ref-str
                 (thread-first
                   (sorted-map
                     ;; NOTE: we can't use the std tx req_id, b/c we need
                     ;; a unique one for each event (there are multiple per tx)
                     "rid" event-req-id
                     "msp" event-header-msp
                     "key" event-header-key
                     "pdc" event-header-pdc)
                   (denil-map)
                   (json:dump-bytes)
                   (to-string))]
               [event-ref-key (format-string "$connector_events:{}" ctr)]
               [event-body-bytes (json:dump-bytes event-body)])
          (when (>= ctr 10)
            (error 'too-many-events "too many events"))
          (when handler-name
            (connector-handlers 
              'register-request-callback
              event-req-id
              handler-name
              ctx))
          (cc:set-tx-metadata event-ref-key event-ref-str)
          (if event-header-pdc
            (cc:storage-put-private event-header-pdc
                                    event-header-key
                                    event-body-bytes)
            (cc:storage-put event-header-key event-body-bytes))
          (assoc! state "ctr" (+ event-num 1))))))))

(export 'register-connector-factory)
(defun register-connector-factory 
  (obj-factory)
  (let ([obj-handler-name (or (obj-factory 'name)
                             (error 'missing-name "factory missing name"))])
    (connector-handlers
      'register-handler
      obj-handler-name
      (lambda (resp ctx)
        (let* ([obj-id (or (get ctx "id")
                          'missing-obj-id "callback missing object ID")]
               [obj (obj-factory 'get obj-id)]
               [transition (obj 'handle resp)]
               [new-obj (get transition "new")]
               [del-obj (get transition "del")]
               [events (get transition "events")])
          (when new-obj 
            (obj-factory 'put new-obj)) 
          (when del-obj 
            (obj-factory 'del obj-id)) 
          (map #^(add-connector-event % obj-handler-name) events))))))
