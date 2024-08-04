;; Copyright © 2021 Luther Systems, Ltd. All right reserved.

;; utils.lisp

;; This file is loaded first and is ideal for defining utilities functions that
;; are widely used across your application.
(in-package 'sandbox)

(defun denil-map (m)
  ;; remove keys with nil entries from map.
  (let ([keep-keys (reject 'list (lambda (k) (nil? (get m k))) (keys m))])
    (foldl (lambda (acc v) (assoc! acc v (get m v))) (sorted-map) keep-keys)))

(defun singleton (fn)
  ;; ensure an object is lazy initialized once.
  ((lambda ()
    (let* ([r ()])
      (lambda (&rest args)
        (unless r (set! r (fn)))
        (apply r args))))))
