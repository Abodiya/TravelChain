;; Title: Decentralized Travel Experience Marketplace
;; Version: 1.0.0

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMS (err u102))
(define-constant ERR-CONTRACT-PAUSED (err u103))

(define-data-var contract-paused bool false)
(define-data-var next-experience-id uint u0)
(define-data-var platform-fee uint u50)
(define-data-var current-timestamp uint u0)

(define-map administrators principal bool)
(define-map experience-hosts principal bool)
(define-map premium-travelers 
    principal 
    { membership-expires: uint }
)

(define-map experiences 
    { experience-id: uint }
    {
        host: principal,
        title: (string-utf8 256),
        description: (string-utf8 1024),
        location-hash: (buff 32),
        price: uint,
        created-at: uint,
        bookings: uint,
        revenue: uint,
        is-available: bool,
        max-travelers: uint
    }
)

(define-map host-revenue principal uint)
(define-map platform-revenue (string-ascii 10) uint)

(define-public (update-timestamp (new-timestamp uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> new-timestamp (var-get current-timestamp)) ERR-INVALID-PARAMS)
        (ok (var-set current-timestamp new-timestamp))))

(define-public (register-as-host)
    (begin
        (asserts! (not (default-to false (map-get? experience-hosts tx-sender))) ERR-NOT-AUTHORIZED)
        (ok (map-set experience-hosts tx-sender true))))

(define-public (list-experience 
    (title (string-utf8 256)) 
    (description (string-utf8 1024)) 
    (location-hash (buff 32)) 
    (price uint)
    (max-travelers uint))
    (let ((experience-id (var-get next-experience-id))
          (current-time (var-get current-timestamp)))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (default-to false (map-get? experience-hosts tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (> (len title) u0) ERR-INVALID-PARAMS)
        (asserts! (> max-travelers u0) ERR-INVALID-PARAMS)
        (map-set experiences
            { experience-id: experience-id }
            {
                host: tx-sender,
                title: title,
                description: description,
                location-hash: location-hash,
                price: price,
                created-at: current-time,
                bookings: u0,
                revenue: u0,
                is-available: true,
                max-travelers: max-travelers
            }
        )
        (var-set next-experience-id (+ experience-id u1))
        (ok experience-id)))

(define-public (book-experience (experience-id uint))
    (let ((experience (unwrap! (map-get? experiences { experience-id: experience-id }) ERR-NOT-FOUND))
          (platform-cut (/ (* (get price experience) (var-get platform-fee)) u1000))
          (host-cut (- (get price experience) platform-cut)))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (get is-available experience) ERR-NOT-FOUND)
        (asserts! (< (get bookings experience) (get max-travelers experience)) ERR-INVALID-PARAMS)
        
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

(define-public (subscribe-premium (duration uint))
    (let ((price (* duration u10000000))
          (current-time (var-get current-timestamp))
          (expiry (+ current-time (* duration u144))))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (> duration u0) ERR-INVALID-PARAMS)
        (try! (stx-transfer? price tx-sender contract-owner))
        (ok (map-set premium-travelers 
            tx-sender 
            { membership-expires: expiry }))))

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (ok (var-set contract-paused (not (var-get contract-paused))))))

(define-read-only (get-experience-details (experience-id uint))
    (map-get? experiences { experience-id: experience-id }))

(define-read-only (is-premium-traveler (user principal))
    (let ((current-time (var-get current-timestamp))
          (sub (default-to 
            { membership-expires: u0 } 
            (map-get? premium-travelers user))))
        (> (get membership-expires sub) current-time)))

;; Initialize contract
(map-set administrators contract-owner true)
(var-set current-timestamp u1)
(var-set platform-fee u50)