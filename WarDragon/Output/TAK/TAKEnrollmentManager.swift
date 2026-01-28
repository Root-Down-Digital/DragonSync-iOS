import Foundation
import Security
import CryptoKit
import os.log
import UIKit

@MainActor
class TAKEnrollmentManager: ObservableObject {
    
    @Published private(set) var enrollmentState: EnrollmentState = .notEnrolled
    @Published private(set) var certificateInfo: CertificateInfo?
    @Published private(set) var lastError: Error?
    @Published private(set) var enrollmentProgress: String = ""
    
    private let logger = Logger(subsystem: "com.wardragon", category: "TAKEnrollment")
    private let enrollmentPort: Int = 8446
    private let apiBasePort: Int = 443  // Standard HTTPS for API calls
    
    private let truststoreCertKey = "com.wardragon.tak.truststore"
    private let clientCertDataKey = "com.wardragon.tak.clientcert.data"
    private let clientKeyDataKey = "com.wardragon.tak.clientkey.data"
    private let clientIdentityLabel = "WarDragon TAK Client"
    private let certMetadataKey = "com.wardragon.tak.certmetadata"
    private let clientCertKey = "com.wardragon.tak.clientcert"
    private let certExpiryKey = "com.wardragon.tak.cert.expiry"
    private let deviceUIDKey = "com.wardragon.tak.device.uid"
    
    /// Get or create a persistent device UID for TAK Server enrollment
    /// This MUST remain consistent across app launches
    private func getOrCreateDeviceUID() -> String {
        if let existingUID = UserDefaults.standard.string(forKey: deviceUIDKey) {
            logger.info("Using existing device UID: \(existingUID)")
            return existingUID
        }
        
        let vendorID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceUID = "APPLE-iOS-\(vendorID)"
        
        UserDefaults.standard.set(deviceUID, forKey: deviceUIDKey)
        logger.info("Created new persistent device UID: \(deviceUID)")
        
        return deviceUID
    }
    
    enum EnrollmentState: Equatable {
        case notEnrolled
        case enrolling
        case enrolled(expiresAt: Date)
        case expired
        case failed(String)
        
        var isValid: Bool {
            switch self {
            case .enrolled(let expiresAt):
                return expiresAt > Date()
            default:
                return false
            }
        }
        
        var statusText: String {
            switch self {
            case .notEnrolled:
                return "Not Enrolled"
            case .enrolling:
                return "Enrolling..."
            case .enrolled(let expiresAt):
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                return "Valid until \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
            case .expired:
                return "Certificate Expired"
            case .failed(let message):
                return "Failed: \(message)"
            }
        }
    }
    
    struct CertificateInfo: Equatable, Codable {
        let subject: String
        let issuer: String
        let expiresAt: Date
        let serialNumber: String?
        
        var daysUntilExpiry: Int {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: Date(), to: expiresAt)
            return components.day ?? 0
        }
    }
    
    init() {
        checkExistingCertificate()
    }
    
    func checkExistingCertificate() {
        logger.info("Checking for existing TAK certificate...")
        
        do {
            if let identity = try getIdentity() {
                if let expiryTimestamp = UserDefaults.standard.object(forKey: certExpiryKey) as? TimeInterval {
                    let expiryDate = Date(timeIntervalSince1970: expiryTimestamp)
                    
                    if expiryDate > Date() {
                        logger.info("Valid certificate found, expires: \(expiryDate)")
                        enrollmentState = .enrolled(expiresAt: expiryDate)
                        
                        var cert: SecCertificate?
                        if SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let certificate = cert {
                            certificateInfo = try? extractCertificateInfo(certificate, expiresAt: expiryDate)
                        }
                    } else {
                        logger.warning("Certificate expired on: \(expiryDate)")
                        enrollmentState = .expired
                    }
                } else {
                    logger.info("Certificate found but no expiry info")
                    let defaultExpiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date.distantFuture
                    enrollmentState = .enrolled(expiresAt: defaultExpiry)
                }
                return
            }
        } catch {
            logger.debug("No existing certificate: \(error.localizedDescription)")
        }
        
        enrollmentState = .notEnrolled
    }
    
    func enroll(host: String, username: String, password: String) async throws {
        logger.info("Starting TAK Server enrollment for user: \(username)")
        logger.info("Note: Using legacy CSR-based enrollment. For newer TAK Servers, use enrollWithAPI() instead.")
        enrollmentState = .enrolling
        enrollmentProgress = "Downloading truststore certificate..."
        
        do {
            logger.info("Step 1: Downloading truststore certificate...")
            let truststoreCert = try await downloadTruststoreCertificate(host: host, username: username, password: password)
            try saveTruststoreCertificate(truststoreCert)
            logger.info("✓ Truststore certificate saved")
            
            enrollmentProgress = "Generating key pair..."
            logger.info("Step 2: Generating key pair...")
            let keyPair = try generateKeyPair()
            logger.info("✓ Key pair generated")
            
            enrollmentProgress = "Creating certificate signing request..."
            logger.info("Step 3: Creating CSR...")
            let csr = try createCSR(keyPair: keyPair, username: username)
            logger.info("✓ CSR created")
            
            enrollmentProgress = "Submitting enrollment request..."
            logger.info("Step 4: Submitting enrollment request...")
            let signedCert = try await submitEnrollmentRequest(
                host: host,
                username: username,
                password: password,
                csr: csr,
                truststoreCert: truststoreCert
            )
            logger.info("✓ Certificate signed by server")
            
            enrollmentProgress = "Saving certificate..."
            logger.info("Step 5: Parsing certificate...")
            let expiryDate = try extractExpiryDate(from: signedCert)
            logger.info("✓ Certificate expires: \(expiryDate)")
            
            logger.info("Step 6: Saving identity to keychain...")
            try saveIdentity(certificate: signedCert, privateKey: keyPair.privateKey)
            UserDefaults.standard.set(expiryDate.timeIntervalSince1970, forKey: certExpiryKey)
            logger.info("✓ Identity saved to keychain")
            
            if let secCert = SecCertificateCreateWithData(nil, signedCert as CFData) {
                certificateInfo = try extractCertificateInfo(secCert, expiresAt: expiryDate)
            }
            
            logger.info("✓ Enrollment successful!")
            enrollmentState = .enrolled(expiresAt: expiryDate)
            enrollmentProgress = "Enrollment complete"
            lastError = nil
            
        } catch {
            logger.error("Enrollment failed: \(error.localizedDescription)")
            enrollmentState = .failed(error.localizedDescription)
            enrollmentProgress = "Enrollment failed"
            lastError = error
            throw error
        }
    }
    
    // MARK: - Modern TAK Server API Enrollment
    
    /// Enroll using the official TAK Server API (recommended for TAK Server 4.0+)
    func enrollWithAPI(host: String, username: String, password: String, callsign: String? = nil) async throws {
        logger.info("Starting TAK Server API enrollment for user: \(username)")
        enrollmentState = .enrolling
        enrollmentProgress = "Downloading truststore..."
        
        do {
            // Step 1: Download truststore from /api/truststore
            logger.info("Step 1: Downloading truststore from /api/truststore...")
            let truststoreCert = try await downloadTruststoreViaAPI(host: host)
            try saveTruststoreCertificate(truststoreCert)
            logger.info("✓ Truststore downloaded and saved")
            
            enrollmentProgress = "Creating certificate package..."
            
            // Step 2: Create certificate package via API
            logger.info("Step 2: Creating certificate package via /api/certificate...")
            let deviceCallsign = callsign ?? username
            let certificatePackage = try await createCertificatePackage(
                host: host,
                username: username,
                password: password,
                callsign: deviceCallsign,
                truststoreCert: truststoreCert
            )
            
            enrollmentProgress = "Installing certificate..."
            logger.info("Step 3: Installing certificate package...")
            
            // Step 3: Extract and install certificate from package
            try await installCertificatePackage(certificatePackage)
            
            logger.info("✓ API enrollment successful!")
            enrollmentProgress = "Enrollment complete"
            lastError = nil
            
        } catch {
            logger.error("API enrollment failed: \(error.localizedDescription)")
            enrollmentState = .failed(error.localizedDescription)
            enrollmentProgress = "Enrollment failed"
            lastError = error
            throw error
        }
    }
    
    func unenroll() {
        logger.info("Unenrolling from TAK Server...")
        
        deleteTruststoreCertificate()
        deleteClientIdentity()
        UserDefaults.standard.removeObject(forKey: certExpiryKey)
        // Note: We keep the device UID even after unenrollment for consistency
        
        enrollmentState = .notEnrolled
        certificateInfo = nil
        logger.info("✓ Successfully unenrolled")
    }
    
    // MARK: - Public Device UID Access
    
    /// Get the persistent device UID used for TAK Server communication
    func getDeviceUID() -> String {
        return getOrCreateDeviceUID()
    }
    
    // MARK: - Manual Certificate Import
    
    func importP12Certificate(data: Data, password: String) throws {
        logger.info("Importing P12 certificate...")
        
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]
        
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        
        guard status == errSecSuccess else {
            logger.error("Failed to import P12, status: \(status)")
            if status == errSecAuthFailed {
                throw EnrollmentError.authenticationFailed
            }
            throw EnrollmentError.invalidCertificate
        }
        
        guard let items = rawItems as? [[String: Any]], !items.isEmpty else {
            logger.error("No items found in P12")
            throw EnrollmentError.invalidCertificate
        }
        
        guard let firstItem = items.first,
              let identity = firstItem[kSecImportItemIdentity as String] else {
            logger.error("No identity found in P12")
            throw EnrollmentError.invalidCertificate
        }
        
        let secIdentity = identity as! SecIdentity
        
        // Extract certificate from identity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(secIdentity, &certificate) == errSecSuccess,
              let cert = certificate else {
            throw EnrollmentError.invalidCertificate
        }
        
        // Extract expiry date
        let expiryDate = try extractExpiryDate(from: SecCertificateCopyData(cert) as Data)
        
        // Extract private key
        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(secIdentity, &privateKey) == errSecSuccess,
              let key = privateKey else {
            throw EnrollmentError.invalidPrivateKey
        }
        
        // Delete any existing identity first
        deleteClientIdentity()
        
        // Save the identity to keychain
        try saveIdentity(certificate: SecCertificateCopyData(cert) as Data, privateKey: key)
        UserDefaults.standard.set(expiryDate.timeIntervalSince1970, forKey: certExpiryKey)
        
        // Update state
        certificateInfo = try extractCertificateInfo(cert, expiresAt: expiryDate)
        enrollmentState = .enrolled(expiresAt: expiryDate)
        
        logger.info("✓ P12 certificate imported successfully")
    }
    
    func importCertificateAndKey(certData: Data, keyData: Data, password: String?) throws {
        logger.info("Importing certificate and private key...")
        
        // Parse certificate
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw EnrollmentError.invalidCertificate
        }
        
        let expiryDate = try extractExpiryDate(from: certData)
        
        // Parse private key (PEM format)
        var keyDataToImport = keyData
        
        // If it's PEM, extract the base64 part
        if let pemString = String(data: keyData, encoding: .utf8),
           pemString.contains("-----BEGIN") {
            let cleanKey = pemString
                .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let decodedKey = Data(base64Encoded: cleanKey) else {
                throw EnrollmentError.invalidPrivateKey
            }
            keyDataToImport = decodedKey
        }
        
        // Import the private key
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyDataToImport as CFData, keyAttributes as CFDictionary, &error) else {
            if let error = error {
                logger.error("Failed to create private key: \(error.takeRetainedValue().localizedDescription)")
            }
            throw EnrollmentError.invalidPrivateKey
        }
        
        // Delete any existing identity
        deleteClientIdentity()
        
        // Save to keychain
        try saveIdentity(certificate: certData, privateKey: privateKey)
        UserDefaults.standard.set(expiryDate.timeIntervalSince1970, forKey: certExpiryKey)
        
        // Update state
        certificateInfo = try extractCertificateInfo(certificate, expiresAt: expiryDate)
        enrollmentState = .enrolled(expiresAt: expiryDate)
        
        logger.info("✓ Certificate and key imported successfully")
    }
    
    func getIdentity() throws -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: clientIdentityLabel,
            kSecReturnRef as String: true
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw EnrollmentError.certificateNotFound
            }
            logger.error("Failed to get identity, status: \(status)")
            throw EnrollmentError.identityCreationFailed
        }
        
        guard let identity = result else {
            throw EnrollmentError.certificateNotFound
        }
        
        return (identity as! SecIdentity)
    }
    
    func getTruststoreCertificate() throws -> SecCertificate? {
        guard let certData = loadTruststoreCertificate() else {
            throw EnrollmentError.truststoreNotFound
        }
        
        guard let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw EnrollmentError.invalidCertificate
        }
        
        return cert
    }
    
    private func downloadTruststoreCertificate(host: String, username: String, password: String) async throws -> Data {
        // The CA certificate isn't available via API endpoints, so we extract it
        // from the TLS handshake when connecting to any HTTPS endpoint
        let urlString = "https://\(host):\(enrollmentPort)/Marti/api/tls/config"
        
        guard let url = URL(string: urlString) else {
            throw EnrollmentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        
        let credentials = "\(username):\(password)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        let delegate = TrustAllDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrollmentError.invalidResponse
        }
        
        logger.info("Config endpoint response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw EnrollmentError.httpError(httpResponse.statusCode)
        }
        
        // Extract the CA certificate from the TLS handshake
        guard let caCert = delegate.extractedCACertificate else {
            logger.error("Failed to extract CA certificate from TLS handshake")
            throw EnrollmentError.truststoreNotFound
        }
        
        let certData = SecCertificateCopyData(caCert) as Data
        logger.info("✓ Extracted CA certificate from TLS handshake (\(certData.count) bytes)")
        
        if let summary = SecCertificateCopySubjectSummary(caCert) as String? {
            logger.info("CA certificate subject: \(summary)")
        }
        
        return certData
    }
    
    private func extractCertificateInfo(_ cert: SecCertificate, expiresAt: Date) throws -> CertificateInfo {
        let subject = SecCertificateCopySubjectSummary(cert) as String? ?? "Unknown"
        let issuer = "TAK Server"
        
        var serialNumber: String? = nil
        if let certData = SecCertificateCopyData(cert) as Data? {
            serialNumber = certData.prefix(20).map { String(format: "%02x", $0) }.joined()
        }
        
        return CertificateInfo(subject: subject, issuer: issuer, expiresAt: expiresAt, serialNumber: serialNumber)
    }
    
    private func generateKeyPair() throws -> (privateKey: SecKey, publicKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error {
                throw error.takeRetainedValue()
            }
            throw EnrollmentError.keyGenerationFailed
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw EnrollmentError.keyGenerationFailed
        }
        
        return (privateKey, publicKey)
    }
    
    private func createCSR(keyPair: (privateKey: SecKey, publicKey: SecKey), username: String) throws -> Data {
        // TAK Server enrollment has multiple modes:
        // 1. Some versions want just the public key in PEM format (legacy)
        // 2. Modern versions want a proper PKCS#10 CSR
        // We'll try to create a proper CSR first, fallback to public key only
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(keyPair.publicKey, &error) as Data? else {
            if let error = error {
                throw error.takeRetainedValue()
            }
            throw EnrollmentError.csrCreationFailed
        }
        
        // Get persistent device UID to use in certificate CN
        let deviceUID = getOrCreateDeviceUID()
        
        // For TAK Server compatibility, we'll send the public key in PEM format
        // The server generates the certificate with its own fields
        let pemPublicKey = "-----BEGIN PUBLIC KEY-----\n"
            + publicKeyData.base64EncodedString(options: .lineLength64Characters)
            + "\n-----END PUBLIC KEY-----\n"
        
        guard let pemData = pemPublicKey.data(using: .utf8) else {
            throw EnrollmentError.csrCreationFailed
        }
        
        logger.info("Created public key PEM for device: \(deviceUID), user: \(username)")
        logger.info("Public key size: \(pemData.count) bytes")
        if let preview = String(data: pemData.prefix(100), encoding: .utf8) {
            logger.debug("Public key PEM (preview): \(preview)...")
        }
        
        return pemData
    }
    
    private func submitEnrollmentRequest(
        host: String,
        username: String,
        password: String,
        csr: Data,
        truststoreCert: Data
    ) async throws -> Data {
        // TAK Server has multiple enrollment endpoints depending on version:
        // - TAK Server 4.5+: /Marti/api/tls/signClient/v2 (recommended)
        // - TAK Server 4.0-4.4: /Marti/api/tls/signClient (legacy)
        // - TAK Server 3.x: May use different endpoints
        
        let deviceUID = getOrCreateDeviceUID()
        
        let endpoints: [(path: String, useClientUid: Bool, version: String)] = [
            // Try v2 first (modern TAK Server)
            ("/Marti/api/tls/signClient/v2", true, "4.5+"),
            // Then v1 (older but common)
            ("/Marti/api/tls/signClient", true, "4.0-4.4"),
            // Alternative enrollment endpoint
            ("/Marti/api/tls/enrollment", false, "legacy"),
        ]
        
        var lastError: Error?
        var attemptedVersions: [String] = []
        
        for endpoint in endpoints {
            do {
                logger.info("Trying TAK Server \(endpoint.version) enrollment: \(endpoint.path)")
                attemptedVersions.append(endpoint.version)
                
                var urlComponents = URLComponents()
                urlComponents.scheme = "https"
                urlComponents.host = host
                urlComponents.port = enrollmentPort
                urlComponents.path = endpoint.path
                
                if endpoint.useClientUid {
                    urlComponents.queryItems = [
                        URLQueryItem(name: "clientUid", value: deviceUID)
                    ]
                }
                
                guard let url = urlComponents.url else {
                    throw EnrollmentError.invalidURL
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 30
                request.httpBody = csr
                
                // TAK Server expects PEM-formatted public key or CSR
                request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                request.setValue("application/x-pem-file", forHTTPHeaderField: "Accept")
                
                let credentials = "\(username):\(password)"
                if let credentialsData = credentials.data(using: .utf8) {
                    let base64Credentials = credentialsData.base64EncodedString()
                    request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                }
                
                logger.debug("Submitting to: \(url.absoluteString)")
                logger.debug("Device UID: \(deviceUID)")
                
                guard let trustCert = SecCertificateCreateWithData(nil, truststoreCert as CFData) else {
                    throw EnrollmentError.invalidCertificate
                }
                
                let config = URLSessionConfiguration.ephemeral
                config.tlsMinimumSupportedProtocolVersion = .TLSv12
                config.tlsMaximumSupportedProtocolVersion = .TLSv13
                let delegate = TruststoreDelegate(trustCertificate: trustCert)
                let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EnrollmentError.invalidResponse
                }
                
                logger.info("Response status: \(httpResponse.statusCode) from \(endpoint.version)")
                logger.info("Response size: \(data.count) bytes")
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    logger.info("Content-Type: \(contentType)")
                }
                
                if httpResponse.statusCode == 200 {
                    // Success!
                    logger.info("✓ Enrollment successful with TAK Server \(endpoint.version)")
                    return try parseEnrollmentResponse(data, contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"))
                    
                } else if httpResponse.statusCode == 401 {
                    // Auth failed - don't try other endpoints
                    logger.error("❌ Authentication failed - check username and password")
                    throw EnrollmentError.authenticationFailed
                    
                } else if httpResponse.statusCode == 404 {
                    // Endpoint doesn't exist - try next version
                    logger.warning("Endpoint not found (404) - TAK Server may be version \(endpoint.version)")
                    lastError = EnrollmentError.httpError(httpResponse.statusCode)
                    continue
                    
                } else if httpResponse.statusCode == 500 {
                    // Server error - might work with different endpoint
                    logger.warning("Server error (500) on \(endpoint.version) - trying next...")
                    if let responseString = String(data: data, encoding: .utf8) {
                        logger.debug("Server response: \(String(responseString.prefix(200)))")
                    }
                    lastError = EnrollmentError.httpError(httpResponse.statusCode)
                    continue
                    
                } else if httpResponse.statusCode == 400 {
                    // Bad request - log details and try next
                    logger.warning("Bad request (400) on \(endpoint.version)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        logger.error("Server error: \(String(responseString.prefix(300)))")
                    }
                    lastError = EnrollmentError.csrCreationFailed
                    continue
                    
                } else {
                    logger.warning("Unexpected status \(httpResponse.statusCode) on \(endpoint.version)")
                    lastError = EnrollmentError.httpError(httpResponse.statusCode)
                    continue
                }
                
            } catch let error as EnrollmentError where error == .authenticationFailed {
                // Don't try other endpoints if auth failed
                throw error
            } catch {
                logger.warning("Failed with \(endpoint.version): \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        
        // All endpoints failed
        logger.error("❌ All enrollment endpoints failed")
        logger.error("Attempted TAK Server versions: \(attemptedVersions.joined(separator: ", "))")
        logger.error("Your TAK Server may be using a custom enrollment configuration")
        logger.error("Last error: \(lastError?.localizedDescription ?? "unknown")")
        throw lastError ?? EnrollmentError.httpError(500)
    }
    
    private func parseEnrollmentResponse(_ data: Data, contentType: String?) throws -> Data {
        
        logger.info("Enrollment successful, received certificate")
        
        // The response might be JSON containing the certificate
        // Try to parse it first, otherwise use raw data
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            logger.info("Response is JSON, keys: \(json.keys.joined(separator: ", "))")
            
            if let certString = json["certificate"] as? String ?? json["signedCert"] as? String ?? json["cert"] as? String {
                logger.info("Found certificate in JSON (length: \(certString.count))")
                // Remove PEM headers and decode base64
                let cleanCert = certString
                    .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                    .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let certData = Data(base64Encoded: cleanCert) {
                    logger.info("✓ Parsed certificate from JSON response (\(certData.count) bytes)")
                    return certData
                } else {
                    logger.warning("Failed to decode base64 certificate from JSON")
                }
            } else {
                logger.warning("No certificate field found in JSON response")
            }
        }
        
        // If JSON parsing failed, check if it's already a PEM certificate
        if let pemString = String(data: data, encoding: .utf8),
           pemString.contains("-----BEGIN CERTIFICATE-----") {
            logger.info("Response is PEM format")
            let cleanCert = pemString
                .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let certData = Data(base64Encoded: cleanCert) {
                logger.info("✓ Parsed PEM certificate (\(certData.count) bytes)")
                return certData
            } else {
                logger.warning("Failed to decode PEM certificate")
            }
        }
        
        // Try to validate as DER certificate directly
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            logger.info("✓ Response is valid DER certificate (\(data.count) bytes)")
            return data
        }
        
        // If we got here, we couldn't parse the certificate
        logger.error("Failed to parse certificate from response")
        if let responseString = String(data: data, encoding: .utf8) {
            logger.error("Raw response (first 500 chars): \(String(responseString.prefix(500)))")
        }
        throw EnrollmentError.invalidCertificate
    }
    
    private func extractExpiryDate(from certData: Data) throws -> Date {
        guard let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw EnrollmentError.invalidCertificate
        }
        
        if let summary = SecCertificateCopySubjectSummary(cert) as String? {
            logger.info("Certificate summary: \(summary)")
        }
        
        let derData = SecCertificateCopyData(cert) as Data
        
        if let expiryDate = try? parseX509Expiry(from: derData) {
            logger.info("Certificate expiry extracted: \(expiryDate)")
            return expiryDate
        }
        
        let expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date.distantFuture
        logger.warning("Could not extract expiry, using default: \(expiryDate)")
        return expiryDate
    }

    private func parseX509Expiry(from derData: Data) throws -> Date? {
        let bytes = [UInt8](derData)
        
        for i in 0..<bytes.count - 15 {
            if bytes[i] == 0x17 {
                let length = Int(bytes[i + 1])
                if length >= 13, i + 2 + length <= bytes.count {
                    let timeBytes = bytes[(i + 2)..<(i + 2 + length)]
                    if let timeString = String(bytes: timeBytes, encoding: .ascii) {
                        return parseUTCTime(timeString)
                    }
                }
            } else if bytes[i] == 0x18 {
                let length = Int(bytes[i + 1])
                if length >= 15, i + 2 + length <= bytes.count {
                    let timeBytes = bytes[(i + 2)..<(i + 2 + length)]
                    if let timeString = String(bytes: timeBytes, encoding: .ascii) {
                        return parseGeneralizedTime(timeString)
                    }
                }
            }
        }
        
        return nil
    }

    private func parseUTCTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: timeString)
    }

    private func parseGeneralizedTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: timeString)
    }
    
    private func saveIdentity(certificate: Data, privateKey: SecKey) throws {
        deleteClientIdentity()
        
        guard let secCert = SecCertificateCreateWithData(nil, certificate as CFData) else {
            throw EnrollmentError.invalidCertificate
        }
        
        let keyAttrs: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: clientIdentityLabel,
            kSecAttrApplicationTag as String: clientIdentityLabel.data(using: .utf8)!,
            kSecValueRef as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecReturnPersistentRef as String: true
        ]
        
        var keyRef: CFTypeRef?
        var status = SecItemAdd(keyAttrs as CFDictionary, &keyRef)
        guard status == errSecSuccess else {
            logger.error("Failed to save private key: \(status)")
            throw EnrollmentError.identityCreationFailed
        }
        logger.info("✓ Private key saved to keychain")
        
        let certAttrs: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: clientIdentityLabel,
            kSecValueRef as String: secCert,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        status = SecItemAdd(certAttrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save certificate: \(status)")
            throw EnrollmentError.identityCreationFailed
        }
        logger.info("✓ Certificate saved to keychain")
        
        let _ = try getIdentity()
        logger.info("✓ Identity verified and retrievable")
    }
    
    private func saveTruststoreCertificate(_ data: Data) throws {
        try KeychainManager.shared.save(data, forKey: truststoreCertKey)
    }
    
    private func loadTruststoreCertificate() -> Data? {
        return try? KeychainManager.shared.load(key: truststoreCertKey)
    }
    
    private func deleteTruststoreCertificate() {
        try? KeychainManager.shared.delete(key: truststoreCertKey)
    }
    
    private func deleteClientIdentity() {
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: clientIdentityLabel
        ]
        SecItemDelete(certQuery as CFDictionary)
        
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: clientIdentityLabel
        ]
        SecItemDelete(keyQuery as CFDictionary)
        
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: clientIdentityLabel
        ]
        SecItemDelete(identityQuery as CFDictionary)
        
        logger.info("✓ Deleted client identity from keychain")
    }
    
    // MARK: - Modern TAK Server API Methods
    
    private func downloadTruststoreViaAPI(host: String) async throws -> Data {
        // Download truststore from /api/truststore (no auth required)
        let urlString = "https://\(host)/api/truststore"
        
        guard let url = URL(string: urlString) else {
            throw EnrollmentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        let config = URLSessionConfiguration.ephemeral
        let delegate = TrustAllDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrollmentError.invalidResponse
        }
        
        logger.info("Truststore download status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw EnrollmentError.httpError(httpResponse.statusCode)
        }
        
        logger.info("✓ Downloaded truststore (\(data.count) bytes)")
        
        // The truststore might be in JKS format - extract the CA cert if needed
        if let caCert = delegate.extractedCACertificate {
            let certData = SecCertificateCopyData(caCert) as Data
            logger.info("✓ Extracted CA certificate from response")
            return certData
        }
        
        // If it's already a certificate, return it
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            return data
        }
        
        // Otherwise return the raw data (might be JKS - we'll handle that later)
        return data
    }
    
    private func createCertificatePackage(
        host: String,
        username: String,
        password: String,
        callsign: String,
        truststoreCert: Data
    ) async throws -> Data {
        // POST /api/certificate to create a certificate package
        let urlString = "https://\(host)/api/certificate"
        
        guard let url = URL(string: urlString) else {
            throw EnrollmentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Basic auth
        let credentials = "\(username):\(password)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        // Use persistent device UID
        let deviceUID = getOrCreateDeviceUID()
        let body: [String: String] = [
            "uid": deviceUID,
            "callsign": callsign
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        logger.info("Creating certificate package for callsign: \(callsign), uid: \(deviceUID)")
        
        guard let trustCert = SecCertificateCreateWithData(nil, truststoreCert as CFData) else {
            throw EnrollmentError.invalidCertificate
        }
        
        let config = URLSessionConfiguration.ephemeral
        let delegate = TruststoreDelegate(trustCertificate: trustCert)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrollmentError.invalidResponse
        }
        
        logger.info("Certificate package response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                logger.error("Server error: \(errorString)")
            }
            
            if httpResponse.statusCode == 401 {
                throw EnrollmentError.authenticationFailed
            }
            throw EnrollmentError.httpError(httpResponse.statusCode)
        }
        
        logger.info("✓ Received certificate package (\(data.count) bytes)")
        return data
    }
    
    private func installCertificatePackage(_ packageData: Data) async throws {
        // The package is typically a ZIP file containing:
        // - client certificate (.pem or .p12)
        // - private key (.key)
        // - truststore certificate
        // - preferences file
        
        logger.info("Installing certificate package...")
        
        // Try to parse as P12 first (most common format)
        do {
            // Try without password first
            try installP12FromData(packageData, password: "atakatak")
            logger.info("✓ Installed P12 with default password")
            return
        } catch {
            logger.debug("Not a P12 or wrong password, trying ZIP extraction...")
        }
        
        // Try to extract ZIP and find P12 file
        // For now, we'll just throw an error and ask for manual import
        logger.error("Certificate package format not supported - use manual P12 import")
        throw EnrollmentError.invalidCertificate
    }
    
    private func installP12FromData(_ data: Data, password: String) throws {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]
        
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        
        guard status == errSecSuccess else {
            throw EnrollmentError.invalidCertificate
        }
        
        guard let items = rawItems as? [[String: Any]], !items.isEmpty else {
            throw EnrollmentError.invalidCertificate
        }
        
        guard let firstItem = items.first,
              let identity = firstItem[kSecImportItemIdentity as String] else {
            throw EnrollmentError.invalidCertificate
        }
        
        let secIdentity = identity as! SecIdentity
        
        // Extract certificate
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(secIdentity, &certificate) == errSecSuccess,
              let cert = certificate else {
            throw EnrollmentError.invalidCertificate
        }
        
        let expiryDate = try extractExpiryDate(from: SecCertificateCopyData(cert) as Data)
        
        // Extract private key
        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(secIdentity, &privateKey) == errSecSuccess,
              let key = privateKey else {
            throw EnrollmentError.invalidPrivateKey
        }
        
        // Save to keychain
        deleteClientIdentity()
        try saveIdentity(certificate: SecCertificateCopyData(cert) as Data, privateKey: key)
        UserDefaults.standard.set(expiryDate.timeIntervalSince1970, forKey: certExpiryKey)
        
        // Update state
        certificateInfo = try extractCertificateInfo(cert, expiresAt: expiryDate)
        enrollmentState = .enrolled(expiresAt: expiryDate)
    }
}

enum EnrollmentError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case authenticationFailed
    case certificateNotFound
    case truststoreNotFound
    case invalidCertificate
    case invalidPrivateKey
    case identityCreationFailed
    case keyGenerationFailed
    case keyExportFailed
    case csrCreationFailed
    case networkError(Error)
    
    static func == (lhs: EnrollmentError, rhs: EnrollmentError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.authenticationFailed, .authenticationFailed),
             (.certificateNotFound, .certificateNotFound),
             (.truststoreNotFound, .truststoreNotFound),
             (.invalidCertificate, .invalidCertificate),
             (.invalidPrivateKey, .invalidPrivateKey),
             (.identityCreationFailed, .identityCreationFailed),
             (.keyGenerationFailed, .keyGenerationFailed),
             (.keyExportFailed, .keyExportFailed),
             (.csrCreationFailed, .csrCreationFailed):
            return true
        case (.httpError(let lhsCode), .httpError(let rhsCode)):
            return lhsCode == rhsCode
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid enrollment URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .authenticationFailed:
            return "Authentication failed - check username and password"
        case .certificateNotFound:
            return "Client certificate not found"
        case .truststoreNotFound:
            return "Truststore certificate not found"
        case .invalidCertificate:
            return "Invalid certificate format"
        case .invalidPrivateKey:
            return "Invalid private key"
        case .identityCreationFailed:
            return "Failed to create identity from certificate and key"
        case .keyGenerationFailed:
            return "Failed to generate key pair"
        case .keyExportFailed:
            return "Failed to export private key"
        case .csrCreationFailed:
            return "Failed to create certificate signing request"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

private class TrustAllDelegate: NSObject, URLSessionDelegate {
    private let logger = Logger(subsystem: "com.wardragon", category: "TAKEnrollment")
    var extractedCACertificate: SecCertificate?
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            
            // Extract the CA certificate from the certificate chain
            if let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                logger.info("Server certificate chain has \(certChain.count) certificates")
                
                // The last certificate in the chain is typically the root CA
                if let rootCert = certChain.last {
                    extractedCACertificate = rootCert
                    if let summary = SecCertificateCopySubjectSummary(rootCert) as String? {
                        logger.info("Extracted CA certificate: \(summary)")
                    }
                }
            }
            
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

private class TruststoreDelegate: NSObject, URLSessionDelegate {
    let trustCertificate: SecCertificate
    private let logger = Logger(subsystem: "com.wardragon", category: "TAKEnrollment")
    
    init(trustCertificate: SecCertificate) {
        self.trustCertificate = trustCertificate
    }
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            logger.debug("Not a server trust challenge, using default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        logger.info("Validating server certificate with truststore")
        
        // Set the truststore certificate as the anchor certificate (CA)
        SecTrustSetAnchorCertificates(serverTrust, [trustCertificate] as CFArray)
        
        // Allow certificates signed by this CA, even if they're not in the system trust store
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        if isValid {
            logger.info("✓ Server certificate validated successfully")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            if let error = error {
                logger.error("Server certificate validation failed: \(error.localizedDescription)")
            } else {
                logger.error("Server certificate validation failed with unknown error")
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
