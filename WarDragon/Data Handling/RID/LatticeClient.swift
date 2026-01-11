import Foundation
import Combine
import os.log

@MainActor
class LatticeClient: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    
    private var configuration: LatticeConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "LatticeClient")
    private var session: URLSession
    
    struct LatticeConfiguration: Codable, Equatable {
        var enabled: Bool
        var serverURL: String
        var apiToken: String?
        var organizationID: String
        var siteID: String
        
        init(
            enabled: Bool = false,
            serverURL: String = "https://sandbox.lattice-das.com",
            apiToken: String? = nil,
            organizationID: String = "",
            siteID: String = ""
        ) {
            self.enabled = enabled
            self.serverURL = serverURL
            self.apiToken = apiToken
            self.organizationID = organizationID
            self.siteID = siteID
        }
        
        var isValid: Bool {
            !serverURL.isEmpty && !organizationID.isEmpty && !siteID.isEmpty
        }
    }
    
    init(configuration: LatticeConfiguration) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)
    }
    
    func publish(detection: CoTViewModel.CoTMessage) async throws {
        guard var urlComponents = URLComponents(string: configuration.serverURL) else {
            logger.error("Invalid Lattice server URL: \(self.configuration.serverURL)")
            throw LatticeError.invalidURL
        }
        
        urlComponents.path = "/api/v1/detections"
        
        guard let url = urlComponents.url else {
            logger.error("Failed to construct Lattice URL")
            throw LatticeError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        if let token = configuration.apiToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let latticeReport = createLatticeReport(from: detection)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(latticeReport)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        logger.debug("Publishing detection \(detection.uid) to Lattice at \(url.absoluteString)")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Lattice publish failed with status code: \(statusCode)")
            throw LatticeError.publishFailed
        }
        
        state = .connected
        logger.info("✅ Successfully published detection \(detection.uid) to Lattice")
    }
    
    private func createLatticeReport(from detection: CoTViewModel.CoTMessage) -> LatticeReport {
        LatticeReport(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            source: "wardragon-ios",
            detectionType: detection.isFPVDetection ? "fpv" : "drone",
            location: LocationData(
                latitude: Double(detection.lat) ?? 0,
                longitude: Double(detection.lon) ?? 0,
                altitude: Double(detection.alt) ?? 0
            ),
            signal: SignalData(
                rssi: detection.rssi ?? 0,
                frequency: detection.fpvFrequency.map(Double.init),
                mac: detection.mac
            ),
            metadata: [
                "uid": detection.uid,
                "manufacturer": detection.manufacturer ?? "Unknown",
                "id_type": detection.idType,
                "organization_id": configuration.organizationID,
                "site_id": configuration.siteID
            ]
        )
    }
    
    func updateConfiguration(_ config: LatticeConfiguration) {
        configuration = config
    }
}

enum LatticeError: LocalizedError {
    case invalidURL
    case publishFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Lattice URL"
        case .publishFailed:
            return "Failed to publish to Lattice"
        }
    }
}


