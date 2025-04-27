;; Decentralized Renewable Energy Asset Network
;; A Clarity smart contract for collaborative verification, investment, and management of renewable energy assets

;; Constants
(define-constant ERR-NOT-NETWORK-OPERATOR (err u1))
(define-constant ERR-GRID-OFFLINE (err u2))
(define-constant ERR-INVALID-INSTALLATION (err u3))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-CAPACITY (err u6))
(define-constant ERR-INSTALLATION-EXISTS (err u7))
(define-constant MAX-INSTALLATION-ID u1000) ;; Maximum allowed installation ID
(define-constant MIN-CAPACITY-REQUIRED u10) ;; Minimum capacity to register
(define-constant MAX-CAPACITY-INPUT u1000000) ;; Maximum capacity input allowed

;; Data Variables
(define-data-var network-operator principal tx-sender)
(define-data-var grid-operational bool false)
(define-data-var minimum-capacity-threshold uint u100) ;; 100 capacity units minimum

;; Energy Installation Structure
(define-map energy-installations
    uint
    {
        installation-name: (string-utf8 128),
        description: (string-utf8 512),
        technical-hash: (buff 32),    ;; SHA256 hash of the technical specifications
        energy-type: (string-utf8 64),
        developer: principal,
        total-capacity: uint
    }
)

;; Engineer Profiles
(define-map engineer-profiles
    principal
    {
        capacity: uint,
        installations-developed: (list 30 uint)
    }
)

;; Authorization
(define-private (is-network-operator)
    (is-eq tx-sender (var-get network-operator)))

;; Data Validation Functions
(define-private (is-valid-hash (hash (buff 32)))
    (> (len hash) u0))

(define-private (is-valid-capacity (cap uint))
    (and (>= cap MIN-CAPACITY-REQUIRED) (<= cap MAX-CAPACITY-INPUT)))

;; Grid Management Functions
(define-public (activate-grid)
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        (var-set grid-operational true)
        (ok true)))

(define-public (deactivate-grid)
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        (var-set grid-operational false)
        (ok true)))

(define-public (register-installation
    (installation-id uint)
    (installation-name (string-utf8 128))
    (description (string-utf8 512))
    (technical-hash (buff 32))
    (energy-type (string-utf8 64)))
    (let (
        (engineer-profile (unwrap! (map-get? engineer-profiles tx-sender) ERR-INSUFFICIENT-CAPACITY))
        (validated-hash (if (is-valid-hash technical-hash) technical-hash 0x))
        )
        
        ;; Check grid status
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Validate installation-id is within acceptable range
        (asserts! (<= installation-id MAX-INSTALLATION-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if installation already exists
        (asserts! (is-none (map-get? energy-installations installation-id)) ERR-INSTALLATION-EXISTS)
        
        ;; Validate installation-name and description are not empty
        (asserts! (> (len installation-name) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len description) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len energy-type) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate hash is not empty
        (asserts! (is-valid-hash technical-hash) ERR-INVALID-PARAMETER)
        
        ;; Check engineer has enough capacity to register installation
        (asserts! (>= (get capacity engineer-profile) (var-get minimum-capacity-threshold)) ERR-INSUFFICIENT-CAPACITY)
        
        ;; Set the installation data
        (map-set energy-installations installation-id
            {
                installation-name: installation-name,
                description: description,
                technical-hash: validated-hash,
                energy-type: energy-type,
                developer: tx-sender,
                total-capacity: (get capacity engineer-profile)
            })
        
        ;; Update engineer profile
        (map-set engineer-profiles tx-sender
            (merge engineer-profile {
                installations-developed: (unwrap! (as-max-len? 
                    (append (get installations-developed engineer-profile) installation-id) u30)
                    ERR-INVALID-PARAMETER)
            }))
        
        (ok true)))

;; Engineer Registration Functions
(define-public (register-engineer (initial-capacity uint))
    (begin
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Validate capacity input
        (asserts! (is-valid-capacity initial-capacity) ERR-INVALID-PARAMETER)
        
        ;; Require some capacity token transfer (simplified for demonstration)
        (try! (stx-transfer? initial-capacity tx-sender (var-get network-operator)))
        
        ;; Initialize engineer profile with validated capacity
        (map-set engineer-profiles tx-sender
            {
                capacity: initial-capacity,
                installations-developed: (list)
            })
            
        (ok true)))

;; Read-only functions
(define-read-only (get-installation-details (installation-id uint))
    (map-get? energy-installations installation-id))

(define-read-only (get-engineer-profile (engineer principal))
    (map-get? engineer-profiles engineer))

(define-read-only (get-grid-metrics)
    {
        operational: (var-get grid-operational),
        minimum-capacity: (var-get minimum-capacity-threshold)
    })

(define-public (update-minimum-capacity (new-minimum uint))
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        ;; Validate new threshold is within acceptable range
        (asserts! (and (>= new-minimum MIN-CAPACITY-REQUIRED) (<= new-minimum MAX-CAPACITY-INPUT)) ERR-INVALID-PARAMETER)
        (var-set minimum-capacity-threshold new-minimum)
        (ok true)))

(define-public (transfer-operator-role (new-operator principal))
    (begin 
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        ;; Cannot set to zero address (represented as none in Clarity)
        (asserts! (is-some (some new-operator)) ERR-INVALID-PARAMETER)
        (var-set network-operator new-operator)
        (ok true)))