import Foundation
import Security

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

// Certificate mode removed - only enrollment-based certificates are supported for TLS
// Non-TLS protocols (TCP/UDP) don't require certificates

struct TAKConfiguration: Codable, Equatable {
    var enabled: Bool
    var host: String
    var port: Int
    var `protocol`: TAKProtocol
    var enrollmentUsername: String?
    var enrollmentPassword: String?
    var tlsEnabled: Bool
    var skipVerification: Bool
    
    init(
        enabled: Bool = false,
        host: String = "",
        port: Int = 8089,
        protocol: TAKProtocol = .tls,
        enrollmentUsername: String? = nil,
        enrollmentPassword: String? = nil,
        tlsEnabled: Bool = true,
        skipVerification: Bool = false
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.protocol = `protocol`
        self.enrollmentUsername = enrollmentUsername
        self.enrollmentPassword = enrollmentPassword
        self.tlsEnabled = tlsEnabled
        self.skipVerification = skipVerification
    }
    
    var isValid: Bool {
        guard !host.isEmpty && port > 0 && port < 65536 else { return false }
        
        // For TLS, we need valid enrollment credentials (certificate will be obtained via enrollment)
        // For TCP/UDP, no certificate is needed
        if `protocol` == .tls {
            return enrollmentUsername?.isEmpty == false && enrollmentPassword?.isEmpty == false
        }
        
        return true
    }
    
    static func == (lhs: TAKConfiguration, rhs: TAKConfiguration) -> Bool {
        lhs.enabled == rhs.enabled &&
        lhs.host == rhs.host &&
        lhs.port == rhs.port &&
        lhs.protocol == rhs.protocol &&
        lhs.enrollmentUsername == rhs.enrollmentUsername &&
        lhs.enrollmentPassword == rhs.enrollmentPassword &&
        lhs.tlsEnabled == rhs.tlsEnabled &&
        lhs.skipVerification == rhs.skipVerification
    }
}

// P12 certificate support removed - use TAKEnrollmentManager for certificate management
