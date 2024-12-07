;; Title: Basic Travel Experience Marketplace
;; Version: 0.1.0

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))

(define-data-var next-experience-id uint u0)

(define-map experiences 
    { experience-id: uint }
    {
        host: principal,
        title: (string-utf8 256),
        price: uint,
        is-available: bool
    }
)

(define-public (list-experience (title (string-utf8 256)) (price uint))
    (let ((experience-id (var-get next-experience-id)))
        (map-set experiences
            { experience-id: experience-id }
            {
                host: tx-sender,
                title: title,
                price: price,
                is-available: true
            }
        )
        (var-set next-experience-id (+ experience-id u1))
        (ok experience-id)))

(define-public (book-experience (experience-id uint))
    (let ((experience (unwrap! (map-get? experiences { experience-id: experience-id }) ERR-NOT-FOUND)))
        (asserts! (get is-available experience) ERR-NOT-FOUND)
        (try! (stx-transfer? (get price experience) tx-sender (get host experience)))
        (ok true)))

(define-read-only (get-experience-details (experience-id uint))
    (map-get? experiences { experience-id: experience-id }))