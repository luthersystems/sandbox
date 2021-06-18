;; utils.lisp

;; This file is loaded first and is ideal for defining utilities functions that
;; are widely used across your application.
(in-package 'sandbox)

;; This block defines helper functions for account objects in the data model.
;; The helper functions have their own internal, private helpers which are
;; defined by labels.
(labels ([make-account (acct-id balance)
          (sorted-map "account_id" acct-id
                      "current_balance" (to-int balance))]
         [get-balance (acct-id)
          (cc:infof (sorted-map "account_id" acct-id) "GET")
          (let* ([balance (statedb:get acct-id)])
            (if (nil? balance) '() (to-int balance)))]
         [put-account! (acct-id balance)
          (cc:infof (sorted-map "account_id" acct-id "balance" balance) "PUT")
          (statedb:put acct-id (to-int balance))
          true])

        ;; create-account! creates a new account record in statedb and records an
        ;; account object.  If the given acct-id already exists in statedb
        ;; create-account! does nothing and returns nil.
        (defun create-account! (acct-id balance)
          (account-do acct-id
                      (lambda (found? _)
                        (and (not found?)
                             (put-account! acct-id balance)
                             (make-account acct-id balance)))))

        ;; get-account retrieves an account record from statedb.  If the given
        ;; account does not exist a nil value is returned.
        (defun get-account (acct-id)
          (account-do acct-id
                      (lambda (found? balance)
                        (if found? (make-account acct-id balance) '()))))

        ;; set-balance! sets the balance in the specified account and returns true.
        ;; If the specified account does not exist set-balance! returns false.
        (defun set-balance! (acct-id balance)
          (account-do acct-id
                      (lambda (found? _)
                        (and found?
                             (put-account! acct-id balance)))))

        ;; account-transfer! moves amount units between two accounts.
        ;; account-transfer! will allow account balances to go negative.
        (defun account-transfer! (from-id to-id amount)
          (account-do from-id
                      (lambda (from-found? from-bal)
                        (and from-found?
                             (account-do to-id
                                         (lambda (to-found? to-bal)
                                           (and to-found?
                                                (put-account! from-id (- from-bal amount))
                                                (put-account! to-id (+ to-bal amount)))))))))

        ;; account-do is a simple way to execute a function against an account record
        ;; in statedb.
        (defun account-do (acct-id fn)
          (let* ([balance (get-balance acct-id)])
            (if (nil? balance)
              (funcall fn false 0)
              (funcall fn true balance))))
        )
