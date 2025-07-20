//
//  ZMQHandler.swift
//  WarDragon
//  Created by Root Down Digital on 11/25/24.
//

import Foundation
import SwiftyZeroMQ5


class ZMQHandler: ObservableObject {
    //MARK: - ZMQ Connection
    @Published var messageFormat: MessageFormat = .bluetooth
    var isInBackgroundMode = false
    static let shared = ZMQHandler()
    private var context: SwiftyZeroMQ.Context?
    private var telemetrySocket: SwiftyZeroMQ.Socket?
    private var statusSocket: SwiftyZeroMQ.Socket?
    private var poller: SwiftyZeroMQ.Poller?
    private var pollingQueue: DispatchQueue?
    private var shouldContinueRunning = false
    private var lastHost = ""
    private var lastTelemetryPort: UInt16 = 0
    private var lastStatusPort: UInt16 = 0
    private var lastTelemetryHandler: MessageHandler = { _ in }
    private var lastStatusHandler: MessageHandler = { _ in }
    private var lastMessageTime: Date = Date()
    private let subscriptionTimeout: TimeInterval = 120
    private var isSubscriptionActive = true
    private var connectionMonitorTimer: Timer?
    private let connectionCheckInterval: TimeInterval = 30
    
    typealias MessageHandler = (String) -> Void
    
    @Published var isConnected = false {
        didSet {
            if oldValue != isConnected {
                DispatchQueue.main.async {
                    Settings.shared.isListening = self.isConnected
                }
            }
        }
    }
    
    enum MessageFormat {
        case wifi
        case bluetooth
        case sdr
    }
    
    private let manufacturerMapping: [Int: String] = [
        1187: "Ruko",
    ]
    
    public let macPrefixesByManufacturer: [String: [String]] = [
        "DJI": [
            "04:A8:5A",
            "34:D2:62",
            "48:1C:B9",
            "58:B8:58",
            "60:60:1F",  // Mavic 1 Pro
            "E4:7A:2C",
            "9C:5A:8A" // Check this one
        ],
        "Parrot": [
            "00:12:1C",
            "00:26:7E",  // AR Drone and AR Drone 2.0
            "90:03:B7",  // AR Drone 2.0
            "90:3A:E6",
            "A0:14:3D"   // Jumping Sumo and SkyController
        ],
        "GuangDong Syma": [
            "58:04:54"
        ],
        "Skydio": [
            "38:1D:14"
        ],
        "Autel": [
            "EC:5B:CD",
            "18:D7:93" // Check this
        ],
        "Yuneec": [
            "E0:B6:F5"
        ],
        "Hubsan": [
            "98:AA:FC"
        ],
        "Holy Stone": [
            "00:0C:BF",
            "18:65:6A"
        ],
        "Ruko": [
            "E0:4E:7A"
        ],
        "PowerVision": [
            "54:7D:40"
        ],
        "Teal": [
            "B0:30:C8"
        ],
        "UAV Navigation": [
            "00:50:C2",
            "B4:4D:43"
        ],
        "Amimon": [
            "0C:D6:96"
        ],
        "Baiwang": [
            "9C:5A:8A"
        ],
        "Bilian": [
            "08:EA:40", "0C:8C:24", "0C:CF:89", "10:A4:BE", "14:5D:34", "14:6B:9C", "20:32:33", "20:F4:1B", "28:F3:66", "2C:C3:E6", "30:7B:C9", "34:7D:E4", "38:01:46", "38:7A:CC", "3C:33:00", "44:01:BB", "44:33:4C", "54:EF:33", "60:FB:00", "74:EE:2A", "78:22:88", "7C:A7:B0", "98:03:CF", "A0:9F:10", "AC:A2:13", "B4:6D:C2", "C4:3C:B0", "C8:FE:0F", "CC:64:1A", "E0:B9:4D", "EC:3D:FD", "F0:C8:14", "FC:23:CD"
        ]
    ]
    

    func connect(host: String, zmqTelemetryPort: UInt16, zmqStatusPort: UInt16, onTelemetry: @escaping MessageHandler, onStatus: @escaping MessageHandler) {
        // Store parameters for reconnection
        self.lastHost = host
        self.lastTelemetryPort = zmqTelemetryPort
        self.lastStatusPort = zmqStatusPort
        self.lastTelemetryHandler = onTelemetry
        self.lastStatusHandler = onStatus
        
        guard !host.isEmpty && zmqTelemetryPort > 0 && zmqStatusPort > 0 else {
            print("Invalid connection parameters")
            return
        }
        
        guard !isConnected else {
            print("Already connected")
            return
        }
        
        disconnect()
        shouldContinueRunning = true
        
        do {
            // Initialize context and poller
            context = try SwiftyZeroMQ.Context()
            poller = SwiftyZeroMQ.Poller()
            
            // Setup telemetry socket
            telemetrySocket = try context?.socket(.subscribe)
            try telemetrySocket?.setSubscribe("")
            try configureSocket(telemetrySocket!)
            try telemetrySocket?.connect("tcp://\(host):\(zmqTelemetryPort)")
            try poller?.register(socket: telemetrySocket!, flags: .pollIn)
            
            // Setup status socket
            statusSocket = try context?.socket(.subscribe)
            try statusSocket?.setSubscribe("")
            try configureSocket(statusSocket!)
            try statusSocket?.connect("tcp://\(host):\(zmqStatusPort)")
            try poller?.register(socket: statusSocket!, flags: .pollIn)
            
            // Start polling on background queue
            pollingQueue = DispatchQueue(label: "com.wardragon.zmq.polling")
            startPolling(onTelemetry: onTelemetry, onStatus: onStatus)
            
            isConnected = true
            isSubscriptionActive = true
            print("ZMQ: Connected successfully")
            
            // Start connection monitoring
            startConnectionMonitoring()
            
        } catch {
            print("ZMQ Setup Error: \(error)")
            disconnect()
        }
    }
    
    private func startConnectionMonitoring() {
        // Stop any existing timer
        connectionMonitorTimer?.invalidate()
        
        // Timer to periodically check the connection
        connectionMonitorTimer = Timer.scheduledTimer(withTimeInterval: connectionCheckInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            
            // Check if the connection is still valid
            self.checkConnectionStatus()
        }
        
        // Make sure the timer runs even when the app is in the background
        RunLoop.main.add(connectionMonitorTimer!, forMode: .common)
    }
    
    private func checkConnectionStatus() {
        guard isConnected else { return }
        
        do {
            if let items = try poller?.poll(timeout: 0.1) {
                if items.isEmpty {
                    print("ZMQ connection appears to be inactive")
                    DispatchQueue.main.async { [weak self] in
                        self?.reconnect()
                    }
                }
                else {
                    print("ZMQ connection appears active..")
                }
            }
        } catch {
            print("ZMQ connection check failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.reconnect()
            }
        }
    }
    
    func setBackgroundMode(_ enabled: Bool) {
        isInBackgroundMode = enabled
        print("ZMQ Background mode \(enabled ? "enabled" : "disabled")")
        
        if enabled {
            try? telemetrySocket?.setRecvTimeout(2000)
            try? statusSocket?.setRecvTimeout(2000)
        } else {
            try? telemetrySocket?.setRecvTimeout(500)
            try? statusSocket?.setRecvTimeout(500)
        }
    }
    
    private func configureSocket(_ socket: SwiftyZeroMQ.Socket) throws {
        try socket.setRecvHighWaterMark(500)
        try socket.setLinger(0)
        try socket.setRecvTimeout(500)
        try socket.setImmediate(true)
        try socket.setIntegerSocketOption(ZMQ_TCP_KEEPALIVE, 1)
        try socket.setIntegerSocketOption(ZMQ_TCP_KEEPALIVE_IDLE, 120)
        try socket.setIntegerSocketOption(ZMQ_TCP_KEEPALIVE_INTVL, 60)
    }
    
    private func startPolling(onTelemetry: @escaping MessageHandler, onStatus: @escaping MessageHandler) {
        pollingQueue?.async { [weak self] in
            guard let self = self else { return }
            
            while self.shouldContinueRunning {
                autoreleasepool {
                    do {
                        let pollTimeout: Double = self.isInBackgroundMode ? 2.0 : 0.1
                        
                        if let items = try self.poller?.poll(timeout: pollTimeout) {
                            for (socket, events) in items {
                                if events.contains(.pollIn) {
                                    if let data = try socket.recv(bufferLength: 32768),
                                       let jsonString = String(data: data, encoding: .utf8) {
                                        
                                        self.lastMessageTime = Date()
                                        self.isSubscriptionActive = true
                                        
                                        if socket === self.telemetrySocket {
                                            if let xmlMessage = self.convertTelemetryToXML(jsonString) {
                                                DispatchQueue.main.async {
                                                    onTelemetry(xmlMessage)
                                                }
                                            }
                                        } else if socket === self.statusSocket {
                                            if let xmlMessage = self.convertStatusToXML(jsonString) {
                                                DispatchQueue.main.async {
                                                    onStatus(xmlMessage)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        if self.isInBackgroundMode {
                            Thread.sleep(forTimeInterval: 0.5)
                        }
                        
                    } catch let error as SwiftyZeroMQ.ZeroMQError {
                        if error.description != "Resource temporarily unavailable" &&
                           error.description != "Operation would block" &&
                           self.shouldContinueRunning {
                            print("ZMQ Polling Error: \(error)")
                            
                            if self.shouldContinueRunning && self.isConnected {
                                DispatchQueue.main.async {
                                    self.reconnect()
                                }
                                return
                            }
                        }
                    } catch {
                        if self.shouldContinueRunning {
                            print("ZMQ Polling Error: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    //MARK: - Message Parsing & Conversion
    // TODO: Implement these
    var status = ""
    var direction = 0.0
    var alt_pressure = 0.0
    var horiz_acc = 0
    var vert_acc = ""
    var baro_acc = 0
    var speed_acc = 0
    var timestamp = 0
    
    func convertTelemetryToXML(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        print("Raw Message: ", jsonString)
        
        // Determine format from raw string and runtime/index presence
        if jsonString.contains("\"index\":") &&
            jsonString.contains("\"runtime\":") &&
            (jsonString.range(of: "\"index\":\\s*([1-9]\\d*)", options: .regularExpression) != nil) &&
            (jsonString.range(of: "\"runtime\":\\s*([1-9]\\d*)", options: .regularExpression) != nil) {
            messageFormat = .wifi
        } else if jsonString.hasPrefix("[") {
            messageFormat = .bluetooth
        } else {
            messageFormat = .sdr
        }
        
        do {
            // Try parsing as a single object first (ESP32 format)
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return processJsonObject(jsonObject)
            }
            
            // If not a single object, try parsing as an array (DJI/BT formats)
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return processJsonArray(jsonArray)
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
        
        return nil
    }
    
    func processJsonObject(_ jsonObject: [String: Any]) -> String? {
        // Extract messages from the object
        let basicId = jsonObject["Basic ID"] as? [String: Any]
        let location = jsonObject["Location/Vector Message"] as? [String: Any]
        let system = jsonObject["System Message"] as? [String: Any]
        let auth = jsonObject["Auth Message"] as? [String: Any]
        let operatorId = jsonObject["Operator ID Message"] as? [String: Any]
        let selfID = jsonObject["Self-ID Message"] as? [String: Any]
        
        // Extract index and runtime
        let mIndex = jsonObject["index"] as? Int ?? 0
        let mRuntime = jsonObject["runtime"] as? Int ?? 0
        
        // Extract takeoff location from DJI via SDR
        let homeLat = system?["home_lat"] as? Double ?? 0.0
        let homeLon = system?["home_lon"] as? Double ?? 0.0
        
        // Extract operator ID from both possible sources
        var opID = (system?["operator_id"] as? String) ?? (operatorId?["operator_id"] as? String) ?? ""
        
        // Handle weird multicast output
        if opID == "Terminator0x00" {
            opID = "N/A"
        }
        guard let basicId = basicId else {
            print("No Basic ID found")
            return nil
        }
        
        // Basic ID Message Fields
        let uaType = String(describing: basicId["ua_type"] ?? "")
        let droneId = basicId["id"] as? String ?? UUID().uuidString
        if droneId.contains("NONE"){
            print("SKIPPING THE NONE IN ID")
            return nil
        }
        let idType = basicId["id_type"] as? String ?? ""
        var caaReg =  ""
        if idType.contains("CAA") {
            caaReg = droneId.replacingOccurrences(of: "drone-", with: "")
        }
        var mac = basicId["MAC"] as? String ?? ""
        let rssi = basicId["RSSI"] as? Int ?? 0
        let desc = basicId["description"] as? String ?? ""
        let mProtocol = basicId["protocol_version"] as? String ?? ""
        
        // SelfID Message Fields
        let selfIDtext = selfID?["text"] as? String ?? ""
        let selfIDDesc = selfID?["description"] as? String ?? ""
        
        // Tricky way to get MAC from "text": "UAV 4f:16:39:ff:ff:ff operational" if mac empty
        if mac.isEmpty, let selfIDtext = selfID?["text"] as? String {
            mac = selfIDtext.replacingOccurrences(of: "UAV ", with: "").replacingOccurrences(of: " operational", with: "")
        }
        
        // Location Message Fields
        let lat = formatDoubleValue(location?["latitude"])
        let lon = formatDoubleValue(location?["longitude"])
        let alt = formatDoubleValue(location?["geodetic_altitude"])
        let speed = formatDoubleValue(location?["speed"])
        let vspeed = formatDoubleValue(location?["vert_speed"])
        let height_agl = formatDoubleValue(location?["height_agl"])
        let pressure_altitude = formatDoubleValue(location?["pressure_altitude"])
        let speed_multiplier = formatDoubleValue(location?["speed_multiplier"])
        
        // Protocol specific handling
        let protocol_version = location?["protocol_version"] as? String ?? mProtocol
        let op_status = location?["op_status"] as? String ?? ""
        let height_type = location?["height_type"] as? String ?? ""
        let ew_dir_segment = location?["ew_dir_segment"] as? String ?? ""
        let direction = formatDoubleValue(location?["direction"])
        
        
        // Status and Accuracy Fields
        let status = location?["status"] as? Int ?? 0
        let alt_pressure = formatDoubleValue(location?["alt_pressure"])
        let horiz_acc = location?["horiz_acc"] as? Int ?? 0
        let vert_acc = location?["vert_acc"] as? String ?? ""
        let baro_acc = location?["baro_acc"] as? Int ?? 0
        let speed_acc = location?["speed_acc"] as? Int ?? 0
        let timestamp = location?["timestamp"] as? Int ?? 0
        
        // System Message Fields - check all possible field names
        let operator_lat = formatDoubleValue(system?["operator_lat"]) != "0.0" ?
        formatDoubleValue(system?["operator_lat"]) :
        formatDoubleValue(system?["latitude"])
        
        let operator_lon = formatDoubleValue(system?["operator_lon"]) != "0.0" ?
        formatDoubleValue(system?["operator_lon"]) :
        formatDoubleValue(system?["longitude"])
        
        let operator_alt_geo = formatDoubleValue(location?["operator_alt_geo"])
        
        let classification = system?["classification"] as? Int ?? 0
        var channel: Int?
        var phy: Int?
        var accessAddress: Int?
        var advMode: String?
        var deviceId: Int?
        var sequenceId: Int?
        var advAddress: String?
        
        
        var manufacturer = "Unknown"
        if let aext = jsonObject["aext"] as? [String: Any],
           let advInfo = aext["AdvDataInfo"] as? [String: Any],
           let macAddress = advInfo["mac"] as? String {
            
            for (key, prefixes) in macPrefixesByManufacturer {
                for prefix in prefixes {
                    if macAddress.hasPrefix(prefix) {
                        manufacturer = key
                        break
                    }
                }
            }
        }
        
        if !mac.isEmpty {
            let normalizedMac = mac.uppercased()
            for (key, prefixes) in macPrefixesByManufacturer {
                for prefix in prefixes {
                    let normalizedPrefix = prefix.uppercased()
                    if normalizedMac.hasPrefix(normalizedPrefix) {
                        manufacturer = key
                        break
                    }
                }
                if manufacturer != "Unknown" { break }
            }
        }
        
        // Extract from AUX_ADV_IND
        if let auxData = jsonObject["AUX_ADV_IND"] as? [String: Any] {
            channel = auxData["chan"] as? Int
            phy = auxData["phy"] as? Int
            accessAddress = auxData["aa"] as? Int
        }
        
        // Extract from aext
        if let aext = jsonObject["aext"] as? [String: Any],
           let advInfo = aext["AdvDataInfo"] as? [String: Any] {
            deviceId = advInfo["did"] as? Int
            sequenceId = advInfo["sid"] as? Int
            advMode = aext["AdvMode"] as? String ?? ""
            advAddress = aext["AdvA"] as? String ?? ""
        }
        
        // Generate XML
        let now = ISO8601DateFormatter().string(from: Date())
        let stale = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        
        return """
        <event version="2.0" uid="drone-\(droneId)" type="a-u-A-M-H-R" time="\(now)" start="\(now)" stale="\(stale)" how="m-g">
            <point lat="\(lat)" lon="\(lon)" hae="\(alt)" ce="9999999" le="999999"/>
            <detail>
                <track course="\(direction)" speed="\(speed)"/>
                <remarks>MAC: \(mac), RSSI: \(rssi)dBm, CAA: \(caaReg), ID Type: \(idType), UA Type: \(uaType), Manufacturer: \(manufacturer), Channel: \(String(describing: channel)), PHY: \(String(describing: phy)), Operator ID: \(opID), Access Address: \(String(describing: accessAddress)), Advertisement Mode: \(String(describing: advMode)), Device ID: \(String(describing: deviceId)), Protocol Version: \(protocol_version.isEmpty ? mProtocol : protocol_version), Location/Vector: [Speed: \(speed) m/s, Vert Speed: \(vspeed) m/s, Geodetic Altitude: \(alt) m, Altitude \(operator_alt_geo) m, Classification: \(classification), Height AGL: \(height_agl) m, Height Type: \(height_type), Pressure Altitude: \(pressure_altitude) m, EW Direction Segment: \(ew_dir_segment), Speed Multiplier: \(speed_multiplier), Operational Status: \(op_status), Direction: \(direction), Course: \(direction)°, Track Speed: \(speed) m/s, Timestamp: \(timestamp), Runtime: \(mRuntime), Index: \(mIndex), Status: \(status), Alt Pressure: \(alt_pressure) m, Horizontal Accuracy: \(horiz_acc), Vertical Accuracy: \(vert_acc), Baro Accuracy: \(baro_acc), Speed Accuracy: \(speed_acc)], Text: \(selfIDtext), Description: \(desc), SelfID Description: \(selfIDDesc), System: [Operator Lat: \(operator_lat), Operator Lon: \(operator_lon), Home Lat: \(homeLat), Home Lon: \(homeLon)]</remarks>
                <contact endpoint="" phone="" callsign="drone-\(droneId)"/>
                <precisionlocation geopointsrc="GPS" altsrc="GPS"/>
                <color argb="-256"/>
                <usericon iconsetpath="34ae1613-9645-4222-a9d2-e5f243dea2865/Military/UAV_quad.png"/>
            </detail>
        </event>
        """
    }
    
    // ZMQ BG socket check
    func verifySubscription(completion: @escaping (Bool) -> Void) {
        guard isConnected else {
            completion(false)
            return
        }
        
        let hasValidSockets = telemetrySocket != nil && statusSocket != nil
        let isActive = Date().timeIntervalSince(lastMessageTime) < subscriptionTimeout
        let isValid = hasValidSockets && isActive
        
        if !isValid && shouldContinueRunning {
            print("ZMQ subscription needs refresh: valid sockets: \(hasValidSockets), active: \(isActive)")
            completion(false)
        } else {
            completion(true)
        }
    }

    
    //MARK - Parse and format data
    
    private func formatDoubleValue(_ value: Any?) -> String {
        if let doubleVal = value as? Double {
            return String(format: "%.7f", doubleVal)
        }
        if let intVal = value as? Int {
            return String(format: "%.7f", Double(intVal))
        }
        if let stringVal = value as? String {
            if let doubleVal = Double(stringVal.replacingOccurrences(of: " m/s", with: "")
                .replacingOccurrences(of: " m", with: "")) {
                return String(format: "%.7f", doubleVal)
            }
        }
        return "0.0"
    }
    
    func processJsonArray(_ jsonArray: [[String: Any]]) -> String? {
        var basicId: [String: Any]?
        var location: [String: Any]?
        var system: [String: Any]?
        var selfID: [String: Any]?
        var operatorId: [String: Any]?
        var auth: [String: Any]?
        var index: Int?
        var runtime: Int?
        
        // Find first Basic ID with a valid id field
        for obj in jsonArray {
            if let basicIdMsg = obj["Basic ID"] as? [String: Any],
               let id = basicIdMsg["id"] as? String,
               !id.isEmpty {
                basicId = basicIdMsg
                break
            }
        }
        // Collect other messages
        for obj in jsonArray {
            if let locationMsg = obj["Location/Vector Message"] as? [String: Any] { location = locationMsg }
            if let systemMsg = obj["System Message"] as? [String: Any] { system = systemMsg }
            if let selfIDMsg = obj["Self-ID Message"] as? [String: Any] { selfID = selfIDMsg }
            if let operatorIDMsg = obj["Operator ID Message"] as? [String: Any] { operatorId = operatorIDMsg }
            if let authMsg = obj["Auth Message"] as? [String: Any] { auth = authMsg }
            if let indexVal = obj["index"] as? Int { index = indexVal }
            if let runtimeVal = obj["runtime"] as? Int { runtime = runtimeVal }
        }
        
        // Create consolidated object and process it
        var consolidatedObject: [String: Any] = [:]
        if let basicId = basicId { consolidatedObject["Basic ID"] = basicId }
        if let location = location { consolidatedObject["Location/Vector Message"] = location }
        if let system = system { consolidatedObject["System Message"] = system }
        if let selfID = selfID { consolidatedObject["Self-ID Message"] = selfID }
        if let operatorId = operatorId { consolidatedObject["Operator ID Message"] = operatorId }
        if let auth = auth { consolidatedObject["Auth Message"] = auth }
        if let index = index { consolidatedObject["index"] = index }
        if let runtime = runtime { consolidatedObject["runtime"] = runtime }
        
        return processJsonObject(consolidatedObject)
    }
    
    // Helper functions to safely extract values
    func extractDouble(from dict: [String: Any]?, key: String) -> Double? {
        guard let dict = dict else { return nil }
        
        if let strValue = dict[key] as? String {
            return Double(strValue.replacingOccurrences(of: " m/s", with: "").replacingOccurrences(of: " m", with: ""))
        }
        return dict[key] as? Double
    }
    
    func extractString(from dict: [String: Any]?, key: String) -> String? {
        return dict?[key] as? String
    }
    
    func extractInt(from dict: [String: Any]?, key: String) -> Int? {
        return dict?[key] as? Int
    }
    
    func extractOperatorID(from dict: [String: Any]?) -> String {
        guard let operatorId = dict else { return "" }
        
        if let opId = operatorId["operator_id"] as? String {
            return opId == "Terminator0x00" ? "N/A" : opId
        }
        return ""
    }
    
    private func getFieldValue(_ json: [String: Any], keys: [String], defaultValue: Any) -> Any {
        for key in keys {
            if let value = json[key], !(value is NSNull) {
                return value
            }
        }
        return defaultValue
    }
    
    func convertStatusToXML(_ jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return createStatusXML(json)
    }
    
    
    private func createStatusXML(_ json: [String: Any]) -> String {
        // top level
        let serialNumber = json["serial_number"] as? String ?? ""
        let gpsData = json["gps_data"] as? [String: Any] ?? [:]
        let systemStats = json["system_stats"] as? [String: Any] ?? [:]
        let antSDRTemps = json["ant_sdr_temps"] as? [String: Any] ?? [:]
        
        let memory = systemStats["memory"] as? [String: Any] ?? [:]
        let memoryTotal = Double(memory["total"] as? Int64 ?? 0)
        let memoryAvailable = Double(memory["available"] as? Int64 ?? 0)
        let memoryPercent = Double(memory["percent"] as? Double ?? 0.0)
        let memoryUsed = Double(memory["used"] as? Int64 ?? 0)
        let memoryFree = Double(memory["free"] as? Int64 ?? 0)
        let memoryActive = Double(memory["active"] as? Int64 ?? 0)
        let memoryInactive = Double(memory["inactive"] as? Int64 ?? 0)
        let memoryBuffers = Double(memory["buffers"] as? Int64 ?? 0)
        let memoryShared = Double(memory["shared"] as? Int64 ?? 0)
        let memoryCached = Double(memory["cached"] as? Int64 ?? 0)
        let memorySlab = Double(memory["slab"] as? Int64 ?? 0)
        
        // Disk stats
        let disk = systemStats["disk"] as? [String: Any] ?? [:]
        let diskTotal = Double(disk["total"] as? Int64 ?? 0)
        let diskUsed = Double(disk["used"] as? Int64 ?? 0)
        let diskFree = Double(disk["free"] as? Int64 ?? 0)
        let diskPercent = Double(disk["percent"] as? Double ?? 0.0)
        
        // Get ANTSDR temps either from dedicated field or remarks string
        var plutoTemp = antSDRTemps["pluto_temp"] as? Double ?? 0.0
        var zynqTemp = antSDRTemps["zynq_temp"] as? Double ?? 0.0
        
        // If temps are 0, try to parse from remarks if available
        if (plutoTemp == 0.0 || zynqTemp == 0.0),
           let details = json["detail"] as? [String: Any],
           let remarks = details["remarks"] as? String {
            // Extract Pluto temp
            if let plutoMatch = remarks.firstMatch(of: /Pluto Temp: (\d+\.?\d*)°C/) {
                plutoTemp = Double(plutoMatch.1) ?? 0.0
            }
            // Extract Zynq temp
            if let zynqMatch = remarks.firstMatch(of: /Zynq Temp: (\d+\.?\d*)°C/) {
                zynqTemp = Double(zynqMatch.1) ?? 0.0
            }
        }
        
        // Exact format that parseRemarks() expects
        let remarks = "CPU Usage: \(systemStats["cpu_usage"] as? Double ?? 0.0)%, " +
        "Memory Total: \(String(format: "%.1f", memoryTotal)) MB, " +
        "Memory Available: \(String(format: "%.1f", memoryAvailable)) MB, " +
        "Memory Used: \(String(format: "%.1f", memoryUsed)) MB, " +
        "Memory Free: \(String(format: "%.1f", memoryFree)) MB, " +
        "Memory Active: \(String(format: "%.1f", memoryActive)) MB, " +
        "Memory Inactive: \(String(format: "%.1f", memoryInactive)) MB, " +
        "Memory Buffers: \(String(format: "%.1f", memoryBuffers)) MB, " +
        "Memory Shared: \(String(format: "%.1f", memoryShared)) MB, " +
        "Memory Cached: \(String(format: "%.1f", memoryCached)) MB, " +
        "Memory Slab: \(String(format: "%.1f", memorySlab)) MB, " +
        "Memory Percent: \(String(format: "%.1f", memoryPercent))%, " +
        "Disk Total: \(String(format: "%.1f", diskTotal)) MB, " +
        "Disk Used: \(String(format: "%.1f", diskUsed)) MB, " +
        "Disk Free: \(String(format: "%.1f", diskFree)) MB, " +
        "Disk Percent: \(String(format: "%.1f", diskPercent))%, " +
        "Temperature: \(systemStats["temperature"] as? Double ?? 0.0)°C, " +
        "Uptime: \(systemStats["uptime"] as? Double ?? 0.0) seconds, " +
        "Pluto Temp: \(plutoTemp)°C, " +
        "Zynq Temp: \(zynqTemp)°C"
        
        return """
        <event version="2.0" uid="\(serialNumber)" type="b-m-p-s-m">
            <point lat="\(gpsData["latitude"] as? Double ?? 0.0)" lon="\(gpsData["longitude"] as? Double ?? 0.0)" hae="\(gpsData["altitude"] as? Double ?? 0.0)" ce="9999999" le="9999999"/>
            <detail>
                <track course="\(gpsData["track"] as? Double ?? 0.0)" speed="\(gpsData["speed"] as? Double ?? 0.0)"/>
                <status readiness="true"/>
                <remarks>\(remarks)</remarks>
            </detail>
        </event>
        """
    }
    
    //MARK: - Services Manager
    
    func sendServiceCommand(_ command: [String: Any], completion: @escaping (Bool, Any?) -> Void) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: command)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                if let statusSocket = statusSocket {
                    try statusSocket.send(string: jsonString)
                    
                    // Wait for response
                    if let response = try statusSocket.recv(bufferLength: 65536),
                       let responseString = String(data: response, encoding: .utf8),
                       let responseData = responseString.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                       let cmdResponse = json["command_response"] as? [String: Any] {
                        
                        let success = cmdResponse["success"] as? Bool ?? false
                        completion(success, cmdResponse["data"])
                        return
                    }
                }
            }
            completion(false, "Failed to send command")
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    func getServiceLogs(_ service: String, completion: @escaping (Result<String, Error>) -> Void) {
        let command: [String: Any] = [
            "command": [
                "type": "service_logs",
                "service": service,
                "timestamp": Date().timeIntervalSince1970
            ]
        ]
        
        sendServiceCommand(command) { success, response in
            if success, let logs = (response as? [String: Any])?["logs"] as? String {
                completion(.success(logs))
            } else {
                completion(.failure(NSError(domain: "", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Failed to get logs"])))
            }
        }
    }
    
    //MARK: - Connection helpers
    
    func disconnect() {
        print("ZMQ: Disconnecting...")
        shouldContinueRunning = false
        
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = nil
        
        Thread.sleep(forTimeInterval: 0.1)
        
        do {
            try telemetrySocket?.close()
            try statusSocket?.close()
            try context?.terminate()
        } catch {
            print("ZMQ Cleanup Error: \(error)")
        }
        
        telemetrySocket = nil
        statusSocket = nil
        context = nil
        poller = nil
        isConnected = false
        isSubscriptionActive = false
        print("ZMQ: Disconnected")
    }

    func reconnect() {
        if isConnected || lastHost.isEmpty || lastTelemetryPort == 0 || lastStatusPort == 0 {
            return
        }
        
        print("ZMQ: Reconnecting...")
        
        do {
            try telemetrySocket?.close()
            try statusSocket?.close()
        } catch {
            print("ZMQ Socket Close Error: \(error)")
            disconnect()
            return
        }
        
        telemetrySocket = nil
        statusSocket = nil
        isConnected = false
        
        connect(
            host: lastHost,
            zmqTelemetryPort: lastTelemetryPort,
            zmqStatusPort: lastStatusPort,
            onTelemetry: lastTelemetryHandler,
            onStatus: lastStatusHandler
        )
    }

    
}

extension ZMQHandler {

    func connectIfNeeded() {
        guard !isConnected,
              !lastHost.isEmpty,
              lastTelemetryPort > 0,
              lastStatusPort > 0 else { return }

        connect(host: lastHost,
                zmqTelemetryPort: lastTelemetryPort,
                zmqStatusPort: lastStatusPort,
                onTelemetry: lastTelemetryHandler,
                onStatus: lastStatusHandler)
    }

    @discardableResult
    func drainOnce() -> Bool {
        guard isConnected else { return false }
        var drained = false

        if let socket = telemetrySocket,
           let payload = try? socket.recv(bufferLength: 32768),
           !payload.isEmpty,
           let text = String(data: payload, encoding: .utf8) {
            lastTelemetryHandler(text)
            drained = true
        }
        
        if let socket = statusSocket,
           let payload = try? socket.recv(bufferLength: 32768),
           !payload.isEmpty,
           let text = String(data: payload, encoding: .utf8) {
            lastStatusHandler(text)
            drained = true
        }
        
        return drained
    }
}

