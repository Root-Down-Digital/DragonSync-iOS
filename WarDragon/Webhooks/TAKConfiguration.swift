//
//  TAKConfiguration.swift
//  WarDragon
//
//  TAK Server configuration model
//

import Foundation
import Security

/// TAK server connection protocol
enum TAKProtocol: String, Codable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
    case tls = "TLS"
    
    var icon: String {
        switch self {
        case .tcp: return "network"
        case .udp: return "arrow.up.arrow.down"
        case .tls: return "lock.shield"
        }
    }
    
    var defaultPort: Int {
        switch self {
        case .tcp: return 8087
        case .udp: return 8087
        case .tls: return 8089
        }
    }
}

/// TAK server configuration
struct TAKConfiguration: Codable, Equatable {
    var enabled: Bool
    var host: String
    var port: Int
    var protocol: TAKProtocol
    
    // TLS-specific settings
    var tlsEnabled: Bool
    var p12CertificateData: Data?
    var p12Password: String?
    var skipVerification: Bool  // UNSAFE: for testing only
    
    init(
        enabled: Bool = false,
        host: String = "",
        port: Int = 8089,
        protocol: TAKProtocol = .tls,
        tlsEnabled: Bool = true,
        p12CertificateData: Data? = nil,
        p12Password: String? = nil,
        skipVerification: Bool = false
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.protocol = `protocol`
        self.tlsEnabled = tlsEnabled
        self.p12CertificateData = p12CertificateData
        self.p12Password = p12Password
        self.skipVerification = skipVerification
    }
    
    var isValid: Bool {
        !host.isEmpty && port > 0 && port < 65536
    }
    
    static func == (lhs: TAKConfiguration, rhs: TAKConfiguration) -> Bool {
        lhs.enabled == rhs.enabled &&
        lhs.host == rhs.host &&
        lhs.port == rhs.port &&
        lhs.protocol == rhs.protocol &&
        lhs.tlsEnabled == rhs.tlsEnabled &&
        lhs.p12CertificateData == rhs.p12CertificateData &&
        lhs.p12Password == rhs.p12Password &&
        lhs.skipVerification == rhs.skipVerification
    }
}

// MARK: - Keychain Storage for Sensitive Data

extension TAKConfiguration {
    /// Save P12 certificate to keychain
    func saveP12ToKeychain(identifier: String = "com.wardragon.tak.p12") throws {
        guard let certData = p12CertificateData else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: certData
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to save P12 certificate to keychain"
            ])
        }
    }
    
    /// Load P12 certificate from keychain
    static func loadP12FromKeychain(identifier: String = "com.wardragon.tak.p12") -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    /// Delete P12 certificate from keychain
    static func deleteP12FromKeychain(identifier: String = "com.wardragon.tak.p12") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
