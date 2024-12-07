;; Title: Decentralized Travel Experience Marketplace
;; Version: 1.0.0
;; Description: Smart contract for managing decentralized travel experiences, bookings, and revenue distribution

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants and Error Codes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-PARAMS (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-CONTRACT-PAUSED (err u105))

;;;;;;;;;;;;;;;;;;
;; Data Storage ;;
;;;;;;;;;;;;;;;;;;

;; Platform State
(define-data-var contract-paused bool false)
(define-data-var platform-fee uint u50) ;; 5% represented as 50/1000
(define-data-var next-experience-id uint u0)
(define-data-var current-timestamp uint u0)

;; Access Control Maps
(define-map administrators principal bool)
(define-map experience-hosts principal bool)
(define-map premium-travelers 
    principal 
    { membership-expires: uint }
)

;; Experience Storage
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
        is-available: bool
    }
)

;; Revenue Tracking
(define-map host-revenue principal uint)
(define-map platform-revenue (string-ascii 10) uint)

;;;;;;;;;;;;;;;;
;; Governance ;;
;;;;;;;;;;;;;;;;

;; Proposal tracking
(define-map governance-proposals
    uint 
    {
        title: (string-utf8 256),
        description: (string-utf8 1024),
        proposer: principal,
        votes-for: uint,
        votes-against: uint,
        end-timestamp: uint,
        executed: bool
    }
)

;;;;;;;;;;;;;;;;;;;;
;; Time Tracking ;;
;;;;;;;;;;;;;;;;;;;;

(define-public (update-timestamp (new-timestamp uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> new-timestamp (var-get current-timestamp)) ERR-INVALID-PARAMS)
        (ok (var-set current-timestamp new-timestamp))))

;;;;;;;;;;;;;;;;;;;;
;; Authorization ;;
;;;;;;;;;;;;;;;;;;;;

(define-private (is-admin)
    (default-to false (map-get? administrators tx-sender)))

(define-private (is-host)
    (default-to false (map-get? experience-hosts tx-sender)))

(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner))

(define-private (check-admin)
    (ok (asserts! (is-admin) ERR-NOT-AUTHORIZED)))

;;;;;;;;;;;;;;;;;;;;
;; Admin Functions ;;
;;;;;;;;;;;;;;;;;;;;

(define-public (set-platform-fee (new-fee uint))
    (begin
        (try! (check-admin))
        (asserts! (<= new-fee u100) ERR-INVALID-PARAMS)
        (ok (var-set platform-fee new-fee))))

(define-public (toggle-contract-pause)
    (begin
        (try! (check-admin))
        (ok (var-set contract-paused (not (var-get contract-paused))))))

(define-public (add-administrator (admin principal))
    (begin
        (try! (check-admin))
        (asserts! (not (is-eq admin 'SP000000000000000000002Q6VF78)) ERR-INVALID-PARAMS)
        (ok (map-set administrators admin true))))

;;;;;;;;;;;;;;;;;;;;;;;
;; Host Functions ;;
;;;;;;;;;;;;;;;;;;;;;;;

(define-public (register-as-host)
    (begin
        (asserts! (not (is-host)) ERR-ALREADY-EXISTS)
        (ok (map-set experience-hosts tx-sender true))))

(define-public (list-experience (title (string-utf8 256)) 
                           (description (string-utf8 1024)) 
                           (location-hash (buff 32)) 
                           (price uint))
    (let ((experience-id (var-get next-experience-id))
          (current-time (var-get current-timestamp)))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (is-host) ERR-NOT-AUTHORIZED)
        (asserts! (> (len title) u0) ERR-INVALID-PARAMS)
        (asserts! (> (len description) u0) ERR-INVALID-PARAMS)
        (asserts! (not (is-eq location-hash 0x0000000000000000000000000000000000000000000000000000000000000000)) ERR-INVALID-PARAMS)
        (asserts! (>= price u0) ERR-INVALID-PARAMS)
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
                is-available: true
            }
        )
        (var-set next-experience-id (+ experience-id u1))
        (ok experience-id)))

;;;;;;;;;;;;;;;;;;;;
;; User Functions ;;
;;;;;;;;;;;;;;;;;;;;

(define-public (book-experience (experience-id uint))
    (let ((experience (unwrap! (map-get? experiences { experience-id: experience-id }) ERR-NOT-FOUND)))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (< experience-id (var-get next-experience-id)) ERR-NOT-FOUND)
        (asserts! (get is-available experience) ERR-NOT-FOUND)
        
        ;; Process payment
        (try! (stx-transfer? (get price experience) tx-sender (get host experience)))
        
        ;; Update booking tracking
        (map-set experiences 
            { experience-id: experience-id }
            (merge experience { 
                revenue: (+ (get revenue experience) (get price experience)),
                bookings: (+ (get bookings experience) u1)
            })
        )
        (ok true)))

(define-public (subscribe-premium (duration uint))
    (let ((price (* duration u10000000)) ;; 10 STX per period
          (current-time (var-get current-timestamp))
          (expiry (+ current-time (* duration u144)))) ;; ~1 day periods
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (> duration u0) ERR-INVALID-PARAMS)
        (try! (stx-transfer? price tx-sender contract-owner))
        (ok (map-set premium-travelers 
            tx-sender 
            { membership-expires: expiry }))))

;;;;;;;;;;;;;;;;;;;;;;;
;; Getter Functions ;;
;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-experience-details (experience-id uint))
    (map-get? experiences { experience-id: experience-id }))

(define-read-only (get-host-revenue (host principal))
    (default-to u0 (map-get? host-revenue host)))

(define-read-only (is-premium-traveler (user principal))
    (let ((current-time (var-get current-timestamp))
          (sub (default-to 
            { membership-expires: u0 } 
            (map-get? premium-travelers user))))
        (> (get membership-expires sub) current-time)))

;;;;;;;;;;;;;;;;
;; Initialize ;;
;;;;;;;;;;;;;;;;

;; Initialize contract owner as first administrator
(map-set administrators contract-owner true)

;; Initialize platform revenue
(map-set platform-revenue "total" u0)

;; Set initial timestamp
(var-set current-timestamp u1)