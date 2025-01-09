;; Copyright © 2021 Luther Systems, Ltd. All right reserved.

;; main.lisp

;; This file is the entrypoint for your chaincode application.  It should
;; initialize global variables and load files containing utilities and endpoint
;; definitions.  Be careful not to use methods in the cc: package namespace
;; while main.lisp is loading because there is no transaction context until the
;; endpoint handler fires.
(in-package 'sandbox)
(use-package 'router)
(use-package 'utils)

;; service-name can be used to identify the service in health checks and longs.
(set 'service-name "sandbox")

(set 'version "LUTHER_PROJECT_VERSION")  ; overridden during build
(set 'build-id "LUTHER_PROJECT_BUILD_ID")  ; overridden during build
(set 'service-version (format-string "{} ({})" version build-id))

(load-file "routes.lisp")
(load-file "claim.lisp")
