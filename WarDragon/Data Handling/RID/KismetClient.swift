import Foundation
import Combine
import os.log

@MainActor
class KismetClient: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var devices: [KismetDevice] = []
    
    private var configuration: KismetConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "KismetClient")
    private var session: URLSession
    private var pollTimer: Timer?
    
    struct KismetConfiguration: Codable, Equatable {
        var enabled: Bool
        var serverURL: String
        var apiKey: String?
        var pollInterval: TimeInterval
        var filterByType: [String]
        
        init(
            enabled: Bool = false,
            serverURL: String = "http://localhost:2501",
            apiKey: String? = nil,
            pollInterval: TimeInterval = 5.0,
            filterByType: [String] = ["Wi-Fi Device", "Bluetooth Device"]
        ) {
            self.enabled = enabled
            self.serverURL = serverURL
            self.apiKey = apiKey
            self.pollInterval = pollInterval
            self.filterByType = filterByType
        }
        
        var isValid: Bool {
            !serverURL.isEmpty && pollInterval > 0
        }
    }
    
    init(configuration: KismetConfiguration) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        pollTimer?.invalidate()
    }
    
    func start() {
        guard configuration.isValid else {
            logger.error("Invalid Kismet configuration")
            state = .failed(KismetError.invalidConfiguration)
            return
        }
        
        if let existingTimer = pollTimer {
            existingTimer.invalidate()
            pollTimer = nil
        }
        
        guard state == .disconnected || state == .failed(KismetError.connectionFailed) else {
            logger.debug("Already started")
            return
        }
        
        state = .connecting
        logger.info("Starting Kismet polling (interval: \(self.configuration.pollInterval)s)")
        
        Task {
            await poll()
            
            await MainActor.run {
                self.pollTimer = Timer.scheduledTimer(
                    withTimeInterval: self.configuration.pollInterval,
                    repeats: true
                ) { [weak self] _ in
                    Task { @MainActor in
                        await self?.poll()
                    }
                }
                
                if let timer = self.pollTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
                
                self.logger.info("Kismet polling timer started")
            }
        }
    }
    
    func stop() {
        if let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
        
        state = .disconnected
        logger.info("Stopped Kismet polling")
    }
    
    private func poll() async {
        guard var urlComponents = URLComponents(string: configuration.serverURL) else {
            logger.error("Invalid Kismet URL")
            state = .failed(KismetError.invalidURL)
            return
        }
        urlComponents.path = "/devices/views/all/devices.json"
        
        guard let url = urlComponents.url else {
            logger.error("Failed to construct Kismet URL")
            state = .failed(KismetError.invalidURL)
            return
        }
        
        var request = URLRequest(url: url)
        if let apiKey = configuration.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Kismet-API-Key")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw KismetError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw KismetError.httpError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            
            let kismetResponse = try decoder.decode([String: [KismetDevice]].self, from: data)
            
            var allDevices = kismetResponse.values.flatMap { $0 }
            
            if !configuration.filterByType.isEmpty {
                allDevices = allDevices.filter { device in
                    configuration.filterByType.contains(device.type)
                }
            }
            
            devices = allDevices
            state = .connected
            
            logger.debug("Polled \(allDevices.count) Kismet devices")
            
        } catch {
            logger.error("Kismet poll failed: \(error.localizedDescription)")
            state = .failed(error)
        }
    }
    
    func publish(device: CoTViewModel.CoTMessage) async throws {
        guard var urlComponents = URLComponents(string: configuration.serverURL) else {
            throw KismetError.invalidURL
        }
        urlComponents.path = "/devices/by-mac/\(device.mac ?? "")/set_tag.cmd"
        
        guard let url = urlComponents.url else {
            throw KismetError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let apiKey = configuration.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Kismet-API-Key")
        }
        
        let tagData: [String: Any] = [
            "tagname": "drone_detection",
            "tagvalue": device.uid,
            "tagdata": device.toDictionary()
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: tagData)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw KismetError.publishFailed
        }
        
        logger.debug("Published device \(device.uid) to Kismet")
    }
    
    func updateConfiguration(_ config: KismetConfiguration) {
        let wasRunning = state == .connected || state == .connecting
        
        if wasRunning {
            stop()
        }
        
        configuration = config
        
        if wasRunning && config.enabled {
            start()
        }
    }
}

enum KismetError: LocalizedError {
    case invalidConfiguration
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case connectionFailed
    case publishFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid Kismet configuration"
        case .invalidURL:
            return "Invalid Kismet URL"
        case .invalidResponse:
            return "Invalid response from Kismet"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .connectionFailed:
            return "Connection to Kismet failed"
        case .publishFailed:
            return "Failed to publish to Kismet"
        }
    }
}
