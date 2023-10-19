;; Copyright © 2021 Luther Systems, Ltd. All right reserved.

;; utils.lisp

;; This file is loaded first and is ideal for defining utilities functions that
;; are widely used across your application.
(in-package 'sandbox)

;; This block defines helper functions for account objects in the data model.
;; The helper functions have their own internal, private helpers which are
;; defined by labels.
(labels ([mk-balance-key (acct-id) (format-string "{}:{}:balance" "account" acct-id)]
         [mk-asset-id-key (acct-id) (format-string "{}:{}:asset-id" "account" acct-id)]

         [get-balance (acct-id)
          (cc:infof (sorted-map "account_id" acct-id "field" "balance") "GET")
          (let* ([key (mk-balance-key acct-id)]
                 [balance (statedb:get key)])
            (if (nil? balance) '() (to-int balance)))]

         [put-balance! (acct-id balance)
          (cc:infof (sorted-map "account_id" acct-id "field" "balance") "PUT")
          (let* ([key (mk-balance-key acct-id)])
            (statedb:put key (to-int balance))
            true)]

         [get-asset-id (acct-id)
          (cc:infof (sorted-map "account_id" acct-id "field" "asset_id") "GET")
          (let* ([key (mk-asset-id-key acct-id)]
                 [asset-id (statedb:get key)])
            (if (nil? asset-id) "" (to-string asset-id)))]

         [put-asset-id! (acct-id asset-id)
          (cc:infof (sorted-map "account_id" acct-id "field" "asset_id") "PUT")
          (let* ([key (mk-asset-id-key acct-id)])
            (statedb:put key (to-string asset-id))
            true)]

         [put-account! (acct-id balance asset-id)
          (and
            (put-balance! acct-id balance)
            (put-asset-id! acct-id asset-id))]

         [make-account (acct-id balance asset-id)
          (sorted-map "account_id" acct-id
                      "balance" (to-int balance)
                      "asset_id" asset-id)]

         [get-account (acct-id)
          (let* ([balance (get-balance acct-id)])
            (if (nil? balance )
              '()
              (let* ([asset-id (get-asset-id acct-id)])
                (make-account acct-id balance asset-id))))])

        ;; account-do is a simple way to execute a function against an account record
        ;; in statedb.
        (defun account-do (acct-id fn)
          (let* ([acct (get-account acct-id)])
            (if (nil? acct)
              (funcall fn false '())
              (funcall fn true acct))))

        ;; create-account! creates a new account record in statedb and records an
        ;; account object.  If the given acct-id already exists in statedb
        ;; create-account! does nothing and returns nil.
        (defun create-account! (acct-id balance &optional asset-id)
          (let* ([asset-id (if (nil? asset-id) "" asset-id)])
            (account-do acct-id
                        (lambda (found? _)
                          (and (not found?)
                               (put-account! acct-id balance asset-id)
                               (make-account acct-id balance asset-id))))))

        ;; get-account retrieves an account record from statedb.  If the given
        ;; account does not exist a nil value is returned.
        (defun get-account (acct-id)
          (account-do acct-id
                      (lambda (found? account)
                        (if found? account '()))))

        ;; set-balance! sets the balance in the specified account and returns true.
        ;; If the specified account does not exist set-balance! returns false.
        (defun set-balance! (acct-id balance)
          (account-do acct-id
                      (lambda (found? act)
                        (and found?
                             (put-balance! acct-id balance)))))

        ;; account-transfer! moves amount units between two accounts for the same asset.
        ;; account-transfer! will allow account balances to go negative.
        (defun account-transfer! (from-id to-id amount)
          (account-do from-id
                      (lambda (from-found? from-acct)
                        (and from-found?
                             (account-do to-id
                                         (lambda (to-found? to-acct)
                                           (and to-found?
                                                (let* ([from-asset-id (get from-acct "asset_id")]
                                                       [from-balance (get from-acct "balance")]
                                                       [new-from-balance (- from-balance amount)]
                                                       [to-asset-id (get to-acct "asset_id")]
                                                       [to-balance (get to-acct "balance")]
                                                       [new-to-balance (+ to-balance amount)])
                                                  (and
                                                    (equal? from-asset-id to-asset-id)
                                                    (set-balance! from-id new-from-balance)
                                                    (set-balance! to-id new-to-balance))))))))))
        )
