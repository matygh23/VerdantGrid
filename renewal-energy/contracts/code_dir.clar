;; Decentralized Renewable Energy Asset Network
;; A Clarity smart contract for collaborative verification, investment, and management of renewable energy assets

;; Constants
(define-constant ERR-NOT-NETWORK-OPERATOR (err u1))
(define-constant ERR-GRID-OFFLINE (err u2))
(define-constant ERR-INVALID-INSTALLATION (err u3))
(define-constant ERR-INSTALLATION-LOCKED (err u4))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-CAPACITY (err u6))
(define-constant ERR-INSTALLATION-EXISTS (err u7))
(define-constant ERR-ALREADY-CERTIFIED (err u8))
(define-constant ERR-NOT-AUTHORIZED (err u9))
(define-constant ERR-PRODUCTION-NOT-FOUND (err u10))
(define-constant MAX-INSTALLATION-ID u1000) ;; Maximum allowed installation ID
(define-constant MIN-CAPACITY-REQUIRED u10) ;; Minimum capacity to register
(define-constant MAX-CAPACITY-INPUT u1000000) ;; Maximum capacity input allowed
(define-constant MAX-VALIDATION-THRESHOLD u100) ;; Maximum validation threshold (100%)

;; Data Variables
(define-data-var network-operator principal tx-sender)
(define-data-var grid-operational bool false)
(define-data-var production-period uint u0)
(define-data-var minimum-capacity-threshold uint u100) ;; 100 capacity units minimum
(define-data-var certification-threshold uint u66) ;; 66% approval required for certification

;; Energy Installation Structure
(define-map energy-installations
    uint
    {
        installation-name: (string-utf8 128),
        description: (string-utf8 512),
        technical-hash: (buff 32),    ;; SHA256 hash of the technical specifications
        energy-type: (string-utf8 64),
        accepting-production: bool,
        developer: principal,
        total-capacity: uint,        ;; Sum of capacity of all engineers
        certified-production: uint    ;; Counter of accepted production reports
    }
)

;; Installation Engineers Mapping
(define-map installation-engineers
    {installation-id: uint, engineer: principal}
    {
        capacity-committed: uint
    }
)

;; Engineer Profiles
(define-map engineer-profiles
    principal
    {
        capacity: uint,
        installations-developed: (list 30 uint),
        production-reported: (list 30 uint),
        certification-weight: uint    ;; Derived from capacity but can be modified
    }
)

;; Production Report Structure
(define-map production-reports
    uint  ;; report-id
    {
        description: (string-utf8 256),
        metrics-hash: (buff 32),
        engineer: principal,
        target-installation: uint,
        submitted-in-period: uint,
        certified: bool
    }
)

;; Production Certifications
(define-map production-certifications
    {report-id: uint, certifier: principal}
    {
        validated: bool,
        weight: uint
    }
)

;; Certification Tallies for Production Reports
(define-map certification-tallies
    uint  ;; report-id
    {
        validation-weight: uint,
        rejection-weight: uint,
        total-certifications: uint
    }
)

;; Authorization
(define-private (is-network-operator)
    (is-eq tx-sender (var-get network-operator)))

;; Data Validation Functions
(define-private (is-valid-hash (hash (buff 32)))
    (> (len hash) u0))

(define-private (is-valid-description (desc (string-utf8 256)))
    (> (len desc) u0))

(define-private (is-valid-capacity (cap uint))
    (and (>= cap MIN-CAPACITY-REQUIRED) (<= cap MAX-CAPACITY-INPUT)))

;; Grid Management Functions
(define-public (activate-grid)
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        (var-set grid-operational true)
        (var-set production-period u0)
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
                accepting-production: true,
                developer: tx-sender,
                total-capacity: (get capacity engineer-profile),
                certified-production: u0
            })
        
        ;; Record engineer as developer
        (map-set installation-engineers 
            {installation-id: installation-id, engineer: tx-sender}
            {capacity-committed: (get capacity engineer-profile)})
        
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
                installations-developed: (list),
                production-reported: (list),
                certification-weight: initial-capacity
            })
            
        (ok true)))

;; Production Report Submission
(define-public (submit-production
    (report-id uint)
    (target-installation-id uint)
    (description (string-utf8 256))
    (metrics-hash (buff 32)))
    (let (
        (installation (unwrap! (map-get? energy-installations target-installation-id) ERR-INVALID-INSTALLATION))
        (engineer (unwrap! (map-get? engineer-profiles tx-sender) ERR-INSUFFICIENT-CAPACITY))
        )
        
        ;; Check grid status
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Check if installation is accepting production reports
        (asserts! (get accepting-production installation) ERR-INSTALLATION-LOCKED)
        
        ;; Check that report ID doesn't already exist
        (asserts! (is-none (map-get? production-reports report-id)) ERR-INVALID-PARAMETER)
        
        ;; Validate description and hash
        (asserts! (is-valid-description description) ERR-INVALID-PARAMETER)
        (asserts! (is-valid-hash metrics-hash) ERR-INVALID-PARAMETER)
        
        ;; Record the production report
        (map-set production-reports report-id
            {
                description: description,
                metrics-hash: metrics-hash,
                engineer: tx-sender,
                target-installation: target-installation-id,
                submitted-in-period: (var-get production-period),
                certified: false
            })
        
        ;; Initialize certification tally
        (map-set certification-tallies report-id
            {
                validation-weight: u0,
                rejection-weight: u0,
                total-certifications: u0
            })
        
        ;; Update engineer's reported production
        (map-set engineer-profiles tx-sender
            (merge engineer {
                production-reported: (unwrap! (as-max-len? 
                    (append (get production-reported engineer) report-id) u30)
                    ERR-INVALID-PARAMETER)
            }))
        
        (ok true)))

;; Certify Production Report
(define-public (certify-production
    (report-id uint)
    (validate bool))
    (let (
        (report (unwrap! (map-get? production-reports report-id) ERR-PRODUCTION-NOT-FOUND))
        (engineer (unwrap! (map-get? engineer-profiles tx-sender) ERR-INSUFFICIENT-CAPACITY))
        (certification-tally (unwrap! (map-get? certification-tallies report-id) ERR-PRODUCTION-NOT-FOUND))
        )
        
        ;; Check grid status
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Ensure report hasn't already been certified
        (asserts! (not (get certified report)) ERR-INSTALLATION-LOCKED)
        
        ;; Check engineer hasn't already certified
        (asserts! (is-none (map-get? production-certifications 
                                    {report-id: report-id, certifier: tx-sender})) 
                ERR-ALREADY-CERTIFIED)
        
        ;; Record the certification
        (map-set production-certifications 
            {report-id: report-id, certifier: tx-sender}
            {
                validated: validate,
                weight: (get certification-weight engineer)
            })
        
        ;; Update certification tally
        (map-set certification-tallies report-id
            (merge certification-tally {
                validation-weight: (if validate 
                                    (+ (get validation-weight certification-tally) (get certification-weight engineer))
                                    (get validation-weight certification-tally)),
                rejection-weight: (if (not validate)
                                    (+ (get rejection-weight certification-tally) (get certification-weight engineer))
                                    (get rejection-weight certification-tally)),
                total-certifications: (+ (get total-certifications certification-tally) u1)
            }))
        
        (ok true)))

;; Advance Production Period
(define-public (advance-production-period)
    (begin
        ;; Only network operator can advance periods
        (asserts! (is-network-operator) ERR-NOT-AUTHORIZED)
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Advance production period
        (var-set production-period (+ (var-get production-period) u1))
        
        (ok true)))

;; Process Specific Production Report
(define-public (process-production-report (report-id uint))
    (let (
        (report (unwrap! (map-get? production-reports report-id) ERR-PRODUCTION-NOT-FOUND))
        (certification-tally (unwrap! (map-get? certification-tallies report-id) ERR-PRODUCTION-NOT-FOUND))
        (installation (unwrap! (map-get? energy-installations (get target-installation report)) ERR-INVALID-INSTALLATION))
        (engineer (unwrap! (map-get? engineer-profiles (get engineer report)) ERR-INVALID-PARAMETER))
        )
        
        ;; Only network operator can process production reports
        (asserts! (is-network-operator) ERR-NOT-AUTHORIZED)
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Ensure report hasn't already been certified
        (asserts! (not (get certified report)) ERR-INSTALLATION-LOCKED)
        
        ;; Check for sufficient certifications and meeting threshold
        (if (and 
                (> (+ (get validation-weight certification-tally) (get rejection-weight certification-tally)) u0)
                (>= (* (get validation-weight certification-tally) u100) 
                    (* (+ (get validation-weight certification-tally) (get rejection-weight certification-tally)) (var-get certification-threshold)))
            )
            (begin
                ;; Update report status
                (map-set production-reports report-id
                    (merge report {certified: true}))
                
                ;; Update installation data
                (map-set energy-installations (get target-installation report)
                    (merge installation {
                        technical-hash: (get metrics-hash report),
                        certified-production: (+ (get certified-production installation) u1)
                    }))
                
                ;; Add engineer to installation engineers if not already
                (match (map-get? installation-engineers {installation-id: (get target-installation report), engineer: (get engineer report)})
                    existing-commitment
                    true
                    ;; Add new engineer
                    (map-set installation-engineers 
                        {installation-id: (get target-installation report), engineer: (get engineer report)}
                        {capacity-committed: (get capacity engineer)}))
                
                ;; Update installation's total capacity
                (map-set energy-installations (get target-installation report)
                    (merge installation {
                        total-capacity: (+ (get total-capacity installation) (get capacity engineer))
                    }))
                
                ;; Reward engineer with capacity boost
                (map-set engineer-profiles (get engineer report)
                    (merge engineer {
                        capacity: (+ (get capacity engineer) u25),
                        certification-weight: (+ (get certification-weight engineer) u10)
                    }))
                
                (ok true))
            (ok false)))) ;; No action if threshold not met

;; Change Installation Production Status
(define-public (set-installation-production-status (installation-id uint) (open bool))
    (let (
        (installation (unwrap! (map-get? energy-installations installation-id) ERR-INVALID-INSTALLATION))
        )
        
        ;; Check grid status
        (asserts! (var-get grid-operational) ERR-GRID-OFFLINE)
        
        ;; Only developer or network operator can change status
        (asserts! (or (is-eq tx-sender (get developer installation)) (is-network-operator)) ERR-NOT-AUTHORIZED)
        
        ;; Update installation status
        (map-set energy-installations installation-id
            (merge installation {accepting-production: open}))
        
        (ok true)))

;; Read-only functions
(define-read-only (get-installation-details (installation-id uint))
    (map-get? energy-installations installation-id))

(define-read-only (get-engineer-profile (engineer principal))
    (map-get? engineer-profiles engineer))

(define-read-only (get-production-report-details (report-id uint))
    (map-get? production-reports report-id))

(define-read-only (get-production-certifications (report-id uint))
    (map-get? certification-tallies report-id))

(define-read-only (get-grid-metrics)
    {
        operational: (var-get grid-operational),
        production-period: (var-get production-period),
        minimum-capacity: (var-get minimum-capacity-threshold),
        certification-threshold: (var-get certification-threshold)
    })

(define-public (update-minimum-capacity (new-minimum uint))
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        ;; Validate new threshold is within acceptable range
        (asserts! (and (>= new-minimum MIN-CAPACITY-REQUIRED) (<= new-minimum MAX-CAPACITY-INPUT)) ERR-INVALID-PARAMETER)
        (var-set minimum-capacity-threshold new-minimum)
        (ok true)))

(define-public (update-certification-threshold (new-percentage uint))
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        ;; Validate percentage is between 1 and 100
        (asserts! (and (> new-percentage u0) (<= new-percentage MAX-VALIDATION-THRESHOLD)) ERR-INVALID-PARAMETER)
        (var-set certification-threshold new-percentage)
        (ok true)))

(define-public (deactivate-grid)
    (begin
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        (var-set grid-operational false)
        (ok true)))

(define-public (transfer-operator-role (new-operator principal))
    (begin 
        (asserts! (is-network-operator) ERR-NOT-NETWORK-OPERATOR)
        ;; Cannot set to zero address (represented as none in Clarity)
        (asserts! (is-some (some new-operator)) ERR-INVALID-PARAMETER)
        (var-set network-operator new-operator)
        (ok true)))