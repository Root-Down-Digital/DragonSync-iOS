//
//  CoTViewModel.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import Foundation
import Network
import UserNotifications
import CoreLocation


class CoTViewModel: ObservableObject {
    @Published var parsedMessages: [CoTMessage] = []
    @Published var droneSignatures: [DroneSignature] = []
    private let signatureGenerator = DroneSignatureGenerator()
    private var zmqHandler: ZMQHandler?
    private var cotListener: NWListener?
    private var statusListener: NWListener?
    private var multicastConnection: NWConnection?
    private let multicastGroup = Settings.shared.multicastHost
    private let cotPortMC = UInt16(Settings.shared.multicastPort)
    private let statusPortZMQ = UInt16(Settings.shared.zmqStatusPort)
    private let listenerQueue = DispatchQueue(label: "CoTListenerQueue")
    private var statusViewModel = StatusViewModel()
    public var isListeningCot = false
    
    
    struct CoTMessage: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var type: String
        var lat: String
        var lon: String
        var speed: String
        var vspeed: String
        var alt: String
        var height: String
        var pilotLat: String
        var pilotLon: String
        var description: String
        var uaType: DroneSignature.IdInfo.UAType
        
        // Basic ID fields
        var idType: String
        var mac: String?
        
        // Location extended fields
        var timeSpeed: String?
        var status: String?
        var direction: String?
        var altPressure: String?
        var heightType: String?
        var horizAcc: String?
        var vertAcc: String?
        var baroAcc: String?
        var speedAcc: String?
        var timestamp: String?
        
        // System Message fields
        var operatorAltGeo: String?
        var areaCount: String?
        var areaRadius: String?
        var areaCeiling: String?
        var areaFloor: String?
        var classification: String?
        
        // Self-ID fields
        var selfIdType: String?
        var selfIdId: String?
        
        // Auth Message fields
        var authType: String?
        var authPage: String?
        var authLength: String?
        var authTimestamp: String?
        var authData: String?
        
        var rawMessage: [String: Any]
        
        static func == (lhs: CoTViewModel.CoTMessage, rhs: CoTViewModel.CoTMessage) -> Bool {
            return lhs.uid == rhs.uid &&
            lhs.type == rhs.type &&
            lhs.lat == rhs.lat &&
            lhs.lon == rhs.lon &&
            lhs.speed == rhs.speed &&
            lhs.vspeed == rhs.vspeed &&
            lhs.alt == rhs.alt &&
            lhs.height == rhs.height &&
            lhs.pilotLat == rhs.pilotLat &&
            lhs.pilotLon == rhs.pilotLon &&
            lhs.description == rhs.description &&
            lhs.uaType == rhs.uaType &&
            lhs.idType == rhs.idType &&
            lhs.mac == rhs.mac &&
            lhs.timeSpeed == rhs.timeSpeed &&
            lhs.status == rhs.status &&
            lhs.direction == rhs.direction &&
            lhs.altPressure == rhs.altPressure &&
            lhs.heightType == rhs.heightType &&
            lhs.horizAcc == rhs.horizAcc &&
            lhs.vertAcc == rhs.vertAcc &&
            lhs.baroAcc == rhs.baroAcc &&
            lhs.speedAcc == rhs.speedAcc &&
            lhs.timestamp == rhs.timestamp &&
            lhs.operatorAltGeo == rhs.operatorAltGeo &&
            lhs.areaCount == rhs.areaCount &&
            lhs.areaRadius == rhs.areaRadius &&
            lhs.areaCeiling == rhs.areaCeiling &&
            lhs.areaFloor == rhs.areaFloor &&
            lhs.classification == rhs.classification &&
            lhs.selfIdType == rhs.selfIdType &&
            lhs.selfIdId == rhs.selfIdId &&
            lhs.authType == rhs.authType &&
            lhs.authPage == rhs.authPage &&
            lhs.authLength == rhs.authLength &&
            lhs.authTimestamp == rhs.authTimestamp &&
            lhs.authData == rhs.authData
        }
        
        var coordinate: CLLocationCoordinate2D? {
            guard let latDouble = Double(lat),
                  let lonDouble = Double(lon) else {
                print("Failed to convert lat: \(lat) or lon: \(lon) to Double")
                return nil
            }
            return CLLocationCoordinate2D(latitude: latDouble, longitude: lonDouble)
        }
    }
    
    init(statusViewModel: StatusViewModel) {
        self.statusViewModel = statusViewModel
        self.checkPermissions()
    }
    
    private func checkPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus != .authorized {
                self?.requestNotificationPermission()
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("Notification permission granted: \(granted)")
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func startListening() {
        // Prevent multiple starts
        guard !isListeningCot else { return }
        
        stopListening()  // Clean up any existing connections
        isListeningCot = true
        
        switch Settings.shared.connectionMode {
        case .multicast:
            startMulticastListening()
        case .zmq:
            startZMQListening()
        }
    }
    
    private func startMulticastListening() {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.requiredInterfaceType = .wifi
        
        do {
            cotListener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: cotPortMC))
            cotListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Multicast listener ready.")
                case .failed(let error):
                    print("Multicast listener failed: \(error)")
                case .cancelled:
                    print("Multicast listener cancelled.")
                default:
                    break
                }
            }
            
            cotListener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.listenerQueue ?? .main)
                self?.receiveMessages(from: connection)
            }
            
            cotListener?.start(queue: listenerQueue)
        } catch {
            print("Failed to create multicast listener: \(error)")
        }
    }
    
    private func startZMQListening() {
        zmqHandler = ZMQHandler()
        
        zmqHandler?.connect(
            host: Settings.shared.zmqHost,
            zmqTelemetryPort: UInt16(Settings.shared.zmqTelemetryPort),
            zmqStatusPort: UInt16(Settings.shared.zmqStatusPort),
            onTelemetry: { [weak self] message in
                if let data = message.data(using: .utf8) {
                    self?.processIncomingMessage(data)
                }
            },
            onStatus: { [weak self] message in
                if let data = message.data(using: .utf8) {
                    self?.processIncomingMessage(data)
                }
            }
        )
    }
    
    private func processIncomingMessage(_ data: Data) {
        guard let message = String(data: data, encoding: .utf8) else { return }
        
        // Incoming Message (JSON/XML) - Determine type and convert if needed
        let xmlData: Data
        if message.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "{") {
            // Handle JSON input
            if message.contains("system_stats") {
                // Status JSON
                guard let statusXML = self.zmqHandler?.convertStatusToXML(message),
                      let convertedData = statusXML.data(using: String.Encoding.utf8) else { return }
                xmlData = convertedData
            } else if let jsonData = message.data(using: .utf8),
                      let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      parsedJson["Basic ID"] != nil {
                // ESP32 Drone JSON
                guard let droneXML = self.zmqHandler?.convertTelemetryToXML(message),
                      let convertedData = droneXML.data(using: String.Encoding.utf8) else { return }
                xmlData = convertedData
            } else {
                print("Unrecognized JSON format")
                return
            }
        } else {
            // Already XML
            xmlData = data
        }
        
        // Parse XML and create appropriate message
        let parser = CoTMessageParser()
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = parser
        
        guard xmlParser.parse() else {
            print("Failed to parse XML")
            return
        }
        
        // Update UI with appropriate message type
        DispatchQueue.main.async {
            if message.contains("<remarks>CPU Usage:"),
               let statusMessage = parser.statusMessage {
                // Status message path
                self.updateStatusMessage(statusMessage)
            } else if let cotMessage = parser.cotMessage {
                // Drone message path
                self.updateMessage(cotMessage)
            }
        }
    }
    
    private func receiveMessages(from connection: NWConnection, isZMQ: Bool = false) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            defer {
                if !isComplete && (isZMQ ? self.zmqHandler?.isConnected == true : self.isListeningCot) {
                    self.receiveMessages(from: connection, isZMQ: isZMQ)
                } else {
                    connection.cancel()
                }
            }
            
            if let error = error {
                print("Error receiving data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, !data.isEmpty else {
                print("No data received.")
                return
            }
            
            if let message = String(data: data, encoding: .utf8) {
                //                print("Received data: \(message)")
                
                // Check for Status message first (has both status code type and remarks with CPU Usage)
                if message.contains("<remarks>CPU Usage:") {
                    print("Processing Status XML message")
                    let parser = XMLParser(data: data)
                    let cotParserDelegate = CoTMessageParser()
                    parser.delegate = cotParserDelegate
                    
                    if parser.parse(), let statusMessage = cotParserDelegate.statusMessage {
                        self.updateStatusMessage(statusMessage) // Use deduplication logic here
                    } else {
                        print("Failed to parse Status XML message.")
                    }
                    return
                }
                
                // If not a status message, check for ESP32 JSON
                if message.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "{"),
                   let jsonData = message.data(using: .utf8),
                   let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   parsedJson["Basic ID"] != nil {
                    print("Processing ESP32 Drone message")
                    let parser = CoTMessageParser()
                    if let parsedMessage = parser.parseESP32Message(parsedJson) {
                        DispatchQueue.main.async {
                            self.updateMessage(parsedMessage)
                        }
                    }
                    return
                }
                
                // Finally check for regular XML drone message
                if message.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "<") {
                    print("Processing XML Drone message")
                    let parser = XMLParser(data: data)
                    let cotParserDelegate = CoTMessageParser()
                    parser.delegate = cotParserDelegate
                    
                    if parser.parse(), let cotMessage = cotParserDelegate.cotMessage {
                        DispatchQueue.main.async {
                            self.updateMessage(cotMessage)
                        }
                    } else {
                        print("Failed to parse Drone XML message.")
                    }
                    return
                }
                
                print("Unrecognized message format.")
            }
        }
    }
    
    private func updateStatusMessage(_ message: StatusViewModel.StatusMessage) {
        DispatchQueue.main.async {
            if let index = self.statusViewModel.statusMessages.firstIndex(where: { $0.uid == message.uid }) {
                // Update existing status message
                self.statusViewModel.statusMessages[index] = message
                print("Updated existing status message: \(message.uid)")
            } else {
                // Add new status message
                self.statusViewModel.statusMessages.append(message)
                self.sendStatusNotification(for: message)
            }
        }
    }
    
    private func updateMessage(_ message: CoTMessage) {
        DispatchQueue.main.async {
            // Generate/update signature from raw message
            guard let signature = self.signatureGenerator.createSignature(from: message.rawMessage) else { return }
            
            // DEBUG - Check for existing signature match
            _ = self.droneSignatures.firstIndex { existing in
                let matchScore = self.signatureGenerator.matchSignatures(existing, signature)
                print("Checking for existing match, score: \(matchScore)")
                return matchScore > 0.42 // High confidence threshold
            }

            // Update signatures collection
            if let index = self.droneSignatures.firstIndex(where: { $0.primaryId.id == signature.primaryId.id }) {
                self.droneSignatures[index] = signature
                print("Updating existing CoT")
            } else {
                print("Added new CoT")
                self.droneSignatures.append(signature)
            }
            
            
            // Update messages collection
            if let index = self.parsedMessages.firstIndex(where: { $0.uid == message.uid }) {
                self.parsedMessages[index] = message
            } else {
                self.parsedMessages.append(message)
                self.sendNotification(for: message)
            }
        }
    }
    
    private func sendNotification(for message: CoTViewModel.CoTMessage) {
        let content = UNMutableNotificationContent()
        content.title = "New CoT Message"
        content.body = "From: \(message.uid)\nType: \(message.type)\nLocation: \(message.lat), \(message.lon)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendStatusNotification(for message: StatusViewModel.StatusMessage) {
        let content = UNMutableNotificationContent()
        content.title = "System Status"
        let memAvail = message.systemStats.memory.available
        let memTotal = message.systemStats.memory.total
        let memoryUsed = memTotal - memAvail
        let percentageUsed = (Double(memoryUsed) / Double(memTotal)) * 100
        content.body = "CPU: \(String(format: "%.0f", message.systemStats.cpuUsage))%\nMemory: \(String(format: "%.0f", percentageUsed))%\nTemp: \(message.systemStats.temperature)°C"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func stopListening() {
        guard isListeningCot else { return }
        
        isListeningCot = false
        
        // Clean up multicast if using it
        multicastConnection?.cancel()
        multicastConnection = nil
        cotListener?.cancel()
        statusListener?.cancel()
        cotListener = nil
        statusListener = nil
        
        // Properly disconnect ZMQ if using it
        if let zmqHandler = zmqHandler {
            zmqHandler.disconnect()
            self.zmqHandler = nil
        }
        
        print("All listeners stopped and connections cleaned up.")
    }
    
    func resetListener() {
        stopListening()
        parsedMessages.removeAll()
        droneSignatures.removeAll() // Test this line
        startListening()
    }
}
