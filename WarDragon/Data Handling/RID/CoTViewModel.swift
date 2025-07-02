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
import UIKit
import SwiftUI

class CoTViewModel: ObservableObject {
    @Published var parsedMessages: [CoTMessage] = []
    @Published var droneSignatures: [DroneSignature] = []
    @Published var randomMacIdHistory: [String: Set<String>] = [:]
    @Published var alertRings: [AlertRing] = []
    @Published private(set) var isReconnecting = false
    private var lastProcessTime: Date = Date()
    private let signatureGenerator = DroneSignatureGenerator()
    private var spectrumViewModel: SpectrumData.SpectrumViewModel?
    private var zmqHandler: ZMQHandler?
    private let backgroundManager = BackgroundManager.shared
    private var cotListener: NWListener?
    private var statusListener: NWListener?
    private var multicastConnection: NWConnection?
    private let multicastGroup = Settings.shared.multicastHost
    private let cotPortMC = UInt16(Settings.shared.multicastPort)
    private let statusPortZMQ = UInt16(Settings.shared.zmqStatusPort)
    private let listenerQueue = DispatchQueue(label: "CoTListenerQueue")
    private var statusViewModel = StatusViewModel()
    public var isListeningCot = false
    public var macIdHistory: [String: Set<String>] = [:]
    public var macProcessing: [String: Bool] = [:]
    private var lastNotificationTime: Date?
    private var macToCAA: [String: String] = [:]
    private var backgroundMaintenanceTimer: Timer?
    private var macToHomeLoc: [String: (lat: Double, lon: Double)] = [:]
    private var currentMessageFormat: ZMQHandler.MessageFormat {
        return zmqHandler?.messageFormat ?? .bluetooth
    }
    
    struct AlertRing: Identifiable {
        let id = UUID()
        let centerCoordinate: CLLocationCoordinate2D
        let radius: Double
        let droneId: String
        let rssi: Int
    }
    
    struct SignalSource: Hashable {
        let mac: String
        let rssi: Int
        let type: SignalType
        let timestamp: Date
        
        enum SignalType: String, Hashable {
            case bluetooth
            case wifi
            case sdr
            case unknown
        }
        
        init?(mac: String, rssi: Int, type: SignalType, timestamp: Date) {
            guard rssi != 0 else { return nil }
            self.mac = mac
            self.rssi = rssi
            self.type = type
            self.timestamp = timestamp
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(mac)
            hasher.combine(type)
        }
        
        static func == (lhs: SignalSource, rhs: SignalSource) -> Bool {
            return lhs.mac == rhs.mac && lhs.type == rhs.type
        }
    }
    
    struct CoTMessage: Identifiable, Equatable {
        var id: String { uid }
        var caaRegistration: String?
        var uid: String
        var type: String
        
        // Basic location and movement
        var lat: String
        var lon: String
        var homeLat: String
        var homeLon: String
        var speed: String
        var vspeed: String
        var alt: String
        var height: String?
        var pilotLat: String
        var pilotLon: String
        var description: String
        var selfIDText: String
        var uaType: DroneSignature.IdInfo.UAType
        
        // Basic ID fields with protocol info
        var idType: String
        var protocolVersion: String?
        var mac: String?
        var rssi: Int?
        var manufacturer: String?
        var signalSources: [SignalSource] = []
        
        // Location/Vector Message fields
        var location_protocol: String?
        var op_status: String?
        var height_type: String?
        var ew_dir_segment: String?
        var speed_multiplier: String?
        var direction: String?
        var geodetic_altitude: Double?
        var vertical_accuracy: String?
        var horizontal_accuracy: String?
        var baro_accuracy: String?
        var speed_accuracy: String?
        var timestamp: String?
        var timestamp_accuracy: String?
        
        // Multicast CoT specific fields
        var time: String?
        var start: String?
        var stale: String?
        var how: String?
        var ce: String?  // Circular error
        var le: String?  // Linear error
        var hae: String? // Height above ellipsoid
        
        // BT/WiFi transmission fields from ZMQ
        var aux_rssi: Int?
        var channel: Int?
        var phy: Int?
        var aa: Int?
        var adv_mode: String?
        var adv_mac: String?
        var did: Int?
        var sid: Int?
        
        // Extended Location fields
        var timeSpeed: String?
        var status: String?
        var opStatus: String?
        var altPressure: String?
        var heightType: String?
        var horizAcc: String?
        var vertAcc: String?
        var baroAcc: String?
        var speedAcc: String?
        var timestampAccuracy: String?
        
        // ZMQ Operator & System fields
        var operator_id: String?
        var operator_id_type: String?
        var classification_type: String?
        var operator_location_type: String?
        var area_count: String?
        var area_radius: String?
        var area_ceiling: String?
        var area_floor: String?
        var advMode: String?
        var txAdd: Int?
        var rxAdd: Int?
        var adLength: Int?
        var accessAddress: Int?
        
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
        
        // Spoof detection
        var isSpoofed: Bool = false
        var spoofingDetails: DroneSignatureGenerator.SpoofDetectionResult?
        
        var index: String?
        var runtime: String?
        
        //CoT Message Tracks
        var trackCourse: String?
        var trackSpeed: String?
        
        var hasTrackInfo: Bool {
            return trackCourse != nil || trackSpeed != nil ||
            (direction != nil && direction != "0")
        }
        
        var trackSpeedFormatted: String? {
            if let speed = trackSpeed {
                return "\(speed) m/s"
            } else if !self.speed.isEmpty && self.speed != "0.0" {
                return "\(self.speed) m/s"
            }
            return nil
        }
        
        public var headingDeg: Double {
            // First try to get heading from track data
            if let rawTrack = trackSpeed,
               rawTrack != "0.0",
               let deg = Double(rawTrack.replacingOccurrences(of: "°", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)) {
                return (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            }
              
              // If no track data, calculate from last two known positions
              guard let encounter = DroneStorageManager.shared.encounters[uid],
                    encounter.flightPath.count >= 2,
                    let currentPoint = encounter.flightPath.last,
                    let previousPoint = encounter.flightPath.dropLast().last else {
                  return 0.0
              }
              
              // Calculate heading using coordinates
              let lat1 = previousPoint.latitude * .pi / 180
              let lon1 = previousPoint.longitude * .pi / 180
              let lat2 = currentPoint.latitude * .pi / 180
              let lon2 = currentPoint.longitude * .pi / 180
              
              let dLon = lon2 - lon1
              let y = sin(dLon) * cos(lat2)
              let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
              var heading = atan2(y, x) * 180 / .pi
              heading = (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
              
              return heading
        }


        // Stale timer
        var lastUpdated: Date = Date()
        
        var isActive: Bool {
            return Date().timeIntervalSince(lastUpdated) <= 300  // 5 minutes standard
        }
        
        var isStale: Bool {
            guard let staleTime = self.stale else { return true }
            let formatter = ISO8601DateFormatter()
            guard let staleDate = formatter.date(from: staleTime) else { return true }
            return Date() > staleDate
        }
        
        var statusColor: Color {
            let timeSince = Date().timeIntervalSince(lastUpdated)
            if timeSince <= 30 {
                return .green  // Recently active (within 30s)
            } else if timeSince <= 300 {
                return .yellow // Warning state (30s - 5min)
            } else {
                return .red    // Stale (over 5min)
            }
        }
        
        var statusDescription: String {
            // Using times from CoT 4.0 Spec, Section 2.2.2.2
            let timeSince = Date().timeIntervalSince(lastUpdated)
            if timeSince <= 90 {
                return "Active"
            } else if timeSince <= 120 {
                return "Aging"
            } else {
                return "Stale"
            }
        }
        
        // Data store
        func saveToStorage() {
            DroneStorageManager.shared.saveEncounter(self)
        }
        
        var formattedAltitude: String? {
            if let altValue = Double(alt), altValue != 0 {
                return String(format: "%.1f m MSL", altValue)
            }
            return nil
        }
        
        var formattedHeight: String? {
            if let heightValue = Double(height ?? ""), heightValue != 0 {
                return String(format: "%.1f m AGL", heightValue)
            }
            return nil
        }
        
        var rawMessage: [String: Any]
        
        static func == (lhs: CoTViewModel.CoTMessage, rhs: CoTViewModel.CoTMessage) -> Bool {
            return lhs.uid == rhs.uid &&
            lhs.caaRegistration == rhs.caaRegistration &&
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
            lhs.rssi == rhs.rssi &&
            lhs.location_protocol == rhs.location_protocol &&
            lhs.op_status == rhs.op_status &&
            lhs.height_type == rhs.height_type &&
            lhs.speed_multiplier == rhs.speed_multiplier &&
            lhs.direction == rhs.direction &&
            lhs.vertical_accuracy == rhs.vertical_accuracy &&
            lhs.horizontal_accuracy == rhs.horizontal_accuracy &&
            lhs.baro_accuracy == rhs.baro_accuracy &&
            lhs.speed_accuracy == rhs.speed_accuracy &&
            lhs.timestamp == rhs.timestamp &&
            lhs.timestamp_accuracy == rhs.timestamp_accuracy &&
            lhs.operator_id == rhs.operator_id &&
            lhs.operator_id_type == rhs.operator_id_type &&
            lhs.aux_rssi == rhs.aux_rssi &&
            lhs.channel == rhs.channel &&
            lhs.phy == rhs.phy &&
            lhs.aa == rhs.aa &&
            lhs.adv_mode == rhs.adv_mode &&
            lhs.adv_mac == rhs.adv_mac &&
            lhs.did == rhs.did &&
            lhs.sid == rhs.sid &&
            lhs.type == rhs.type &&
            lhs.timeSpeed == rhs.timeSpeed &&
            lhs.status == rhs.status &&
            lhs.altPressure == rhs.altPressure &&
            lhs.heightType == rhs.heightType &&
            lhs.horizAcc == rhs.horizAcc &&
            lhs.vertAcc == rhs.vertAcc &&
            lhs.baroAcc == rhs.baroAcc &&
            lhs.speedAcc == rhs.speedAcc &&
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
            lhs.authData == rhs.authData &&
            lhs.isSpoofed == rhs.isSpoofed &&
            lhs.spoofingDetails?.isSpoofed == rhs.spoofingDetails?.isSpoofed &&
            lhs.spoofingDetails?.confidence == rhs.spoofingDetails?.confidence &&
            lhs.accessAddress == rhs.accessAddress &&
            lhs.mac == rhs.mac &&
            lhs.rssi == rhs.rssi &&
            lhs.lat == rhs.lat &&
            lhs.lon == rhs.lon &&
            lhs.speed == rhs.speed &&
            lhs.vspeed == rhs.vspeed &&
            lhs.alt == rhs.alt &&
            lhs.height == rhs.height &&
            lhs.op_status == rhs.op_status &&
            lhs.height_type == rhs.height_type &&
            lhs.direction == rhs.direction &&
            lhs.geodetic_altitude == rhs.geodetic_altitude
        }
        
        var coordinate: CLLocationCoordinate2D? {
            guard let latDouble = Double(lat),
                  let lonDouble = Double(lon) else {
                print("Failed to convert lat: \(lat) or lon: \(lon) to Double")
                return nil
            }
            return CLLocationCoordinate2D(latitude: latDouble, longitude: lonDouble)
        }
        
        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "uid": self.uid,
                "id": self.id,
                "type": self.type,
                "lat": self.lat,
                "lon": self.lon,
                "latitude": self.lat,
                "longitude": self.lon,
                "speed": self.speed,
                "vspeed": self.vspeed,
                "alt": self.alt,
                "pilotLat": self.pilotLat,
                "pilotLon": self.pilotLon,
                "description": self.description,
                "selfIDText": self.selfIDText,
                "uaType": self.uaType,
                "idType": self.idType,
                "isSpoofed": self.isSpoofed,
                "rssi": self.rssi ?? 0.0,
                "mac": self.mac ?? "",
                "manufacturer": self.manufacturer ?? "",
                "op_status": self.op_status ?? "",
                "ew_dir_segment": self.ew_dir_segment ?? "",
                "direction": self.direction ?? "",
                "geodetic_altitude": self.geodetic_altitude ?? 0.0
            ]
            
            // Include optional fields if they exist
            dict["id"] = self.id
            dict["uid"] = self.uid
            dict["height"] = self.height
            dict["protocolVersion"] = self.protocolVersion
            dict["geodetic_altitude"] = self.geodetic_altitude
            dict["mac"] = self.mac
            dict["rssi"] = self.rssi
            dict["rssi"] = self.rssi
            dict["manufacturer"] = self.manufacturer
            dict["op_status"] = self.op_status
            dict["direction"] = self.direction
            dict["ew_dir_segment"] = self.ew_dir_segment
            dict["location_protocol"] = self.location_protocol
            dict["op_status"] = self.op_status
            dict["height_type"] = self.height_type
            dict["direction"] = self.direction
            dict["time"] = self.time
            dict["start"] = self.start
            dict["stale"] = self.stale
            dict["how"] = self.how
            dict["ce"] = self.ce
            dict["le"] = self.le
            dict["hae"] = self.hae
            dict["aux_rssi"] = self.aux_rssi
            dict["channel"] = self.channel
            dict["phy"] = self.phy
            dict["aa"] = self.aa
            dict["adv_mode"] = self.adv_mode
            dict["adv_mac"] = self.adv_mac
            dict["operator_id"] = self.operator_id
            dict["classification_type"] = self.classification_type
            dict["area_radius"] = self.area_radius
            dict["area_ceiling"] = self.area_ceiling
            dict["area_floor"] = self.area_floor
            
            return dict
        }
    }
    
    init(statusViewModel: StatusViewModel, spectrumViewModel: SpectrumData.SpectrumViewModel? = nil) {
        self.statusViewModel = statusViewModel
        self.spectrumViewModel = spectrumViewModel
        self.checkPermissions()
        
        // Register for application lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        // Also add observer for refreshing connections
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshConnections),
            name: Notification.Name("RefreshNetworkConnections"),
            object: nil
        )
    }
    
    
    @objc private func handleAppDidEnterBackground() {
        // Prepare connections for background mode
        prepareForBackgroundExpiry()
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Resume normal connection behavior
        resumeFromBackground()
    }
    
    @objc private func refreshConnections() {
        // Only refresh if we're actively listening
        if isListeningCot && !isReconnecting {
            // Briefly reconnect to keep connections alive
            performBackgroundRefresh()
        }
    }
    
    private func performBackgroundRefresh() {
        // Quick reconnect to refresh connections
        if isListeningCot && !isReconnecting {
            isReconnecting = true
            
            // Brief reconnection to keep connections active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                
                switch Settings.shared.connectionMode {
                case .multicast:
                    self.multicastConnection?.cancel()
                    self.multicastConnection = nil
                    self.startMulticastListening()
                case .zmq:
                    self.zmqHandler?.disconnect()
                    self.zmqHandler = nil
                    self.startZMQListening()
                }
                
                // Reset reconnecting flag
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.isReconnecting = false
                }
            }
        }
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
        // Prevent multiple starts or starts during reconnection
        guard !isListeningCot && !isReconnecting else { return }
        
        // Clean up any existing connections
        stopListening()
        isListeningCot = true
        
        // Setup background processing notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkConnections),
            name: Notification.Name("RefreshNetworkConnections"),
            object: nil
        )
        
        // Start the appropriate connection type
        switch Settings.shared.connectionMode {
        case .multicast:
            startMulticastListening()
        case .zmq:
            startZMQListening()
        }
        
        // Start background processing if enabled
        if Settings.shared.enableBackgroundDetection {
            backgroundManager.startBackgroundProcessing()
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
    
    private func isDeviceBlocked(_ message: CoTMessage) -> Bool {
        let droneId = message.uid.hasPrefix("drone-") ? message.uid : "drone-\(message.uid)"
        
        // Check both the original UID and the formatted drone ID
        let possibleIds = [
            message.uid,
            droneId,
            message.uid.replacingOccurrences(of: "drone-", with: "")
        ]
        
        // Check each possible ID format
        for id in possibleIds {
            if let encounter = DroneStorageManager.shared.encounters[id],
               encounter.metadata["doNotTrack"] == "true" {
                print("⛔️ BLOCKED message with ID \(id) - marked as do not track")
                return true
            }
            
            // Also check the "drone-" prefixed version
            let droneFormatId = id.hasPrefix("drone-") ? id : "drone-\(id)"
            if let encounter = DroneStorageManager.shared.encounters[droneFormatId],
               encounter.metadata["doNotTrack"] == "true" {
                print("⛔️ BLOCKED message with drone ID \(droneFormatId) - marked as do not track")
                return true
            }
        }
        
        return false
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
                // Drone JSON
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
            print("Failed to parse XML: \(xmlData)")
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
            
            // Also bail if throttled
            let now = Date()
            if now.timeIntervalSince(self.lastProcessTime) < Settings.shared.messageProcessingIntervalSeconds {
                // Skip this message if we're processing too fast
                print("Processing too fast for set interval, throttling...")
                return
            }
            self.lastProcessTime = now
            
            
            if let message = String(data: data, encoding: .utf8) {
                print("DEBUG - Received data: \(message)")
                
                // Check for Status message first (has both status code type and remarks with CPU Usage)
                if message.contains("<remarks>CPU Usage:") {
                    print("Processing Status XML message")
                    let parser = XMLParser(data: data)
                    let cotParserDelegate = CoTMessageParser()
                    parser.delegate = cotParserDelegate
                    
                    if parser.parse(), let statusMessage = cotParserDelegate.statusMessage {
                        self.updateStatusMessage(statusMessage)
                    } else {
                        print("Failed to parse Status XML message.")
                    }
                    return
                }
                
                // If not a status message, check for JSON
                if message.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "{"),
                   let jsonData = message.data(using: .utf8),
                   let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   parsedJson["Basic ID"] != nil {
                    print("Processing json message: \(message)")
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
                    //                    print("Processing XML Drone message: \(message)")
                    let parser = XMLParser(data: data)
                    let cotParserDelegate = CoTMessageParser()
                    parser.delegate = cotParserDelegate
                    
                    if parser.parse(), let cotMessage = cotParserDelegate.cotMessage {
                        // Set message format based on Index/Runtime presence
                        if cotMessage.index != "0" || cotMessage.runtime != "0" {
                            self.zmqHandler?.messageFormat = .wifi
                        } else {
                            self.zmqHandler?.messageFormat = .bluetooth
                        }
                        
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
            self.statusViewModel.updateExistingStatusMessage(message)
        }
    }
    
    // Check connection status without heavy processing
    func checkConnectionStatus() {
        // Just verify that connections are still responsive
        if !isListeningCot && Settings.shared.isListening {
            reconnectIfNeeded()
        }
    }
    
    func prepareForBackgroundExpiry() {
        // Record state for potential resumption
        let wasListening = isListeningCot
        
        // Log background transition
        print("WarDragon preparing for background expiry...")
        
        // Set a flag to indicate reduced processing mode
        isReconnecting = true
        
        // For ZMQ connections, reduce activity but maintain connection
        if let zmqHandler = self.zmqHandler {
            // Don't fully disconnect ZMQ, just reduce activity
            // Save current message format for restoration later
            let currentFormat = zmqHandler.messageFormat
            
            if zmqHandler.isConnected {
                print("Reducing ZMQ activity for background mode")
                zmqHandler.setBackgroundMode(true)
            }
        }
        
        // For multicast connections, we'll keep them open but reduce processing rate
        if multicastConnection != nil {
            print("Reducing multicast processing for background mode")
        }
        
        objectWillChange.send()
        
        if wasListening {
            // Only start background processing if not already running and invalidate old timers
            if !BackgroundManager.shared.isBackgroundModeActive {
                BackgroundManager.shared.startBackgroundProcessing()
            }
            backgroundMaintenanceTimer?.invalidate()
            
            // Set a timer to periodically check status
            backgroundMaintenanceTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] timer in
                guard let self = self, self.isListeningCot else {
                    timer.invalidate()
                    self?.backgroundMaintenanceTimer = nil
                    return
                }
                print("Background maintenance check: \(Date())")
            }
        }
        print("WarDragon background preparation complete")
    }
    
    func resumeFromBackground() {
        print("WarDragon resuming from background...")
        
        // Clear the reconnecting flag
        isReconnecting = false
        
        // Restore ZMQ to normal operation if it was modified
        if let zmqHandler = self.zmqHandler, zmqHandler.isConnected {
            print("Restoring ZMQ normal activity")
            zmqHandler.setBackgroundMode(false)
        }
        
        // Stop background task management
        BackgroundManager.shared.stopBackgroundProcessing()
        
        // Force an update to UI
        objectWillChange.send()
        
        print("WarDragon successfully resumed from background")
    }
    
    // Reconnect BG if we need to
    func reconnectIfNeeded() {
        if !isReconnecting && Settings.shared.isListening && !isListeningCot {
            isReconnecting = true
            
            // Clean up any existing connections
            stopListening()
            
            // Wait a moment before reconnecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startListening()
                self.isReconnecting = false
            }
        }
    }
    
    private func updateMessage(_ message: CoTMessage) {
        
        // Uncomment this to disallow zero-coordinate entries
        //        guard let coordinate = message.coordinate,
        //              coordinate.latitude != 0 || coordinate.longitude != 0 else {
        //            return
        //        }
        
        
        if isDeviceBlocked(message) {
            print("UNTRACKED: Dropping message for \(message.uid)")
            return
        }
        
        // Extract the numerical ID from messages like "pilot-107", "home-107", "drone-107"
        let extractedId = extractNumericId(from: message.uid)
        
        // Check if this is a pilot or home message that should be associated with a drone
        if message.uid.hasPrefix("pilot-") {
            updatePilotLocation(for: extractedId, message: message)
            return // Don't create lone message for pilot or home
        }
        
        if message.uid.hasPrefix("home-") {
            updateHomeLocation(for: extractedId, message: message)
            return
        }
        
        // Early exit for untracked devices
        let droneId = message.uid.hasPrefix("drone-") ? message.uid : "drone-\(message.uid)"
  
        
        DispatchQueue.main.async {
            
            let droneId = message.uid.hasPrefix("drone-") ? message.uid : "drone-\(message.uid)"
            var mac: String? = nil
            if let basicIdMac = (message.rawMessage["Basic ID"] as? [String: Any])?["MAC"] as? String {
                mac = basicIdMac
            } else if let auxAdvMac = (message.rawMessage["AUX_ADV_IND"] as? [String: Any])?["addr"] as? String {
                mac = auxAdvMac
            } else {
                mac = message.mac
            }
            
            let trackSpeed = message.trackSpeed ?? "0.0"
            let trackCourse = message.trackCourse ?? "0.0"
            
            // Prepare updated message
            var updatedMessage = message
            updatedMessage.uid = droneId
            
            // CoT XML Track data
            updatedMessage.trackSpeed = trackSpeed
            updatedMessage.trackCourse = trackCourse
            
            // Update alert ring if zero coordinate drone
            self.updateAlertRing(for: message)
            
            // Determine signal type and update sources
            let signalType = self.determineSignalType(message: message, mac: mac, rssi: updatedMessage.rssi, updatedMessage: &updatedMessage)
            
            // Handle CAA and location mapping
            if let mac = mac, !mac.isEmpty {
                // Update the MAC-to-CAA mapping without changing the primary ID
                if message.idType.contains("CAA") {
                    if let mac = message.mac {
                        // Find existing message with same MAC and update its CAA registration
                        if let existingIndex = self.parsedMessages.firstIndex(where: { $0.mac == mac }) {
                            var existingMessage = self.parsedMessages[existingIndex]
                            existingMessage.caaRegistration = message.caaRegistration ?? message.id
                            // Keep the original ID type if it's a serial number
                            if existingMessage.idType.contains("Serial") {
                                // Don't overwrite serial number ID type with CAA
                                existingMessage.idType = existingMessage.idType
                            } else {
                                existingMessage.idType = "CAA Assigned Registration ID"
                            }
                            self.parsedMessages[existingIndex] = existingMessage
                            print("Updated CAA registration for existing drone with MAC: \(mac)")
                        }
                    }
                    // Don't process CAA as a standalone message
                    return
                }
            }
            
            // Generate signature and handle spoof detection
            guard let signature = self.signatureGenerator.createSignature(from: updatedMessage.toDictionary()) else {
                if message.idType.contains("CAA") {
                    self.handleCAAMessage(updatedMessage)
                }
                return
            }
            
            // Update tracking data
            self.updateDroneSignaturesAndEncounters(signature, message: updatedMessage)
            self.updateMACHistory(droneId: droneId, mac: mac)
            
            // Spoof detection
            if Settings.shared.spoofDetectionEnabled,
               let monitorStatus = self.statusViewModel.statusMessages.last {
                if let spoofResult = self.signatureGenerator.detectSpoof(signature, fromMonitor: monitorStatus) {
                    updatedMessage.isSpoofed = spoofResult.isSpoofed
                    updatedMessage.spoofingDetails = spoofResult
                }
                
                let monitorLoc = CLLocation(
                    latitude: monitorStatus.gpsData.latitude,
                    longitude: monitorStatus.gpsData.longitude
                )
                self.signatureGenerator.updateMonitorLocation(monitorLoc)
            }
            
            // Final update
            self.updateParsedMessages(updatedMessage: updatedMessage, signature: signature)
        }
    }
    
    private func extractNumericId(from uid: String) -> String {
        if let match = uid.firstMatch(of: /.*-(\d+)/) {
            return String(match.1)
        }
        return uid
    }
    
    private func updatePilotLocation(for droneId: String, message: CoTMessage) {
        let targetUid = "drone-\(droneId)"
        
        // Find existing drone message and update pilot location
        if let index = parsedMessages.firstIndex(where: { $0.uid == targetUid }) {
            var updatedMessage = parsedMessages[index]
            updatedMessage.pilotLat = message.lat
            updatedMessage.pilotLon = message.lon
            parsedMessages[index] = updatedMessage
            
            // Also update in storage
            DroneStorageManager.shared.updatePilotLocation(
                droneId: targetUid,
                latitude: Double(message.lat) ?? 0.0,
                longitude: Double(message.lon) ?? 0.0
            )
        }
    }
    
    private func updateHomeLocation(for droneId: String, message: CoTMessage) {
        let targetUid = "drone-\(droneId)"
        
        // Find existing drone message and update home location
        if let index = parsedMessages.firstIndex(where: { $0.uid == targetUid }) {
            var updatedMessage = parsedMessages[index]
            updatedMessage.homeLat = message.lat
            updatedMessage.homeLon = message.lon
            parsedMessages[index] = updatedMessage
            
            // Also update in storage
            DroneStorageManager.shared.updateHomeLocation(
                droneId: targetUid,
                latitude: Double(message.lat) ?? 0.0,
                longitude: Double(message.lon) ?? 0.0
            )
        }
    }
    
    // MARK: - Helper Methods
    
    
    private func extractMAC(from message: CoTMessage) -> String? {
        // Try message property first
        if let mac = message.mac { return mac }
        
        // Try raw message sources
        if let basicIdMac = (message.rawMessage["Basic ID"] as? [String: Any])?["MAC"] as? String {
            return basicIdMac
        }
        
        if let auxAdvMac = (message.rawMessage["AUX_ADV_IND"] as? [String: Any])?["addr"] as? String {
            return auxAdvMac
        }
        
        return nil
    }
    
    private func updateCAARegistration(for mac: String, message: CoTMessage) {
        // Find existing message with same MAC and update its CAA registration
        if let existingIndex = self.parsedMessages.firstIndex(where: { $0.mac == mac }) {
            var existingMessage = self.parsedMessages[existingIndex]
            existingMessage.caaRegistration = message.caaRegistration ?? message.id
            // Keep the original ID type if it's a serial number
            if !existingMessage.idType.contains("Serial") {
                existingMessage.idType = "CAA Assigned Registration ID"
            }
            self.parsedMessages[existingIndex] = existingMessage
            print("Updated CAA registration for existing drone with MAC: \(mac)")
        }
    }
    
    
    func determineSignalType(message: CoTMessage, mac: String?, rssi: Int?, updatedMessage: inout CoTMessage) -> SignalSource.SignalType {
        print("DEBUG: Index and runtime : \(String(describing: message.index)) and \(String(describing: message.runtime))")
        print("CurrentmessageFormat: \(currentMessageFormat)")
        
        func isValidMAC(_ mac: String) -> Bool {
            return mac.range(of: "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", options: .regularExpression) != nil
        }
        
        var checkedMac = mac ?? ""
        if !isValidMAC(checkedMac) {
            checkedMac = ""
        }
        
        let newSourceType: SignalSource.SignalType
        if !isValidMAC(checkedMac) {
            newSourceType = .sdr
        } else if message.index != nil && message.index != "" && message.index != "0" ||
                    message.runtime != nil && message.runtime != "" && message.runtime != "0" {
            newSourceType = .wifi
        } else {
            newSourceType = .bluetooth
        }
        
        // Create new source only if we have valid data
        guard let newSource = SignalSource(
            mac: checkedMac,
            rssi: rssi ?? 0,
            type: newSourceType,
            timestamp: Date()
        ) else { return newSourceType }
        
        // Keep track of sources by TYPE
        var sourcesByType: [SignalSource.SignalType: SignalSource] = [:]
        
        // Process existing sources - keep newest per type
        for source in updatedMessage.signalSources {
            if let existing = sourcesByType[source.type] {
                if source.timestamp > existing.timestamp {
                    sourcesByType[source.type] = source
                }
            } else {
                sourcesByType[source.type] = source
            }
        }
        
        // Only add the new source if it's valid
        sourcesByType[newSourceType] = newSource
        
        // Sort by precedence: WiFi > BT > SDR
        updatedMessage.signalSources = Array(sourcesByType.values).sorted { s1, s2 in
            let typeOrder: [SignalSource.SignalType] = [.wifi, .bluetooth, .sdr]
            if let index1 = typeOrder.firstIndex(of: s1.type),
               let index2 = typeOrder.firstIndex(of: s2.type) {
                return index1 < index2
            }
            return false
        }
        
        //        print("DEBUG: Signal sources after filtering by type: \(updatedMessage.signalSources.count)")
        for source in updatedMessage.signalSources {
            print("  - \(source.type): \(source.mac) @ \(source.rssi)dBm")
        }
        
        return newSourceType
    }
    
    
    private func updateDroneSignaturesAndEncounters(_ signature: DroneSignature, message: CoTMessage) {
        
        // UNCOMMENT THIS BLOCK TO DISALLOW ZERO COORDINATE DETECTIONS
        //        guard signature.position.coordinate.latitude != 0 &&
        //              signature.position.coordinate.longitude != 0 else {
        //            return // Skip update if coordinates are 0,0
        //        }
        
        // Update drone signatures
        if let index = self.droneSignatures.firstIndex(where: { $0.primaryId.id == signature.primaryId.id }) {
            self.droneSignatures[index] = signature
            print("Updating existing signature")
        } else {
            print("Added new signature")
            self.droneSignatures.append(signature)
        }
        
        //        // Validate coordinates first - UNCOMMENT THIS TO DISALLOW ZERO COORDINATE DETECTIONS
        //        guard signature.position.coordinate.latitude != 0 &&
        //              signature.position.coordinate.longitude != 0 else {
        //            return // Skip update if coordinates are 0,0
        //        }
        
        // Update encounters storage history
        let encounters = DroneStorageManager.shared.encounters
        let currentMonitorStatus = self.statusViewModel.statusMessages.last
        
        if encounters[signature.primaryId.id] != nil {
            let existing = encounters[signature.primaryId.id]!
            let hasNewPosition = existing.flightPath.last?.latitude != signature.position.coordinate.latitude ||
            existing.flightPath.last?.longitude != signature.position.coordinate.longitude ||
            existing.flightPath.last?.altitude != signature.position.altitude
            
            if hasNewPosition {
                DroneStorageManager.shared.saveEncounter(message, monitorStatus: currentMonitorStatus)
                print("Updated existing encounter with new position")
            }
        } else {
            DroneStorageManager.shared.saveEncounter(message, monitorStatus: currentMonitorStatus)
            print("Added new encounter to storage")
        }
    }
    
    private func updateAlertRing(for message: CoTMessage) {
        let latValue = Double(message.lat) ?? 0
        let lonValue = Double(message.lon) ?? 0
        
        // Check if we have a drone with zero coordinates but valid RSSI
        if (latValue == 0 && lonValue == 0) && message.rssi != nil && message.rssi != 0 {
            // Use the latest status message for monitor location
            if let monitorStatus = statusViewModel.statusMessages.last {
                let monitorLocation = CLLocationCoordinate2D(
                    latitude: monitorStatus.gpsData.latitude,
                    longitude: monitorStatus.gpsData.longitude
                )
                
                // Use the SignatureGenerator to calculate distance
                let signatureGenerator = DroneSignatureGenerator()
                let distance = signatureGenerator.calculateDistance(Double(message.rssi!))
                
                // Add or update alert ring
                if let index = alertRings.firstIndex(where: { $0.droneId == message.uid }) {
                    alertRings[index] = AlertRing(
                        centerCoordinate: monitorLocation,
                        radius: distance,
                        droneId: message.uid,
                        rssi: message.rssi!
                    )
                } else {
                    alertRings.append(AlertRing(
                        centerCoordinate: monitorLocation,
                        radius: distance,
                        droneId: message.uid,
                        rssi: message.rssi!
                    ))
                }
            }
        } else {
            // Remove alert ring if coordinates are now valid
            alertRings.removeAll(where: { $0.droneId == message.uid })
        }
    }
    
    // Helper function to calculate distance using the MDN RSSI scale
    private func calculateMDNDistance(_ rssi: Double) -> Double {
        let minRssi = 1200.0 // Threshold for weakest signals
        let maxRssi = 2800.0 // Threshold for strongest signals
        
        if rssi < minRssi {
            return 1500.0 // Maximum range when signal is too weak
        }
        
        let normalizedRssi = (rssi - minRssi) / (maxRssi - minRssi)
        let clampedNormalizedRssi = min(1.0, max(0.0, normalizedRssi))
        
        // Use an exponential curve to map RSSI to distance
        // Strong signal (closer to maxRssi) results in shorter distance
        // Weak signal (closer to minRssi) results in longer distance
        let distance = 1500.0 * exp(-5.0 * clampedNormalizedRssi)
        
        // Ensure distance stays within the expected range
        return min(max(distance, 0.0), 1500.0)
    }
    
    
    
    
    // Helper function to update alert rings for consolidated messages
    private func updateAlertRingForConsolidated(consolidated: CoTMessage, originalMessages: [CoTMessage]) {
        // Remove all existing alert rings for the original messages
        for message in originalMessages {
            alertRings.removeAll(where: { $0.droneId == message.uid })
        }
        
        // Create a new alert ring for the consolidated message
        if let monitorStatus = statusViewModel.statusMessages.last {
            let monitorLocation = CLLocationCoordinate2D(
                latitude: monitorStatus.gpsData.latitude,
                longitude: monitorStatus.gpsData.longitude
            )
            
            // Calculate radius based on strongest signal
            let rssiValue = Double(consolidated.rssi ?? 0)
            let distance: Double
            
            if rssiValue > 1000 {
                distance = calculateMDNDistance(rssiValue)
            } else {
                distance = DroneSignatureGenerator().calculateDistance(rssiValue)
            }
            
            let newRing = AlertRing(
                centerCoordinate: monitorLocation,
                radius: distance,
                droneId: consolidated.uid,
                rssi: consolidated.rssi ?? 0
            )
            
            alertRings.append(newRing)
        }
    }
    
    // Helper to calculate radius from RSSI
    private func calculateRadius(rssi: Double) -> Double {
        if rssi > 1000 {
            // MDN-style values (around 1400-2500)
            return 100.0 + ((rssi - 1200) / 10)
        } else {
            // Standard RSSI values (negative dBm)
            let generator = DroneSignatureGenerator()
            return generator.calculateDistance(rssi)
        }
    }
    
    
    private func calculateConfidenceRadius(_ confidence: Double) -> Double {
        // Radius gets smaller as confidence increases
        return 50.0 + ((1.0 - confidence) * 250.0)
    }
    
    private func updateMACHistory(droneId: String, mac: String?) {
        guard let mac = mac, !mac.isEmpty else { return }
        
        // Check second character for randomization pattern (2,6,A,E)
        if mac.count >= 2 {
            let secondChar = mac[mac.index(mac.startIndex, offsetBy: 1)]
            let isRandomized = "26AE".contains(secondChar)
            
            if isRandomized {
                macProcessing[droneId] = true
            }
        }
        
        var macs = self.macIdHistory[droneId] ?? Set<String>()
        macs.insert(mac)
        self.macIdHistory[droneId] = macs
    }
    
    private func updateParsedMessages(updatedMessage: CoTMessage, signature: DroneSignature) {
        // Find existing message by MAC or UID
        if let existingIndex = self.parsedMessages.firstIndex(where: { $0.mac == updatedMessage.mac || $0.uid == updatedMessage.uid }) {
            var existingMessage = self.parsedMessages[existingIndex]
            
            var consolidatedSources: [SignalSource.SignalType: SignalSource] = [:]
            
            // Process existing sources first to maintain original order
            for source in existingMessage.signalSources {
                consolidatedSources[source.type] = source
            }
            
            // Only update with newer sources
            for source in updatedMessage.signalSources {
                if let existing = consolidatedSources[source.type] {
                    if source.timestamp > existing.timestamp {
                        consolidatedSources[source.type] = source
                    }
                } else {
                    consolidatedSources[source.type] = source
                }
            }
            
            // Maintain the preferred order of WiFi > Bluetooth > SDR while preserving existing sources
            let typeOrder: [SignalSource.SignalType] = [.wifi, .bluetooth, .sdr]
            existingMessage.signalSources = Array(consolidatedSources.values)
                .sorted { s1, s2 in
                    if let index1 = typeOrder.firstIndex(of: s1.type),
                       let index2 = typeOrder.firstIndex(of: s2.type) {
                        return index1 < index2
                    }
                    return false
                }
            
            // Set primary MAC and RSSI based on the most recent source
            if let latestSource = existingMessage.signalSources.first {
                existingMessage.mac = latestSource.mac
                existingMessage.rssi = latestSource.rssi
            }
            
            // Update metadata but avoid overwriting good values with defaults
            if updatedMessage.lat != "0.0" { existingMessage.lat = updatedMessage.lat }
            if updatedMessage.lon != "0.0" { existingMessage.lon = updatedMessage.lon }
            if updatedMessage.speed != "0.0" { existingMessage.speed = updatedMessage.speed }
            if updatedMessage.vspeed != "0.0" { existingMessage.vspeed = updatedMessage.vspeed }
            if updatedMessage.alt != "0.0" { existingMessage.alt = updatedMessage.alt }
            if let height = updatedMessage.height, height != "0.0" { existingMessage.height = height }
            
            // Update the timestamp
            existingMessage.lastUpdated = Date()
            
            // Preserve operator info
            if !updatedMessage.pilotLat.isEmpty && updatedMessage.pilotLat != "0.0" {
                existingMessage.pilotLat = updatedMessage.pilotLat
                existingMessage.pilotLon = updatedMessage.pilotLon
            }
            
            // Preserve operator ID unless we get a new valid one
            if let newOpId = updatedMessage.operator_id, !newOpId.isEmpty {
                existingMessage.operator_id = newOpId
            }
            
            // Update ID type and CAA registration if present
            if updatedMessage.idType.contains("CAA") {
                existingMessage.caaRegistration = updatedMessage.caaRegistration
                existingMessage.idType = "CAA Assigned Registration ID"
            }
            
            // Update Track
            if updatedMessage.trackSpeed != "0.0" && updatedMessage.trackCourse != "0.0" {
                existingMessage.trackSpeed = updatedMessage.trackSpeed
                existingMessage.trackCourse = updatedMessage.trackCourse
            }
            
            // Update spoof detection
            existingMessage.isSpoofed = updatedMessage.isSpoofed
            existingMessage.spoofingDetails = updatedMessage.spoofingDetails
            
            // Update the message
            self.parsedMessages[existingIndex] = existingMessage
            self.objectWillChange.send()
            
        } else {
            // New message - add it
            self.parsedMessages.append(updatedMessage)
            if !updatedMessage.idType.contains("CAA") {
                self.sendNotification(for: updatedMessage)
            }
        }
    }
    
    private func handleCAAMessage(_ message: CoTMessage) {
        // Special handling for CAA messages that don't generate a signature
        if let mac = message.mac {
            // Update MAC to CAA mapping
            self.macToCAA[mac] = message.id
            
            // Find and update existing message with same MAC
            if let index = self.parsedMessages.firstIndex(where: { $0.mac == mac }) {
                var existingMessage = self.parsedMessages[index]
                existingMessage.caaRegistration = message.caaRegistration
                self.parsedMessages[index] = existingMessage
                print("Updated CAA registration for existing drone")
            }
        }
    }
    
    //MARK: - Helper functions
    
    private func sendNotification(for message: CoTViewModel.CoTMessage) {
        guard Settings.shared.notificationsEnabled else { return }
        
        // Only send notification if more than 5 seconds have passed
        if let lastTime = lastNotificationTime,
           Date().timeIntervalSince(lastTime) < 5 {
            return
        }
        
        if Settings.shared.webhooksEnabled {
            sendWebhookNotification(for: message)
        }
        
        // Create and send notification
        let content = UNMutableNotificationContent()
        print("Attempting to send notification for drone: \(message.uid)")
        content.title = "Drone Detected"
        content.body = "From: \(message.uid)\nMAC: \(message.mac ?? "")"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            } else {
                print("Successfully scheduled notification")
            }
        }
        
        lastNotificationTime = Date()
    }
    
    private func sendStatusNotification(for message: StatusViewModel.StatusMessage) {
        guard Settings.shared.notificationsEnabled else { return }
        // Don't send here - let StatusViewModel handle it through checkSystemThresholds
        statusViewModel.checkSystemThresholds()
    }
    
    func stopListening() {
        guard isListeningCot else { return }
        
        isListeningCot = false
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("RefreshNetworkConnections"),
            object: nil
        )
        
        // Clean up multicast if using it
        multicastConnection?.cancel()
        cotListener?.cancel()
        statusListener?.cancel()
        
        // Chill and let it die
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.multicastConnection = nil
            self.cotListener = nil
            self.statusListener = nil
            
            print("Listeners properly released after delay")
        }
        
        // Properly disconnect ZMQ if using it
        if let zmqHandler = zmqHandler {
            zmqHandler.disconnect()
            self.zmqHandler = nil
        }
        
        // Stop background processing
        backgroundManager.stopBackgroundProcessing()
        
        print("All listeners stopped and connections cleaned up.")
    }
    
    @objc private func checkConnections() {
        // Only check if we're supposed to be listening
        guard isListeningCot else { return }
        
        if Settings.shared.connectionMode == .zmq {
            if zmqHandler == nil || zmqHandler?.isConnected != true {
                print("ZMQ connection lost in background, reconnecting...")
                startZMQListening()
            }
        } else if Settings.shared.connectionMode == .multicast {
            if cotListener == nil || statusListener == nil {
                print("Multicast connection lost in background, reconnecting...")
                startMulticastListening()
            }
        }
    }
    
}


extension CoTViewModel.CoTMessage {
    
    var timestampDouble: Double {
        if let timestampString = timestamp, let value = Double(timestampString) {
            return value
        }
        // Fallback to current time if timestamp is invalid
        return Date().timeIntervalSince1970
    }
    
    enum ConnectionStatus {
        case connected
        case weak
        case lost
        case unknown
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .weak: return .yellow
            case .lost: return .red
            case .unknown: return .gray
            }
        }
        
        var description: String {
            switch self {
            case .connected: return "Connected"
            case .weak: return "Weak Signal"
            case .lost: return "Connection Lost"
            case .unknown: return "Unknown"
            }
        }
    }
    
    var connectionStatus: ConnectionStatus {
        let currentTime = Date().timeIntervalSince1970
        let messageTime = timestampDouble
        let timeSinceLastUpdate = currentTime - messageTime
        
        if timeSinceLastUpdate < 5 {
            if let rssi = rssi {
                return rssi > -70 ? .connected : .weak
            }
            return .connected
        } else if timeSinceLastUpdate < 30 {
            return .weak
        } else {
            return .lost
        }
    }
}

extension CoTViewModel.CoTMessage {
    struct TrackData {
        let course: String?
        let speed: String?
        let bearing: String?
    }
}

// MARK: - Webhook Integration
extension CoTViewModel {
    
    private func sendWebhookNotification(for message: CoTMessage) {
        // Always drone detected for this branch (no FPV support)
        let event: WebhookEvent = .droneDetected
        
        // Build data payload
        var data: [String: Any] = [
            "uid": message.uid,
            "timestamp": message.timestamp ?? Date().timeIntervalSince1970
        ]
        
        if let rssi = message.rssi {
            data["rssi"] = rssi
        }
        
        // Use the existing lat/lon properties from CoTMessage
        if let latitude = Double(message.lat) {
            data["latitude"] = latitude
        }
        
        if let longitude = Double(message.lon) {
            data["longitude"] = longitude
        }
        
        if let altitude = Double(message.alt) {
            data["altitude"] = altitude
        }
        
        // Build metadata
        var metadata: [String: String] = [:]
        
        if let mac = message.mac {
            metadata["mac"] = mac
        }
        
        if let caaReg = message.caaRegistration {
            metadata["caa_registration"] = caaReg
        }
        
        if let manufacturer = message.manufacturer {
            metadata["manufacturer"] = manufacturer
        }
        
        metadata["id_type"] = message.idType
        metadata["ua_type"] = message.uaType.rawValue
        
        // Send webhook
        WebhookManager.shared.sendWebhook(event: event, data: data, metadata: metadata)
    }
    
    private func sendSystemWebhookAlert(_ title: String, _ message: String, event: WebhookEvent) {
        let data: [String: Any] = [
            "title": title,
            "message": message,
            "timestamp": Date()
        ]
        
        WebhookManager.shared.sendWebhook(event: event, data: data)
    }
}
