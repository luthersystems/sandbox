(in-package 'sandbox)

;; TODO: move all methods into single class

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
         (let ([callback-state (sorted-map
                               "handler_name" handler-name)])
           (when ctx (assoc! callback-state "ctx" ctx))
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
         (let ([req-id (get resp "request_id") ])
           (unless req-id (error 'missing-req-id "missing request ID"))
           (let ([callback-state (get-callback-state req-id)]
                 [handler-name (get callback-state "handler_name")]
                 [callback-ctx (get callback-state "ctx")]
                 [handler-fn (get state handler-name)])
             (if handler-fn
               (apply handler-fn resp callback-ctx)
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
  (connector-handlers 'call-handler resp))

(defun denil-map (m)
  ;; remove keys with nil entries from map
  (let ([keep-keys (reject 'list (lambda (k) (nil? (get m k))) (keys m))])
    (foldl (lambda (acc v) (assoc! acc v (get m v))) (sorted-map) keep-keys)))

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
               [event-body-msp (get event "msp")] ; msp ID for responsible connector
               [event-body-key (get event "key")] ; fabric key containing req
               [event-body-pdc (get event "pdc")] ; pdc storing key with req
               [event-ref-str
                 (thread-first
                   (sorted-map
                     ;; NOTE: we can't use the std tx req_id, b/c we need
                     ;; a unique one for each event (there are multiple per tx)
                     "rid" event-req-id
                     "msp" event-body-msp
                     "key" event-body-key
                     "pdc" event-body-pdc)
                   (denil-map)
                   (json:dump-bytes)
                   (to-string))]
               [event-ref-key (format-string "$connector_events:{}" ctr)]
               [event-body-bytes (json:dump-bytes event-body)])
          (when (>= ctr 10)
            (error 'too-many-events "too many events"))
          (when handler-name
            (connector-handlers 
              'register-request-callback event-req-id handler-name))
          (cc:set-tx-metadata event-ref-key event-ref-str)
          (if event-body-pdc
            (cc:storage-put-private event-body-pdc 
                                    event-body-key 
                                    event-body-bytes)
            (cc:storage-put event-body-key event-body-bytes))
          (assoc! state "ctr" (+ event-num 1))))))))

(export 'register-connector-factory)
(defun register-connector-factory 
  (obj-factory)
  (let ([obj-handler-name (or (obj-factory 'name)
                             (error 'missing-name "factory missing name"))])
    (connector-handlers 
      'register-handler 
      obj-handler-name 
      (lambda (resp &optional ctx) 
        (let ([obj-id (or (get ctx "id") 
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
