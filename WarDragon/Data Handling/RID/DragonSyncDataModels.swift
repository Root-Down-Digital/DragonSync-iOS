import Foundation

struct EnrichedDroneData: Codable {
    let basicId: String
    let mac: String
    let rssi: Int
    let latitude: Double
    let longitude: Double
    let altitude: Double
    
    let freq: Double?
    let seenBy: String?
    let observedAt: Double?
    let ridTimestamp: String?
    
    let rid: RIDEnrichment?
    
    let backendSource: String?
    let processingTimestamp: Double?
}

struct RIDEnrichment: Codable {
    let make: String?
    let model: String?
    let source: String?
    let lookupSuccess: Bool
}

struct KismetDevice: Codable {
    let key: String
    let macaddr: String
    let type: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let signal: Int?
    let channel: String?
    let firstSeen: Date
    let lastSeen: Date
}

struct LatticeReport: Codable {
    let timestamp: String
    let source: String
    let detectionType: String
    let location: LocationData
    let signal: SignalData
    let metadata: [String: String]
}

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

struct SignalData: Codable {
    let rssi: Int
    let frequency: Double?
    let mac: String?
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(Error)
    
    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}
