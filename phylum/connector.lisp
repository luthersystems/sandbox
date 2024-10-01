(in-package 'sandbox)
;;
;; Connector hubs (hub) listen for events that encode requests, forward them to
;; third-party services, and then send the responses back to the phylum, via
;; a special $ch_callback endpoint. Events are carefully crafted using several
;; data structures to ensure privacy and economic storage.
;;
;; *Request Generation Logic*:
;;
;; Phylum logic create events, and register a callback class factory, that
;; instantiates a business object (using the "class" pattern) which receives
;; the response using a `'handle` method. Each event registration specifies
;; the business object class that is responsible for instantiating these
;; objects, along with the "Object ID" (OID) associated with the event.
;;
;; The event header is stored in the event data map, using a special prefix
;; `$connector_events:N`, where `N` is an incrementing counter. A single
;; phylum tx may contain multiple event headers and multiple events.
;; Note that event data is public to the orderer and all members of the network.
;; The event header contains a reference to a particular event "context".
;;
;; An event has a "context", which is data that is also available to the
;; callback during its execution. The context is stored in the sideDB, a
;; hardcoded PDC with name `private`. Luther configures its networks so that
;; all orgs have access to this common PDC, however the orderer does not have
;; access to any PDC. The key for this context data is `$cr:<REQ_ID>`.
;; The context is wrapped in a "callback state" object, which includes the 
;; handler name for the object, necessary for routing responses to factories.
;; The event context contains a reference to the request body, along with an 
;; MSP that determines which org and their respective connector is responsible
;; for processing the request. The context also stores the OID, which is used
;; when processing the response.
;;
;; The request body itself is stored either in the stateDB or in a PDC, and is
;; referenced indirectly by the event context. The body contains the request
;; payload that is to be forwarded to the third-party system. Every request has
;; a unique request ID, which is used to correlate a response to a callback.
;; *IMPORTANT*: this request ID is NOT the same as the request ID embedded
;; in the transaction context, which is primarily used for tracing.
;;
;; *Response Handling Logic*:
;;
;; Once the hub has forwarded the request, and received a response from the
;; third-party system, it then sends this response to the `$ch_callback `
;; entrypoint, passing in the response as transient data using key prefix 
;; `$ch_rep:N`, which may include multiple responses for different requests.
;; This response includes the request ID, which is used to correlate the
;; response with the request via the same event context. The MSPID in the
;; original event context is used to ensure that a response is only received
;; by the correct org, so an org cannot spoof responses for requests from
;; another org.
;;
;; The phylum logic for `$ch_callback` uses the req ID to lookup the event
;; context, along with the OID and class factory. The class factory is used
;; to instantiate the object for that OID, and call the handle method on that
;; object with the response.
;;
;; Upon execution of the callback, the original event context is purged, along
;; with the original request (or deleted if in state DB), so as to reduce
;; storage space.
;;
(defun mk-connector-handler ()
  (let ([state (sorted-map)])
    (labels
      ([register-handler (name fn)
         (assoc! state name fn)]

       [mk-request-key (req-id)
         (format-string "$cr:{}" req-id)]

       ;; IMPORTANT: we store this in the central `private` PDC since we
       ;; don't know which PDC the original request was stored.
       [register-request-callback (req-id handler-name &optional ctx)
         (let* ([ctx (default ctx (sorted-map))]
                [callback-state (sorted-map
                               "handler_name" handler-name)])
           (assoc! ctx "request_id" req-id)
           (assoc! callback-state "ctx" ctx)
           (sidedb:put (mk-request-key req-id) callback-state))]

       [unregister-request (req-id ctx)
         ;; TODO: handle multiple responses for single request_id (optional) 
         (let* ([callback-state-key (mk-request-key req-id)]
                [key (get ctx "key")]
                [pdc (get ctx "pdc")])
           (sidedb:purge callback-state-key)
           (if pdc
            (cc:storage-purge-private pdc key)
            (statedb:del key)))]

       [get-callback-state (req-id)
         (or (sidedb:get (mk-request-key req-id))
                         (error 'missing-handler "no registered handler"))]

       [call-handler-helper (resp-body)
         (unless resp-body (error 'missing-resp "missing response"))
         (let* ([req-id (get resp-body "request_id")]
                [callback-state (get-callback-state req-id)]
                [handler-name (get callback-state "handler_name")]
                [ctx (default (get callback-state "ctx") (sorted-map))]
                [msp (get ctx "msp")]
                [handler-fn (get state handler-name)])
           (when msp 
             (cc:debugf (sorted-map "msp" msp "req_id" req-id) "validating MSP")
             (if (valid-msp? msp)
               (cc:debugf (sorted-map "msp" msp) "MSPID validated")
               (set-exception-security "invalid MSP for response")))
           (if handler-fn
             (handler-fn resp-body ctx)
             (error 'missing-handler 
                    (format "missing connector handler: {}" handler-name)))
           (unregister-request req-id ctx))]

       [call-handler-helper-recurse-i (i)
         (let* ([resp-body (transient:get (format-string "$ch_rep:{}" i))])
           (when resp-body
             (call-handler-helper resp-body)
             (call-handler-helper-recurse-i (+ i 1))))]

       [call-handler (resp)
         (call-handler-helper-recurse-i 0)])
 
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

;; add-connector-event inspects an event and sets up the data structures to 
;; register callbacks.
(set 'add-connector-event
  ((lambda ()
    (let ([state (sorted-map "ctr" 0)])
      (lambda (event &optional handler-name)
        (let* ([ctr (get state "ctr")]
               [event-num (get state "ctr")]
               [event-body (get event "req")]
               [event-req-id (or
                               (get event-body "request_id")
                               (mk-uuid))]
               [event-key (get event "key")] ; if key omitted then use req id
               [event-pdc (get event "pdc")] ; pdc storing key with req
               [event-oid (or ; ID of the object
                                   (get event "oid")
                                   (error 'missing-oid
                                          "missing object id"))]
               [event-header (sorted-map "rid" event-req-id)]
               [ctx (sorted-map "oid" event-oid
                                "key" event-key
                                "pdc" event-pdc
                                "msp" (get event "msp")   ; opt. connector MSP
                                "sys" (get event "sys")   ; opt. system name
                                "eng" (get event "eng"))] ; opt. english
                                                          ; description of event
               [event-ref-str
                 (thread-first
                   event-header
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
          (if event-pdc
            (cc:storage-put-private event-pdc
                                    event-key
                                    event-body-bytes)
            (cc:storage-put event-key event-body-bytes))
          (assoc! state "ctr" (+ event-num 1))))))))

(export 'do-transition)
(defun do-transition (obj-factory transition)
  (let* ([obj-handler-name (or (obj-factory 'name)
                             (error 'missing-name "factory missing name"))]
         [put-obj (get transition "put")] 
         [del-obj (get transition "del")] 
         [events (get transition "events")]) 
    (when put-obj 
      (obj-factory 'put put-obj))
    (when del-obj 
      (obj-factory 'del obj-id)) 
    (map () #^(add-connector-event % obj-handler-name) events)
    put-obj))

(export 'register-connector-factory)
(defun register-connector-factory 
  (obj-factory)
  (let ([obj-handler-name (or (obj-factory 'name)
                             (error 'missing-name "factory missing name"))])
    (connector-handlers
      'register-handler
      obj-handler-name
      (lambda (resp ctx)
        (let* ([obj-id (or (get ctx "oid")
                           (error 'missing-obj-id "callback missing object ID"))]
               [obj (or (obj-factory 'get obj-id)
                           (error 'missing-obj "callback missing object"))]
               [transition (obj 'handle resp)])
          (do-transition obj-factory transition))))))
