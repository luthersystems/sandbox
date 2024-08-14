;; Copyright © 2024 Luther Systems, Ltd. All right reserved.

(in-package 'sandbox)
(use-package 'testing)

(test "claims"
  (let* ([claim (create-claim)]
         [_ (assert (not (nil? claim)))]
         [data (claim 'data)]) 
    (assert (not (nil? (get data "state"))))
    (assert (not (nil? (get data "claim_id"))))
    (let*
      ([claim-id (get data "claim_id")]
       [got-claim (claims 'get claim-id)])
      (assert (not (nil? got-claim))))))
