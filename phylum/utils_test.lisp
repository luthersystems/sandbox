;; Copyright © 2021 Luther Systems, Ltd. All right reserved.

(in-package 'sandbox)
(use-package 'testing)

(test "account-functions"
  (let ([person0 "person0"]
        [person1 "person1"]
        [account-found? (lambda (found? balance) found?)]
        [get-balance (lambda (found? balance) balance)])
    (assert (create-account! person0 100))
    (assert-not (create-account! person0 10000))
    (assert-equal 50 (get (create-account! person1 50) "current_balance"))
    (assert-equal 100 (get (get-account person0) "current_balance"))
    (assert (account-transfer! person0 person1 25))
    (assert-not (account-transfer! person1 person0 100))
    (assert-equal 75 (get (get-account person0) "current_balance"))
    (assert-equal 75 (get (get-account person1) "current_balance"))))

(test "no-negative-accounts"
  (let ([person0 "person0"])
    (assert-not (create-account! person0 -100))))
