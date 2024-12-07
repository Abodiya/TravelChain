;; Title: Enhanced Travel Experience Marketplace
;; Version: 0.2.0

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMS (err u102))

(define-data-var next-experience-id uint u0)
(define-data-var platform-fee uint u50) ;; 5% fee

(define-map experiences 
    { experience-id: uint }
    {
        host: principal,
        title: (string-utf8 256),
        description: (string-utf8 1024),
        price: uint,
        bookings: uint,
        revenue: uint,
        is-available: bool
    }
)

(define-map host-revenue principal uint)

(define-public (list-experience (title (string-utf8 256)) 
                                (description (string-utf8 1024))
                                (price uint))
    (let ((experience-id (var-get next-experience-id)))
        (asserts! (> (len title) u0) ERR-INVALID-PARAMS)
        (map-set experiences
            { experience-id: experience-id }
            {
                host: tx-sender,
                title: title,
                description: description,
                price: price,
                bookings: u0,
                revenue: u0,
                is-available: true
            }
        )
        (var-set next-experience-id (+ experience-id u1))
        (ok experience-id)))

(define-public (book-experience (experience-id uint))
    (let ((experience (unwrap! (map-get? experiences { experience-id: experience-id }) ERR-NOT-FOUND))
          (platform-cut (/ (* (get price experience) (var-get platform-fee)) u1000))
          (host-cut (- (get price experience) platform-cut)))
        (asserts! (get is-available experience) ERR-NOT-FOUND)
        
        ;; Transfer to host
        (try! (stx-transfer? host-cut tx-sender (get host experience)))
        
        ;; Update experience stats
        (map-set experiences 
            { experience-id: experience-id }
            (merge experience { 
                revenue: (+ (get revenue experience) (get price experience)),
                bookings: (+ (get bookings experience) u1)
            })
        )
        
        ;; Track host revenue
        (map-set host-revenue 
            (get host experience)
            (+ (default-to u0 (map-get? host-revenue (get host experience))) host-cut))
        
        (ok true)))

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-fee u100) ERR-INVALID-PARAMS)
        (ok (var-set platform-fee new-fee))))

(define-read-only (get-experience-details (experience-id uint))
    (map-get? experiences { experience-id: experience-id }))

(define-read-only (get-host-revenue (host principal))
    (default-to u0 (map-get? host-revenue host)))