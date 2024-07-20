;; Copyright © 2021 Luther Systems, Ltd. All right reserved.

;; utils.lisp

;; This file is loaded first and is ideal for defining utilities functions that
;; are widely used across your application.
(in-package 'sandbox)

(defun singleton (fn)
  ((lambda ()
    (let* ([r ()])
      (lambda (&rest args)
        (unless r (set! r (fn)))
        (apply r args))))))
