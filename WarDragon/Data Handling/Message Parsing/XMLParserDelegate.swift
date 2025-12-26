//
//  XMLParserDelegate.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import Foundation

class CoTMessageParser: NSObject, XMLParserDelegate {
    // MARK: - Properties
    var messageFormat: ZMQHandler.MessageFormat = .bluetooth
    private var rawMessage: [String: Any]?
    private var currentElement = ""
    private var currentIdType: String = "Unknown"
    private var parentElement = ""
    private var elementStack: [String] = []
    private var eventAttributes: [String: String] = [:]
    private var pointAttributes: [String: String] = [:]
    private var speed = "0.0"
    private var vspeed = "0.0"
    private var alt = "0.0"
    private var height = "0.0"
    private var pilotLat = "0.0"
    private var pilotLon = "0.0"
    private var pHomeLat = "0.0"
    private var pHomeLon = "0.0"
    private var droneDescription = ""
    private var currentValue = ""
    private var messageContent = ""
    private var remarks = ""
    private var cpuUsage: Double = 0.0
    private var bleData: [String: Any]?
    private var auxAdvInd: [String: Any]?
    private var adType: [String: Any]?
    private var aext: [String: Any]?
    private var location_protocol: String?
    private var op_status: String?
    private var height_type: String?
    private var ew_dir_segment: String?
    private var speed_multiplier: String?
    private var vertical_accuracy: String?
    private var horizontal_accuracy: String?
    private var baro_accuracy: String?
    private var speed_accuracy: String?
    private var timestamp: String?
    private var timestamp_accuracy: String?
    private var operator_id: String?
    private var operator_id_type: String?
    private var aux_rssi: Int?
    private var channel: Int?
    private var phy: Int?
    private var aa: Int?
    private var adv_mode: String?
    private var adv_mac: String?
    private var did: Int?
    private var sid: Int?
    private var index: String?
    private var runtime: String?
    var originalRawString: String?
    
    // Public method to parse JSON directly (for ZMQ messages)
    func parseJSONMessage(_ jsonData: [String: Any]) -> CoTViewModel.CoTMessage? {
        // Check if it's an array format or single object
        if let messages = jsonData["messages"] as? [[String: Any]] {
            processJSONArray(messages)
        } else {
            processSingleJSON(jsonData)
        }
        return cotMessage
    }
    
    private var fpvFrequency: String?
    private var fpvSource: String?
    private var fpvBandwidth: String?
    private var fpvRSSI: Int?
    
    // Backend metadata fields
    private var freq: Double?
    private var seenBy: String?
    private var observedAt: Double?
    private var ridTimestamp: String?
    
    // FAA RID enrichment fields
    private var ridTracking: String?
    private var ridStatus: String?
    private var ridMake: String?
    private var ridModel: String?
    private var ridSource: String?
    private var ridLookupSuccess: Bool = false
    
    private var trackAttributes: [String: String] = [:]
    private var track_course: String?
    private var track_speed: String?
    private var track_bearing: String?
    
    private var classification: Int?
    private var system_timestamp: Int?
    private var location_status: Int?
    private var alt_pressure: Double?
    private var horiz_acc: Int?
    private var description_type: Int?
    
    private var memoryTotal: Double = 0.0
    private var memoryAvailable: Double = 0.0
    private var memoryUsed: Double = 0.0
    private var memoryFree: Double = 0.0
    private var memoryActive: Double = 0.0
    private var memoryInactive: Double = 0.0
    private var memoryPercent: Double = 0.0
    private var memoryBuffers: Double = 0.0
    private var memoryShared: Double = 0.0
    private var memorySlab: Double = 0.0
    private var memoryCached: Double = 0.0
    
    private var diskTotal: Double = 0.0
    private var diskUsed: Double = 0.0
    private var diskPercent: Double = 0.0
    private var diskFree: Double = 0.0
    
    private var temperature: Double = 0.0
    private var uptime: Double = 0.0
    
    private var plutoTemp: Double = 0.0
    private var zynqTemp: Double = 0.0
    
    private var gps_course: Double = 0.0
    private var gps_speed: Double = 0.0

    var cotMessage: CoTViewModel.CoTMessage?
    var statusMessage: StatusViewModel.StatusMessage?
    private var isStatusMessage = false
    
    private let macPrefixesByManufacturer = ZMQHandler().macPrefixesByManufacturer
    
    
    // MARK: - XMLParserDelegate
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
        messageContent = ""
        
        elementStack.append(elementName)
        
        if elementName == "event" {
            
            eventAttributes = attributes
            remarks = ""

        } else if elementName == "point" {
            pointAttributes = attributes
            // For multicast message altitude is in hae
            if let haeAlt = attributes["hae"] {
                alt = haeAlt
            }
        } else if elementName == "track" {
            trackAttributes = attributes
            track_course   = attributes["course"]
            track_speed    = attributes["speed"]
        }
        
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "message" {
            messageContent += string
            if let jsonData = string.data(using: .utf8) {
                // Try array format first
                if let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    processJSONArray(jsonArray)
                }
                // Then try single object
                else if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    processSingleJSON(jsonObject)
                }
            }
        } else if currentElement == "remarks" {
            remarks += string
        } else {
            currentValue += string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func processJSONArray(_ messages: [[String: Any]]) {
        var droneData: [String: Any] = [:]
        
        for message in messages {
            // Top level elements for WiFi ID
            droneData["index"] = message["index"]
            droneData["runtime"] = message["runtime"]
            
            // Extract backend metadata (from dragonsync.py/drone.py)
            if let freq = message["freq"] as? Double {
                droneData["freq"] = freq
            }
            if let seenBy = message["seen_by"] as? String {
                droneData["seen_by"] = seenBy
            }
            if let observedAt = message["observed_at"] as? Double {
                droneData["observed_at"] = observedAt
            }
            if let ridTimestamp = message["rid_timestamp"] as? String {
                droneData["rid_timestamp"] = ridTimestamp
            }
            
            // Extract FAA RID enrichment (from faa-rid-lookup)
            if let rid = message["rid"] as? [String: Any] {
                droneData["rid_tracking"] = rid["tracking"]
                droneData["rid_status"] = rid["status"]
                droneData["rid_make"] = rid["make"]
                droneData["rid_model"] = rid["model"]
                droneData["rid_source"] = rid["source"]
                droneData["rid_lookup_success"] = rid["lookup_success"] as? Bool ?? false
            }
            
            if let basicId = message["Basic ID"] as? [String: Any] {
                droneData["id"] = basicId["id"]
                droneData["id_type"] = basicId["id_type"]
                droneData["mac"] = basicId["MAC"]
                droneData["rssi"] = basicId["RSSI"]
                droneData["protocol_version"] = basicId["protocol_version"]
            }
            
            if let location = message["Location/Vector Message"] as? [String: Any] {
                droneData["latitude"] = location["latitude"]
                droneData["longitude"] = location["longitude"]
                droneData["speed"] = location["speed"]
                droneData["vert_speed"] = location["vert_speed"]
                droneData["geodetic_altitude"] = location["geodetic_altitude"]
                droneData["height_agl"] = location["height_agl"]
                droneData["direction"] = location["direction"]
                droneData["op_status"] = location["op_status"]
                droneData["height_type"] = location["height_type"]
                droneData["vertical_accuracy"] = location["vertical_accuracy"]
                droneData["horizontal_accuracy"] = location["horizontal_accuracy"]
                droneData["baro_accuracy"] = location["baro_accuracy"]
                droneData["speed_accuracy"] = location["speed_accuracy"]
                droneData["timestamp"] = location["timestamp"]
                droneData["status"] = location["status"]
                droneData["alt_pressure"] = location["alt_pressure"]
                droneData["horiz_acc"] = location["horiz_acc"]
                droneData["vert_acc"] = location["vert_acc"]
                droneData["speed_acc"] = location["speed_acc"]
                droneData["ew_dir_segment"] = location["ew_dir_segment"]
                droneData["speed_multiplier"] = location["speed_multiplier"]
            }
            
            if let system = message["System Message"] as? [String: Any] {
                droneData["pilot_lat"] = system["operator_lat"] ?? system["latitude"]
                droneData["pilot_lon"] = system["operator_lon"] ?? system["longitude"]
                droneData["home_lat"] = system["home_lat"]
                droneData["home_lon"] = system["home_lon"]
                droneData["area_count"] = system["area_count"]
                droneData["area_radius"] = system["area_radius"]
                droneData["area_ceiling"] = system["area_ceiling"]
                droneData["area_floor"] = system["area_floor"]
                droneData["operator_alt_geo"] = system["operator_alt_geo"]
                droneData["classification"] = system["classification"]
                droneData["system_timestamp"] = system["timestamp"]
            }
            
            if let selfId = message["Self-ID Message"] as? [String: Any] {
                droneData["description"] = selfId["description"]
                droneData["text"] = selfId["text"]
                droneData["description_type"] = selfId["description_type"]
            }
            
            if let operatorId = message["Operator ID Message"] as? [String: Any] {
                droneData["operator_id"] = operatorId["operator_id"]
                droneData["operator_id_type"] = operatorId["operator_id_type"]
                if let protocolVersion = operatorId["protocol_version"] {
                    droneData["operator_protocol_version"] = protocolVersion
                }
            }
        }
        
        if let basicId = droneData["id"] as? String {
            let mac = droneData["mac"] as? String ?? ""
            var manufacturer: String?
            
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
                    if manufacturer != nil { break }
                }
            }
            
            var message = CoTViewModel.CoTMessage(
                uid: basicId,
                type: buildDroneType(droneData),
                lat: String(describing: droneData["latitude"] ?? "0.0"),
                lon: String(describing: droneData["longitude"] ?? "0.0"),
                homeLat: String(describing: droneData["home_lat"] ?? "0.0"),
                homeLon: String(describing: droneData["home_lon"] ?? "0.0"),
                speed: String(describing: droneData["speed"] ?? "0.0"),
                vspeed: String(describing: droneData["vert_speed"] ?? "0.0"),
                alt: String(describing: droneData["geodetic_altitude"] ?? "0.0"),
                pilotLat: String(describing: droneData["pilot_lat"] ?? "0.0"),
                pilotLon: String(describing: droneData["pilot_lon"] ?? "0.0"),
                description: droneData["description"] as? String ?? "",
                selfIDText: droneData["text"] as? String ?? "",
                uaType: mapUAType(droneData["ua_type"]),
                idType: droneData["id_type"] as? String ?? "Unknown",
                rawMessage: droneData
            )
            
            message.height = droneData["height_agl"] as? String
            message.protocolVersion = droneData["protocol_version"] as? String
            message.mac = mac
            message.rssi = droneData["rssi"] as? Int
            message.manufacturer = manufacturer
            message.freq = droneData["freq"] as? Double
            message.seenBy = droneData["seen_by"] as? String
            message.observedAt = droneData["observed_at"] as? Double
            message.ridTimestamp = droneData["rid_timestamp"] as? String
            message.ridTracking = droneData["rid_tracking"] as? String
            message.ridStatus = droneData["rid_status"] as? String
            message.ridMake = droneData["rid_make"] as? String
            message.ridModel = droneData["rid_model"] as? String
            message.ridSource = droneData["rid_source"] as? String
            message.ridLookupSuccess = droneData["rid_lookup_success"] as? Bool ?? false
            message.location_protocol = droneData["protocol_version"] as? String
            message.op_status = droneData["op_status"] as? String
            message.height_type = droneData["height_type"] as? String
            message.ew_dir_segment = droneData["ew_dir_segment"] as? String
            message.speed_multiplier = droneData["speed_multiplier"] as? String
            message.direction = droneData["direction"] as? String
            message.geodetic_altitude = droneData["geodetic_altitude"] as? Double
            message.vertical_accuracy = droneData["vertical_accuracy"] as? String
            message.horizontal_accuracy = droneData["horizontal_accuracy"] as? String
            message.baro_accuracy = droneData["baro_accuracy"] as? String
            message.speed_accuracy = droneData["speed_accuracy"] as? String
            message.timestamp = droneData["timestamp"] as? String
            message.timestamp_accuracy = droneData["timestamp_accuracy"] as? String
            message.operator_id = droneData["operator_id"] as? String
            message.operator_id_type = droneData["operator_id_type"] as? String
            message.index = droneData["index"] as? String
            message.runtime = droneData["runtime"] as? String ?? ""
            message.trackCourse  = track_course
            message.trackSpeed   = track_speed
            message.originalRawString = originalRawString
            
            // Parse new fields
            if let classificationInt = droneData["classification"] as? Int {
                message.classification = String(classificationInt)
            }
            message.system_timestamp = droneData["system_timestamp"] as? Int
            message.location_status = droneData["status"] as? Int
            message.alt_pressure = droneData["alt_pressure"] as? Double
            message.horiz_acc = droneData["horiz_acc"] as? Int
            message.description_type = droneData["description_type"] as? Int
            
            cotMessage = message
        }
    }
    
    private func processSingleJSON(_ json: [String: Any]) {
        // Check for FPV Detection in single object format
        if let fpvDetection = json["FPV Detection"] as? [String: Any] {
            if let fpvMessage = processFPVDetection(fpvDetection) {
                cotMessage = fpvMessage
                return
            }
        }
        
        // Check for AUX_ADV_IND (FPV update) format
        if json["AUX_ADV_IND"] != nil {
            if let auxMessage = processAuxAdvInd(json) {
                cotMessage = auxMessage
                return
            }
        }
        
        // Handle ESP32 format
        if let message = parseESP32Message(json) {
            cotMessage = message
        }
    }
    
    func parseESP32Message(_ jsonData: [String: Any]) -> CoTViewModel.CoTMessage? {
        let index = jsonData["index"] as? Int ?? 0
        let runtime = jsonData["runtime"] as? Int ?? 0
        
        if let basicId = jsonData["Basic ID"] as? [String: Any] {
            let id = basicId["id"] as? String ?? UUID().uuidString
            // Always use the original ID for the drone identifier
            let droneId = id.hasPrefix("drone-") ? id : "drone-\(id)"
            let idType = basicId["id_type"] as? String ?? ""
            var caaReg: String?
            
            // CAA registration should be stored separately, not as the primary ID
            if idType.contains("CAA") {
                caaReg = id
                print("CAA IN XML CONVERSION - storing as registration, not primary ID")
            }
            
            let droneType = buildDroneType(jsonData)
            
            let location = jsonData["Location/Vector Message"] as? [String: Any]
            let system = jsonData["System Message"] as? [String: Any]
            let selfId = jsonData["Self-ID Message"] as? [String: Any]
            let operatorID = jsonData["Operator ID Message"] as? [String: Any]
            
            // Get MAC from all possible sources
            var mac = basicId["MAC"] as? String ?? ""
            var manufacturer: String?
            
            // Check if MAC exists and match it against prefixes
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
                    if manufacturer != nil { break }
                }
            }
            
            // Fallback to extract MAC from Self-ID Message
            if mac.isEmpty, let selfIDtext = selfId?["text"] as? String {
                mac = selfIDtext
                    .replacingOccurrences(of: "UAV ", with: "")
                    .replacingOccurrences(of: " operational", with: "")
                
                let normalizedMac = mac.uppercased()
                for (key, prefixes) in macPrefixesByManufacturer {
                    for prefix in prefixes {
                        let normalizedPrefix = prefix.uppercased()
                        if normalizedMac.hasPrefix(normalizedPrefix) {
                            manufacturer = key
                            break
                        }
                    }
                    if manufacturer != nil { break }
                }
            }
            
            // Get operator info
            let opID = operatorID?["operator_id"] as? String ?? ""
            let opIDType = operatorID?["operator_id_type"] as? String ?? ""
            
            // Skip only if the ID itself is empty or explicitly "drone-" (empty after prefix)
            if id.isEmpty || droneId == "drone-" {
                print("Skipping message with empty ID")
                return nil
            }
            
            var message = CoTViewModel.CoTMessage(
                uid: droneId,
                type: droneType,
                lat: String(describing: location?["latitude"] ?? "0.0"),
                lon: String(describing: location?["longitude"] ?? "0.0"),
                homeLat: String(describing: system?["home_lat"] ?? "0.0"),
                homeLon: String(describing: system?["home_lon"] ?? "0.0"),
                speed: String(describing: location?["speed"] ?? "0.0"),
                vspeed: String(describing: location?["vert_speed"] ?? "0.0"),
                alt: String(describing: location?["geodetic_altitude"] ?? "0.0"),
                pilotLat: String(describing: system?["operator_lat"] ?? system?["latitude"] ?? "0.0"),
                pilotLon: String(describing: system?["operator_lon"] ?? system?["longitude"] ?? "0.0"),
                description: selfId?["description"] as? String ?? "",
                selfIDText: selfId?["text"] as? String ?? "",
                uaType: mapUAType(basicId["ua_type"] as? String),
                idType: idType,
                rawMessage: jsonData
            )
            
            message.caaRegistration = caaReg
            message.height = String(describing: location?["height_agl"] ?? "0.0")
            message.protocolVersion = location?["protocol_version"] as? String
            message.mac = mac
            message.rssi = basicId["RSSI"] as? Int ?? 0
            message.manufacturer = manufacturer
            message.freq = jsonData["freq"] as? Double
            message.seenBy = jsonData["seen_by"] as? String
            message.observedAt = jsonData["observed_at"] as? Double
            message.ridTimestamp = jsonData["rid_timestamp"] as? String
            message.ridTracking = jsonData["rid_tracking"] as? String
            message.ridStatus = jsonData["rid_status"] as? String
            message.ridMake = jsonData["rid_make"] as? String
            message.ridModel = jsonData["rid_model"] as? String
            message.ridSource = jsonData["rid_source"] as? String
            message.ridLookupSuccess = jsonData["rid_lookup_success"] as? Bool ?? false
            message.location_protocol = location?["protocol_version"] as? String
            message.op_status = location?["op_status"] as? String
            message.height_type = location?["height_type"] as? String
            message.ew_dir_segment = location?["ew_dir_segment"] as? String
            message.speed_multiplier = location?["speed_multiplier"] as? String
            message.direction = location?["direction"] as? String
            message.geodetic_altitude = location?["geodetic_altitude"] as? Double
            message.vertical_accuracy = location?["vertical_accuracy"] as? String
            message.horizontal_accuracy = location?["horizontal_accuracy"] as? String
            message.baro_accuracy = location?["baro_accuracy"] as? String
            message.speed_accuracy = location?["speed_accuracy"] as? String
            message.timestamp = location?["timestamp"] as? String
            message.timestamp_accuracy = location?["timestamp_accuracy"] as? String
            message.operator_id = opID
            message.operator_id_type = opIDType
            message.index = String(index)
            message.runtime = String(runtime)
            message.originalRawString = originalRawString
            
            // Parse new fields
            if let classificationInt = system?["classification"] as? Int {
                message.classification = String(classificationInt)
            }
            message.system_timestamp = system?["timestamp"] as? Int
            message.location_status = location?["status"] as? Int
            message.alt_pressure = location?["alt_pressure"] as? Double
            message.horiz_acc = location?["horiz_acc"] as? Int
            message.description_type = selfId?["description_type"] as? Int
            
            return message
        }
        return nil
    }
    
    private func buildDroneType(_ json: [String: Any]) -> String {
        var droneType = "a-u-A-M-H-R"
        
        if let basicId = json["Basic ID"] as? [String: Any] {
            let idType = basicId["id_type"] as? String
            if idType == "Serial Number (ANSI/CTA-2063-A)" {
                droneType += "-S"
            } else if idType == "CAA Assigned Registration ID" {
                droneType += "-R"
            } else {
                droneType += "-U"
            }
        }
        
        if let system = json["System Message"] as? [String: Any] {
            let operatorLat = system["operator_lat"] as? Double ?? system["latitude"] as? Double ?? 0.0
            let operatorLon = system["operator_lon"] as? Double ?? system["longitude"] as? Double ?? 0.0
            
            if operatorLat != 0.0 && operatorLon != 0.0 {
                droneType += "-O"
            }
        }
        
        return droneType
    }
    
    
    private func mapUAType(_ value: Any?) -> DroneSignature.IdInfo.UAType {
        if let intValue = value as? Int {
            switch intValue {
            case 0: return .none
            case 1: return .aeroplane
            case 2: return .helicopter
            case 3: return .gyroplane
            case 4: return .hybridLift
            case 5: return .ornithopter
            case 6: return .glider
            case 7: return .kite
            case 8: return .freeballoon
            case 9: return .captive
            case 10: return .airship
            case 11: return .freeFall
            case 12: return .rocket
            case 13: return .tethered
            case 14: return .groundObstacle
            default: return .other
            }
        } else if let strValue = value as? String {
            switch strValue {
            case "None": return .none
            case "Aeroplane", "Airplane": return .aeroplane
            case "Helicopter (or Multirotor)": return .helicopter
            case "Gyroplane": return .gyroplane
            case "Hybrid Lift": return .hybridLift
            case "Ornithopter": return .ornithopter
            case "Glider": return .glider
            case "Kite": return .kite
            case "Free Balloon": return .freeballoon
            case "Captive Balloon": return .captive
            case "Airship": return .airship
            case "Free Fall/Parachute": return .freeFall
            case "Rocket": return .rocket
            case "Tethered Powered Aircraft": return .tethered
            case "Ground Obstacle": return .groundObstacle
            default: return .helicopter
            }
        }
        return .helicopter
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let parent = elementStack.dropLast().last ?? ""
        
        if elementName == "remarks" {
            isStatusMessage = remarks.contains("CPU Usage:")
        }
        
        // Route to appropriate handler based on message type
        if isStatusMessage {
            handleStatusMessage(elementName)
        } else {
            handleDroneMessage(elementName, parent)
        }
        
        // Clean up the element stack
        elementStack.removeLast()
    }
    
    
    // MARK: - Status Message Handler
    private func handleStatusMessage(_ elementName: String) {
        switch elementName {
        case "remarks":
            parseRemarks(remarks)
        case "event":
            let uid = eventAttributes["uid"] ?? "unknown"
            // Ensure uid has "wardragon-" prefix
            let fullUid = uid.hasPrefix("wardragon-") ? uid : "wardragon-" + uid
            let serialNumber = eventAttributes["uid"] ?? "unknown"
            let fullSerialNumber = serialNumber.hasPrefix("wardragon-") ? serialNumber: "wardragon-" + serialNumber
            let lat = Double(pointAttributes["lat"] ?? "0.0") ?? 0.0
            let lon = Double(pointAttributes["lon"] ?? "0.0") ?? 0.0
            let altitude = Double(pointAttributes["hae"] ?? "0.0") ?? 0.0
            
            statusMessage = StatusViewModel.StatusMessage(
                uid: fullUid,
                serialNumber: fullSerialNumber,
                timestamp: uptime,
                gpsData: .init(
                    latitude: lat,
                    longitude: lon,
                    altitude: altitude,
                    speed: gps_speed
                ),
                systemStats: .init(
                    cpuUsage: cpuUsage,
                    memory: .init(
                      total:     Int64(memoryTotal),
                      available: Int64(memoryAvailable),
                      percent:   memoryPercent,
                      used:      Int64(max(memoryUsed, memoryTotal - memoryAvailable)),
                      free:      Int64(memoryFree),
                      active:    Int64(memoryActive),
                      inactive:  Int64(memoryInactive),
                      buffers:   Int64(memoryBuffers),
                      cached:    Int64(memoryCached),
                      shared:    Int64(memoryShared),
                      slab:      Int64(memorySlab)
                    ),
                    disk: .init(
                      total: Int64(diskTotal),
                      used:  Int64(diskUsed),
                      free:  Int64(diskFree),
                      percent: diskPercent
                    ),
                    temperature: temperature,
                    uptime:      uptime
                  ),
                antStats: .init(
                    plutoTemp: plutoTemp,
                    zynqTemp: zynqTemp
                )
            )
        default:
            break
        }
    }
    
    
    
    // MARK: - Message Handler
    private func handleDroneMessage(_ elementName: String, _ parent: String) {
        switch elementName {
        case "remarks":
            let (mac, rssi, caaReg, idRegType, manufacturer, protocolVersion, description, speed, vspeed, alt, heightAGL,
                 heightType, _, ewDirSegment, speedMultiplier, opStatus,
                 direction, timestamp, runtime, index, status, altPressure, horizAcc,
                 vertAcc, baroAcc, speedAcc, selfIDtext, selfIDDesc, operatorID, uaType,
                 operatorLat, operatorLon, operatorAltGeo, classification,
                 channel, phy, accessAddress, advMode, _, _, advAddress,
                 _, homeLat, homeLon, trackCourse, trackSpeed,
                 freq, seenBy, observedAt, ridTimestamp, ridMake, ridModel, ridSource) = parseDroneRemarks(remarks)
            
            print("DEBUG - Parsing Remarks: \(remarks) and op lon is \(String(describing: operatorLon)) and home is \(String(describing: homeLat)) / \(String(describing: homeLon))")
            
            let finalDescription = description?.isEmpty ?? true ? selfIDDesc : description ?? ""
            
            if cotMessage == nil {
                var message = CoTViewModel.CoTMessage(
                    uid: eventAttributes["uid"] ?? "",
                    type: eventAttributes["type"] ?? "",
                    lat: pointAttributes["lat"] ?? "0.0",
                    lon: pointAttributes["lon"] ?? "0.0",
                    homeLat: homeLat?.description ?? "0.0",
                    homeLon: homeLon?.description ?? "0.0",
                    speed: speed?.description ?? "0.0",
                    vspeed: vspeed?.description ?? "0.0",
                    alt: pointAttributes["hae"] ?? (alt?.description ?? "0.0"),
                    pilotLat: operatorLat?.description ?? "0.0",
                    pilotLon: operatorLon?.description ?? "0.0",
                    description: finalDescription ?? "",
                    selfIDText: selfIDtext ?? "",
                    uaType: mapUAType(uaType),
                    idType: idRegType ?? "",
                    rawMessage: buildRawMessage(mac, rssi, description)
                )
                
                message.caaRegistration = caaReg
                message.height = heightAGL?.description ?? "0.0"
                message.protocolVersion = protocolVersion
                message.mac = mac
                message.rssi = rssi
                message.manufacturer = manufacturer
                message.freq = freq
                message.seenBy = seenBy
                message.observedAt = observedAt
                message.ridTimestamp = ridTimestamp
                message.ridTracking = ridTracking
                message.ridStatus = ridStatus
                message.ridMake = ridMake
                message.ridModel = ridModel
                message.ridSource = ridSource
                message.ridLookupSuccess = ridLookupSuccess
                message.location_protocol = location_protocol
                message.op_status = opStatus
                message.height_type = heightType
                message.ew_dir_segment = ewDirSegment
                message.speed_multiplier = speedMultiplier?.description
                message.direction = direction?.description
                message.vertical_accuracy = vertAcc
                message.horizontal_accuracy = horizAcc?.description
                message.baro_accuracy = baroAcc?.description
                message.speed_accuracy = speedAcc?.description
                message.timestamp = timestamp
                message.timestamp_accuracy = timestamp_accuracy
                message.aux_rssi = aux_rssi
                message.channel = channel
                message.phy = phy
                message.aa = accessAddress
                message.adv_mode = advMode
                message.adv_mac = advAddress
                message.did = did
                message.sid = sid
                message.status = status
                message.opStatus = opStatus
                message.altPressure = altPressure?.description
                message.heightType = heightType
                message.horizAcc = horizAcc?.description
                message.vertAcc = vertAcc
                message.baroAcc = baroAcc?.description
                message.speedAcc = speedAcc?.description
                message.timestampAccuracy = timestamp_accuracy
                message.operator_id = operatorID
                message.advMode = advMode
                message.accessAddress = accessAddress
                message.operatorAltGeo = operatorAltGeo?.description
                message.classification = classification?.description
                message.index = index
                message.runtime = runtime ?? ""
                message.trackCourse = trackCourse?.description
                message.trackSpeed = trackSpeed?.description
                message.originalRawString = originalRawString
                
                cotMessage = message
            }
        case "location_protocol", "op_status", "height_type", "ew_dir_segment",
            "speed_multiplier", "vertical_accuracy", "horizontal_accuracy",
            "baro_accuracy", "speed_accuracy", "timestamp", "timestamp_accuracy":
            handleLocationFields(elementName)
        case "operator_id", "operator_id_type", "aux_rssi", "channel", "phy",
            "aa", "adv_mode", "adv_mac", "did", "sid":
            handleTransmissionFields(elementName)
        case "message":
            if let data = messageContent.data(using: .utf8) {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    processJSONArray(jsonArray)
                } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    processSingleJSON(json)
                }
            }
            
        case "event":
            if cotMessage == nil {
                let jsonFormat: [String: Any] = [
                    "index": index ?? "",
                    "runtime": runtime ?? "",
                    "Basic ID": [
                        "id": eventAttributes["uid"] ?? "",
                        "mac": eventAttributes["MAC"] ?? "",
                        "rssi": eventAttributes["RSSI"] ?? "",
                        "id_type": eventAttributes["id_type"] ?? "",
                        "ua_type": "Helicopter (or Multirotor)"
                    ],
                    "Location/Vector Message": [
                        "latitude": pointAttributes["lat"] ?? "0.0",
                        "longitude": pointAttributes["lon"] ?? "0.0",
                        "speed": speed,
                        "vert_speed": vspeed,
                        "geodetic_altitude": alt,
                        "height_agl": height
                    ],
                    "System Message": [
                        "latitude": pilotLat,
                        "longitude": pilotLon,
                        "operator_lat": pilotLat,
                        "operator_lon": pilotLon,
                        "home_lat": pHomeLat,
                        "home_lon": pHomeLon
                    ],
                    "Self-ID Message": [
                        "text": droneDescription,
                        
                    ],
                    "AUX_ADV_IND": auxAdvInd ?? [:],
                    "adtype": adType ?? [:],
                    "aext": aext ?? [:]
                ]
                rawMessage = jsonFormat
                
                let id = eventAttributes["uid"] ?? ""
                let droneId = id.hasPrefix("drone-") ? id : "drone-\(id)"
                
                let mac = eventAttributes["MAC"] ?? ""
                var manufacturer: String?
                
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
                        if manufacturer != nil { break }
                    }
                }
                
                let idType = ((eventAttributes["type"]?.contains("-S")) != nil) ? "Serial Number (ANSI/CTA-2063-A)" :
                ((eventAttributes["type"]?.contains("-R")) != nil) ? "CAA Registration ID" : "None"
                
                var caaReg: String?
                if idType == "CAA Registration ID" {
                    caaReg = droneId.replacingOccurrences(of: "drone-", with: "")
                }
                
                var message = CoTViewModel.CoTMessage(
                    uid: droneId,
                    type: eventAttributes["type"] ?? "",
                    lat: pointAttributes["lat"] ?? "0.0",
                    lon: pointAttributes["lon"] ?? "0.0",
                    homeLat: pHomeLat,
                    homeLon: pHomeLon,
                    speed: speed,
                    vspeed: vspeed,
                    alt: pointAttributes["hae"] ?? "0.0",
                    pilotLat: pilotLat,
                    pilotLon: pilotLon,
                    description: droneDescription,
                    selfIDText: "",
                    uaType: .helicopter,
                    idType: idType,
                    rawMessage: jsonFormat
                )
                
                message.caaRegistration = caaReg
                message.height = height
                message.mac = mac
                message.rssi = Int(eventAttributes["RSSI"] ?? "") ?? 0
                message.manufacturer = manufacturer
                message.location_protocol = location_protocol
                message.op_status = op_status
                message.height_type = height_type
                message.ew_dir_segment = ew_dir_segment
                message.speed_multiplier = speed_multiplier
                message.vertical_accuracy = vertical_accuracy
                message.horizontal_accuracy = horizontal_accuracy
                message.baro_accuracy = baro_accuracy
                message.speed_accuracy = speed_accuracy
                message.timestamp = timestamp
                message.timestamp_accuracy = timestamp_accuracy
                message.opStatus = op_status
                message.heightType = height_type
                message.horizAcc = horizontal_accuracy
                message.vertAcc = vertical_accuracy
                message.baroAcc = baro_accuracy
                message.speedAcc = speed_accuracy
                message.timestampAccuracy = timestamp_accuracy
                message.operator_id = operator_id
                message.operator_id_type = operator_id_type
                message.index = index
                message.runtime = runtime ?? ""
                message.trackCourse = track_course?.description
                message.trackSpeed = track_speed?.description
                message.originalRawString = originalRawString
                
                cotMessage = message
            }
        default:
            break
        }
    }
    
    //MARK: - FPV 
    
    private func processFPVDetection(_ fpvData: [String: Any]) -> CoTViewModel.CoTMessage? {
        let timestamp = fpvData["timestamp"] as? String ?? ""
        let manufacturer = fpvData["manufacturer"] as? String ?? ""
        let deviceType = fpvData["device_type"] as? String ?? ""
        let frequency = fpvData["frequency"] as? Int ?? 0
        let bandwidth = fpvData["bandwidth"] as? String ?? ""
        let signalStrength = fpvData["signal_strength"] as? Double ?? 0.0
        let detectionSource = fpvData["detection_source"] as? String ?? ""
        
        let fpvId = "fpv-\(detectionSource)-\(frequency)"
        
        let message = CoTViewModel.CoTMessage(
            uid: fpvId,
            type: "a-f-A-M-F-R",
            lat: "0.0", lon: "0.0", homeLat: "0.0", homeLon: "0.0",
            speed: "0.0", vspeed: "0.0", alt: "0.0",
            pilotLat: "0.0", pilotLon: "0.0",
            description: "FPV Detection: \(deviceType)",
            selfIDText: "FPV \(frequency)MHz \(bandwidth)",
            uaType: .helicopter, idType: "FPV Detection",
            rawMessage: fpvData
        )
        
        cotMessage = message
        
        // Set FPV fields
        cotMessage?.fpvTimestamp = timestamp
        cotMessage?.fpvSource = detectionSource
        cotMessage?.fpvFrequency = frequency
        cotMessage?.fpvBandwidth = bandwidth
        cotMessage?.fpvRSSI = signalStrength
        cotMessage?.manufacturer = manufacturer
        
        return cotMessage
    }

    private func processAuxAdvInd(_ jsonObject: [String: Any]) -> CoTViewModel.CoTMessage? {
        guard let auxAdvInd = jsonObject["AUX_ADV_IND"] as? [String: Any],
              let aext = jsonObject["aext"] as? [String: Any] else {
            return nil
        }
        
        let rssi = auxAdvInd["rssi"] as? Double ?? 0.0
        let timestamp = auxAdvInd["time"] as? String ?? ""
        let advA = aext["AdvA"] as? String ?? ""
        let frequency = jsonObject["frequency"] as? Int ?? 0
        
        let detectionSource = advA.replacingOccurrences(of: " random", with: "")
        let fpvId = "fpv-\(detectionSource)-\(frequency)"
        
        let message = CoTViewModel.CoTMessage(
            uid: fpvId,
            type: "a-f-A-M-F-R",
            lat: "0.0", lon: "0.0", homeLat: "0.0", homeLon: "0.0",
            speed: "0.0", vspeed: "0.0", alt: "0.0",
            pilotLat: "0.0", pilotLon: "0.0",
            description: "FPV Update: \(detectionSource)",
            selfIDText: "FPV \(frequency)MHz Update",
            uaType: .helicopter, idType: "FPV Update",
            rawMessage: jsonObject
        )
        
        cotMessage = message
        
        // Set FPV fields
        cotMessage?.fpvTimestamp = timestamp
        cotMessage?.fpvSource = detectionSource
        cotMessage?.fpvFrequency = frequency
        cotMessage?.fpvRSSI = rssi
        cotMessage?.aa = auxAdvInd["aa"] as? Int
        
        return cotMessage
    }
    
    // MARK: - Parsing helpers
    
    private func parseRemarks(_ remarks: String) {
        let components = remarks.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for component in components {
            
            if component.hasPrefix("CPU Usage:") {
                cpuUsage = Double(component.replacingOccurrences(of: "CPU Usage: ", with: "").replacingOccurrences(of: "%", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Total:") {
                memoryTotal = Double(component.replacingOccurrences(of: "Memory Total: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Available:") {
                memoryAvailable = Double(component.replacingOccurrences(of: "Memory Available: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Disk Total:") {
                diskTotal = Double(component.replacingOccurrences(of: "Disk Total: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Disk Used:") {
                diskUsed = Double(component.replacingOccurrences(of: "Disk Used: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Temperature:") {
                temperature = Double(component.replacingOccurrences(of: "Temperature: ", with: "").replacingOccurrences(of: "°C", with: "")) ?? 0.0
            } else if component.hasPrefix("Uptime:") {
                uptime = Double(component.replacingOccurrences(of: "Uptime: ", with: "").replacingOccurrences(of: " seconds", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Used:") {
                memoryUsed = Double(component.replacingOccurrences(of: "Memory Used: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Free:") {
                memoryFree = Double(component.replacingOccurrences(of: "Memory Free: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Active:") {
                memoryActive = Double(component.replacingOccurrences(of: "Memory Active: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Inactive:") {
                memoryInactive = Double(component.replacingOccurrences(of: "Memory Inactive: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Buffers:") {
                memoryBuffers = Double(component.replacingOccurrences(of: "Memory Buffers: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Shared:") {
                memoryShared = Double(component.replacingOccurrences(of: "Memory Shared: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Cached:") {
                memoryCached = Double(component.replacingOccurrences(of: "Memory Cached: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Slab:") {
                memorySlab = Double(component.replacingOccurrences(of: "Memory Slab: ", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0.0
            } else if component.hasPrefix("Memory Percent:") {
                memoryPercent = Double(component.replacingOccurrences(of: "Memory Percent: ", with: "").replacingOccurrences(of: " percent", with: "")) ?? 0.0
            } else if component.hasPrefix("Pluto Temp:") {
                plutoTemp = Double(component.replacingOccurrences(of: "Pluto Temp: ", with: "").replacingOccurrences(of: "°C", with: "")) ?? 0.0
            } else if component.hasPrefix("Zynq Temp:") {
                zynqTemp = Double(component.replacingOccurrences(of: "Zynq Temp: ", with: "").replacingOccurrences(of: "°C", with: "")) ?? 0.0
            } else if component.hasPrefix("GPS Course:") {
                gps_course = Double(component.replacingOccurrences(of: "GPS Course: ", with: "").replacingOccurrences(of: "°", with: "")) ?? 0.0
            } else if component.hasPrefix("GPS Speed:") {
                gps_speed = Double(component.replacingOccurrences(of: "GPS Speed: ", with: "").replacingOccurrences(of: " m/s", with: "")) ?? 0.0
            }
        }
    }
    
    private func parseDroneRemarks(_ remarks: String) -> (
        mac: String?,
        rssi: Int?,
        caaReg: String?,
        idRegType: String?,
        manufacturer: String?,
        protocolVersion: String?,
        description: String?,
        speed: Double?,
        vspeed: Double?,
        alt: Double?,
        heightAGL: Double?,
        heightType: String?,
        pressureAltitude: Double?,
        ewDirSegment: String?,
        speedMultiplier: Double?,
        opStatus: String?,
        direction: Double?,
        timestamp: String?,
        runtime: String?,
        index: String?,
        status: String?,
        altPressure: Double?,
        horizAcc: Int?,
        vertAcc: String?,
        baroAcc: Int?,
        speedAcc: Int?,
        selfIDtext: String?,
        selfIDDesc: String?,
        operatorID: String?,
        uaType: String?,
        operatorLat: Double?,
        operatorLon: Double?,
        operatorAltGeo: Double?,
        classification: Int?,
        channel: Int?, phy: Int?,
        accessAddress: Int?,
        advMode: String?,
        deviceId: Int?,
        sequenceId: Int?,
        advAddress: String?,
        timestampAdv: Double?,
        homeLat: Double?,
        homeLon: Double?,
        trackCourse: String?,
        trackSpeed: String?,
        freq: Double?,
        seenBy: String?,
        observedAt: Double?,
        ridTimestamp: String?,
        ridMake: String?,
        ridModel: String?,
        ridSource: String?
    ) {
        var mac: String?
        var rssi: Int?
        var caaReg: String?
        var idRegType: String?
        var protocolVersion: String?
        var description: String?
        var speed: Double?
        var vspeed: Double?
        var alt: Double?
        var heightAGL: Double?
        var heightType: String?
        var pressureAltitude: Double?
        var ewDirSegment: String?
        var speedMultiplier: Double?
        var opStatus: String?
        var direction: Double?
        var timestamp: String?
        var runtime: String?
        var index: String?
        var status: String?
        var altPressure: Double?
        var horizAcc: Int?
        var vertAcc: String?
        var baroAcc: Int?
        var speedAcc: Int?
        var selfIDtext: String?
        var selfIDDesc: String?
        var operatorID: String?
        var uaType: String?
        var operatorLat: Double?
        var operatorLon: Double?
        var operatorAltGeo: Double?
        var classification: Int?
        var manufacturer: String?
        var channel: Int?
        var phy: Int?
        var accessAddress: Int?
        var advMode: String?
        var deviceId: Int?
        var sequenceId: Int?
        var advAddress: String?
        var timestampAdv: Double?
        var homeLat: Double?
        var homeLon: Double?
        var trackCourse: String?
        var trackSpeed: String?
        
        // Backend metadata variables
        var freq: Double?
        var seenBy: String?
        var observedAt: Double?
        var ridTimestamp: String?
        
        // FAA RID enrichment variables
        var ridMake: String?
        var ridModel: String?
        var ridSource: String?
        
        // First, extract and preserve special blocks that contain internal commas
        var specialBlocks: [String: String] = [:]
        var workingRemarks = remarks
        
        // Extract System block
        if let systemRange = remarks.range(of: "System: \\[[^\\]]+\\]", options: .regularExpression) {
            let systemBlock = String(remarks[systemRange])
            specialBlocks["SYSTEM_BLOCK"] = systemBlock
            workingRemarks = workingRemarks.replacingOccurrences(of: systemBlock, with: "SYSTEM_BLOCK")
        }
        
        // Extract Location/Vector block
        if let locationRange = remarks.range(of: "Location/Vector: \\[[^\\]]+\\]", options: .regularExpression) {
            let locationBlock = String(remarks[locationRange])
            specialBlocks["LOCATION_BLOCK"] = locationBlock
            workingRemarks = workingRemarks.replacingOccurrences(of: locationBlock, with: "LOCATION_BLOCK")
        }
        
        // Now normalize and split
        let normalized = workingRemarks.replacingOccurrences(of: "; ", with: "|")
            .replacingOccurrences(of: ", ", with: "|")
        var components = normalized.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Restore special blocks
        for i in 0..<components.count {
            if let block = specialBlocks[components[i]] {
                components[i] = block
            }
        }
        
        
        print("DEBUG: REMARKS COMPONENTS: \(components)")
        
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("MAC:") {
                mac = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first
            } else if trimmed.hasPrefix("RSSI:") {
                rssi = Int(trimmed.dropFirst(5).replacingOccurrences(of: "dBm", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("ID Type:") {
                idRegType = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if idRegType?.contains("CAA") == true {
                    if let droneId = eventAttributes["uid"] {
                        caaReg = droneId.replacingOccurrences(of: "drone-", with: "")
                    }
                }
            } else if trimmed.hasPrefix("UA Type:") {
                uaType = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Manufacturer:") {
                let mfr = trimmed.dropFirst(13).trimmingCharacters(in: .whitespaces)
                // Only set manufacturer if it's not empty and not "Unknown"
                if !mfr.isEmpty && mfr != "Unknown" {
                    manufacturer = mfr
                }
            } else if trimmed.hasPrefix("Channel:") {
                channel = Int(trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("PHY:") {
                phy = Int(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Operator ID:") {
                operatorID = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Access Address:") {
                accessAddress = Int(trimmed.dropFirst(15).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Advertisement Mode:") {
                advMode = trimmed.dropFirst(18).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Device ID:") {
                deviceId = Int(trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Sequence ID:") {
                sequenceId = Int(trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Advertisement Address:") {
                advAddress = trimmed.dropFirst(21).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Advertisement Timestamp:") {
                if let tsStr = trimmed.dropFirst(23).trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first {
                    timestampAdv = Double(tsStr)
                }
            } else if trimmed.lowercased().hasPrefix("course:") {
                let raw = trimmed.dropFirst("course:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "°", with: "")
                if let val = Double(raw) {
                    trackCourse = String(val)
                }
            } else if trimmed.lowercased().hasPrefix("speed:") {
                let raw = trimmed.dropFirst("speed:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                    .first ?? ""
                if let val = Double(raw) {
                    trackSpeed = String(val)
                    speed = val
                }
            } else if trimmed.hasPrefix("Protocol Version:") {
                protocolVersion = trimmed.dropFirst(17).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Description:") {
                description = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Speed:") {
                speed = Double(trimmed.dropFirst(6).replacingOccurrences(of: "m/s", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Vert Speed:") {
                vspeed = Double(trimmed.dropFirst(11).replacingOccurrences(of: "m/s", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Geodetic Altitude:") {
                alt = Double(trimmed.dropFirst(18).replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Height AGL:") {
                heightAGL = Double(trimmed.dropFirst(11).replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Height Type:") {
                heightType = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Pressure Altitude:") {
                pressureAltitude = Double(trimmed.dropFirst(18).replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("EW Direction Segment:") {
                ewDirSegment = trimmed.dropFirst(21).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Speed Multiplier:") {
                speedMultiplier = Double(trimmed.dropFirst(17).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Operational Status:") {
                opStatus = trimmed.dropFirst(19).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Direction:") {
                direction = Double(trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Timestamp:") {
                timestamp = trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Runtime:") {
                let runtimeStr = trimmed.dropFirst(8)
                    .replacingOccurrences(of: "]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                runtime = runtimeStr
            } else if trimmed.hasPrefix("Index:") {
                let indexStr = trimmed.dropFirst(6)
                    .replacingOccurrences(of: "]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                index = indexStr
            } else if trimmed.hasPrefix("Status:") {
                status = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Alt Pressure:") {
                altPressure = Double(trimmed.dropFirst(13).replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Horizontal Accuracy:") {
                horizAcc = Int(trimmed.dropFirst(20).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Vertical Accuracy:") {
                vertAcc = trimmed.dropFirst(18).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Baro Accuracy:") {
                baroAcc = Int(trimmed.dropFirst(14).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Speed Accuracy:") {
                speedAcc = Int(trimmed.dropFirst(15).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("Text:") {
                selfIDtext = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Self-ID Message: Text:") {
                selfIDtext = trimmed.dropFirst(22).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Self-ID Message: Description:") {
                selfIDDesc = trimmed.dropFirst(30).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("SelfID Description:") {
                selfIDDesc = trimmed.dropFirst(19).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("System:") {
                // Parse System message which is formatted as: System: [Operator Lat: X, Operator Lon: Y, Home Lat: Z, Home Lon: W]
                print("DEBUG: Found System block: \(trimmed)")
                let content = trimmed.components(separatedBy: "[").last?
                    .replacingOccurrences(of: "]", with: "") ?? ""
                print("DEBUG: System content: '\(content)'")
                let systemParts = content.components(separatedBy: ", ")
                print("DEBUG: System parts: \(systemParts)")
                for part in systemParts {
                    let clean = part.trimmingCharacters(in: .whitespaces)
                    if clean.hasPrefix("Operator Lat:") {
                        operatorLat = Double(clean.dropFirst(13)
                            .trimmingCharacters(in: .whitespaces))
                        print("DEBUG: Extracted operator lat: \(String(describing: operatorLat))")
                    } else if clean.hasPrefix("Operator Lon:") {
                        operatorLon = Double(clean.dropFirst(13)
                            .trimmingCharacters(in: .whitespaces))
                        print("DEBUG: Extracted operator lon: \(String(describing: operatorLon))")
                    } else if clean.hasPrefix("Home Lat:") {
                        homeLat = Double(clean.dropFirst(9)
                            .trimmingCharacters(in: .whitespaces))
                        print("DEBUG: Extracted home lat: \(String(describing: homeLat))")
                    } else if clean.hasPrefix("Home Lon:") {
                        homeLon = Double(clean.dropFirst(9)
                            .trimmingCharacters(in: .whitespaces))
                        print("DEBUG: Extracted home lon: \(String(describing: homeLon))")
                    }
                }
            } else if trimmed.contains("Location/Vector:") {
                let content = trimmed.components(separatedBy: "[").last?
                    .replacingOccurrences(of: "]", with: "") ?? ""
                let vectorParts = content.components(separatedBy: ",")
                for part in vectorParts {
                    let clean = part.trimmingCharacters(in: .whitespaces)
                    if clean.hasPrefix("Speed:") {
                        speed = Double(clean.dropFirst(6)
                            .replacingOccurrences(of: "m/s", with: "")
                            .trimmingCharacters(in: .whitespaces))
                    } else if clean.hasPrefix("Vert Speed:") {
                        vspeed = Double(clean.dropFirst(11)
                            .replacingOccurrences(of: "m/s", with: "")
                            .trimmingCharacters(in: .whitespaces))
                    } else if clean.hasPrefix("Geodetic Altitude:") {
                        alt = Double(clean.dropFirst(18)
                            .replacingOccurrences(of: "m", with: "")
                            .trimmingCharacters(in: .whitespaces))
                    } else if clean.hasPrefix("Height AGL:") {
                        heightAGL = Double(clean.dropFirst(11)
                            .replacingOccurrences(of: "m", with: "")
                            .trimmingCharacters(in: .whitespaces))
                    }
                }
            } else if trimmed.hasPrefix("Self-ID:") {
                description = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("FPV Update") || trimmed.hasPrefix("FPV Detection") {
                   // Extract RSSI from FPV format
                   if let rssiMatch = trimmed.range(of: "RSSI: ([-]?\\d+(?:\\.\\d+)?)dBm", options: .regularExpression) {
                       let rssiStr = trimmed[rssiMatch].replacingOccurrences(of: "RSSI: ", with: "").replacingOccurrences(of: "dBm", with: "")
                       rssi = Int(Double(rssiStr) ?? 0)
                   }
                   
                   // Extract frequency
                   if let freqMatch = trimmed.range(of: "Frequency: (\\d+(?:\\.\\d+)?)", options: .regularExpression) {
                       let freqStr = trimmed[freqMatch].replacingOccurrences(of: "Frequency: ", with: "").replacingOccurrences(of: " MHz", with: "")
                       fpvFrequency = freqStr
                   }
                   
                   // Extract source
                   if let sourceMatch = trimmed.range(of: "Source: ([^,]+)", options: .regularExpression) {
                       let sourceStr = trimmed[sourceMatch].replacingOccurrences(of: "Source: ", with: "")
                       fpvSource = sourceStr
                   }
            // Parse backend metadata fields from dragonsync.py
            } else if trimmed.hasPrefix("Frequency:") {
                // Parse frequency in MHz format: "Frequency: 5785.000 MHz"
                let freqStr = trimmed.dropFirst(10)
                    .replacingOccurrences(of: " MHz", with: "")
                    .trimmingCharacters(in: .whitespaces)
                freq = Double(freqStr)
            } else if trimmed.hasPrefix("SeenBy:") {
                seenBy = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("ObservedAt:") {
                // Parse ISO8601 timestamp and convert to Unix timestamp
                let dateStr = trimmed.dropFirst(11).trimmingCharacters(in: .whitespaces)
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateStr) {
                    observedAt = date.timeIntervalSince1970
                }
            } else if trimmed.hasPrefix("RID_TS:") {
                ridTimestamp = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            // Parse FAA RID enrichment fields
            } else if trimmed.hasPrefix("RID:") {
                // Parse "RID: Make Model (source)"
                let ridStr = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                
                // Extract source in parentheses
                if let sourceStart = ridStr.lastIndex(of: "("),
                   let sourceEnd = ridStr.lastIndex(of: ")") {
                    ridSource = String(ridStr[ridStr.index(after: sourceStart)..<sourceEnd])
                    
                    // Extract make/model before parentheses
                    let makeModelStr = ridStr[..<sourceStart].trimmingCharacters(in: .whitespaces)
                    let components = makeModelStr.components(separatedBy: " ")
                    if components.count >= 2 {
                        ridMake = components[0]
                        ridModel = components.dropFirst().joined(separator: " ")
                        ridLookupSuccess = true
                    }
                } else {
                    // No source info, just make/model - set source to "UNKNOWN"
                    ridSource = "UNKNOWN"
                    let components = ridStr.components(separatedBy: " ")
                    if components.count >= 2 {
                        ridMake = components[0]
                        ridModel = components.dropFirst().joined(separator: " ")
                        ridLookupSuccess = true
                    }
                }
               }
        }
        
        // Only try MAC-based manufacturer lookup if not already set from remarks
        if manufacturer == nil, let mac = mac {
            print("MAC is \(mac)")
            let cleanMac = mac.replacingOccurrences(of: ":", with: "").uppercased()
            for (brand, prefixes) in macPrefixesByManufacturer {
                for prefix in prefixes {
                    let cleanPrefix = prefix.replacingOccurrences(of: ":", with: "").uppercased()
                    if cleanMac.hasPrefix(cleanPrefix) {
                        manufacturer = brand
                        print("Match found! Manufacturer: \(manufacturer ?? "nil")")
                        break
                    }
                }
                if manufacturer != nil { break }
            }
        }
        
        return (
            mac: mac,
            rssi: rssi,
            caaReg: caaReg,
            idRegType: idRegType,
            manufacturer: manufacturer,
            protocolVersion: protocolVersion,
            description: description,
            speed: speed,
            vspeed: vspeed,
            alt: alt,
            heightAGL: heightAGL,
            heightType: heightType,
            pressureAltitude: pressureAltitude,
            ewDirSegment: ewDirSegment,
            speedMultiplier: speedMultiplier,
            opStatus: opStatus,
            direction: direction,
            timestamp: timestamp,
            runtime: runtime,
            index: index,
            status: status,
            altPressure: altPressure,
            horizAcc: horizAcc,
            vertAcc: vertAcc,
            baroAcc: baroAcc,
            speedAcc: speedAcc,
            selfIDtext: selfIDtext,
            selfIDDesc: selfIDDesc,
            operatorID: operatorID,
            uaType: uaType,
            operatorLat: operatorLat,
            operatorLon: operatorLon,
            operatorAltGeo: operatorAltGeo,
            classification: classification,
            channel: channel,
            phy: phy,
            accessAddress: accessAddress,
            advMode: advMode,
            deviceId: deviceId,
            sequenceId: sequenceId,
            advAddress: advAddress,
            timestampAdv: timestampAdv,
            homeLat: homeLat,
            homeLon: homeLon,
            trackCourse: trackCourse,
            trackSpeed: trackSpeed,
            freq: freq,
            seenBy: seenBy,
            observedAt: observedAt,
            ridTimestamp: ridTimestamp,
            ridMake: ridMake,
            ridModel: ridModel,
            ridSource: ridSource
        )
    }
    
    
    
    private func handleLocationFields(_ elementName: String) {
        if cotMessage == nil { return }
        
        switch elementName {
        case "location_protocol":
            cotMessage?.location_protocol = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["protocol_version"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "op_status":
            cotMessage?.op_status = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["op_status"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "height_type":
            cotMessage?.height_type = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["height_type"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "ew_dir_segment":
            cotMessage?.ew_dir_segment = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["ew_dir_segment"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "speed_multiplier":
            cotMessage?.speed_multiplier = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["speed_multiplier"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "vertical_accuracy":
            cotMessage?.vertical_accuracy = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["vertical_accuracy"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "horizontal_accuracy":
            cotMessage?.horizontal_accuracy = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["horizontal_accuracy"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "baro_accuracy":
            cotMessage?.baro_accuracy = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["baro_accuracy"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "speed_accuracy":
            cotMessage?.speed_accuracy = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["speed_accuracy"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "timestamp":
            cotMessage?.timestamp = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["timestamp"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "timestamp_accuracy":
            cotMessage?.timestamp_accuracy = currentValue
            if var raw = cotMessage?.rawMessage {
                if var location = raw["Location/Vector Message"] as? [String: Any] {
                    location["timestamp_accuracy"] = currentValue
                    raw["Location/Vector Message"] = location
                    cotMessage?.rawMessage = raw
                }
            }
            
        default: break
        }
    }
    
    private func handleTransmissionFields(_ elementName: String) {
        if cotMessage == nil { return }
        
        switch elementName {
        case "operator_id":
            cotMessage?.operator_id = currentValue
            if var raw = cotMessage?.rawMessage {
                if var opMsg = raw["Operator ID Message"] as? [String: Any] {
                    opMsg["operator_id"] = currentValue
                    raw["Operator ID Message"] = opMsg
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "operator_id_type":
            cotMessage?.operator_id_type = currentValue
            if var raw = cotMessage?.rawMessage {
                if var opMsg = raw["Operator ID Message"] as? [String: Any] {
                    opMsg["operator_id_type"] = currentValue
                    raw["Operator ID Message"] = opMsg
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "aux_rssi":
            aux_rssi = Int(currentValue)
            if var raw = cotMessage?.rawMessage {
                if var auxData = raw["AUX_ADV_IND"] as? [String: Any] {
                    auxData["rssi"] = aux_rssi
                    raw["AUX_ADV_IND"] = auxData
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "channel":
            channel = Int(currentValue)
            if var raw = cotMessage?.rawMessage {
                if var auxData = raw["AUX_ADV_IND"] as? [String: Any] {
                    auxData["chan"] = channel
                    raw["AUX_ADV_IND"] = auxData
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "phy":
            phy = Int(currentValue)
            if var raw = cotMessage?.rawMessage {
                if var auxData = raw["AUX_ADV_IND"] as? [String: Any] {
                    auxData["phy"] = phy
                    raw["AUX_ADV_IND"] = auxData
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "aa":
            aa = Int(currentValue)
            if var raw = cotMessage?.rawMessage {
                if var auxData = raw["AUX_ADV_IND"] as? [String: Any] {
                    auxData["aa"] = aa
                    raw["AUX_ADV_IND"] = auxData
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "adv_mode":
            adv_mode = currentValue
            if var raw = cotMessage?.rawMessage {
                if var aextData = raw["aext"] as? [String: Any] {
                    aextData["AdvMode"] = adv_mode
                    raw["aext"] = aextData
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "adv_mac":
            adv_mac = currentValue
            if var raw = cotMessage?.rawMessage {
                if var aextData = raw["aext"] as? [String: Any] {
                    aextData["AdvA"] = adv_mac
                    raw["aext"] = aextData
                    cotMessage?.rawMessage = raw
                }
            }
            
        case "did":
            did = Int(currentValue)
            if var raw = cotMessage?.rawMessage {
                if var aextData = raw["aext"] as? [String: Any] {
                    if var advInfo = aextData["AdvDataInfo"] as? [String: Any] {
                        advInfo["did"] = did
                        aextData["AdvDataInfo"] = advInfo
                        raw["aext"] = aextData
                        cotMessage?.rawMessage = raw
                    }
                }
            }
            
        case "sid":
            sid = Int(currentValue)
            if var raw = cotMessage?.rawMessage {
                if var aextData = raw["aext"] as? [String: Any] {
                    if var advInfo = aextData["AdvDataInfo"] as? [String: Any] {
                        advInfo["sid"] = sid
                        aextData["AdvDataInfo"] = advInfo
                        raw["aext"] = aextData
                        cotMessage?.rawMessage = raw
                    }
                }
            }
            
        default: break
        }
    }
    
    private func buildRawMessage(_ mac: String?, _ rssi: Int?, _ desc: String?) -> [String: Any] {
        var raw: [String: Any] = [:]
        
        // Basic ID section
        var basicId: [String: Any] = [:]
        if let mac = mac { basicId["MAC"] = mac }
        if let rssi = rssi { basicId["RSSI"] = rssi }
        if let desc = desc { basicId["description"] = desc }
        if !basicId.isEmpty { raw["Basic ID"] = basicId }
        
        // Location/Vector section
        var location: [String: Any] = [:]
        if let protocol_version = location_protocol { location["protocol_version"] = protocol_version }
        if let op_status = op_status { location["op_status"] = op_status }
        if let height_type = height_type { location["height_type"] = height_type }
        if let ew_dir_segment = ew_dir_segment { location["ew_dir_segment"] = ew_dir_segment }
        if let speed_multiplier = speed_multiplier { location["speed_multiplier"] = speed_multiplier }
        if let vertical_accuracy = vertical_accuracy { location["vertical_accuracy"] = vertical_accuracy }
        if let horizontal_accuracy = horizontal_accuracy { location["horizontal_accuracy"] = horizontal_accuracy }
        if let baro_accuracy = baro_accuracy { location["baro_accuracy"] = baro_accuracy }
        if let speed_accuracy = speed_accuracy { location["speed_accuracy"] = speed_accuracy }
        if let timestamp = timestamp { location["timestamp"] = timestamp }
        if let timestamp_accuracy = timestamp_accuracy { location["timestamp_accuracy"] = timestamp_accuracy }
        if !location.isEmpty { raw["Location/Vector Message"] = location }
        
        // Transmission data section
        if let aux_rssi = aux_rssi,
           let channel = channel,
           let phy = phy {
            raw["AUX_ADV_IND"] = [
                "rssi": aux_rssi,
                "chan": channel,
                "phy": phy,
                "aa": aa ?? 0
            ]
        }
        
        // Advertisement data section
        if let adv_mode = adv_mode,
           let adv_mac = adv_mac,
           let did = did,
           let sid = sid {
            raw["aext"] = [
                "AdvMode": adv_mode,
                "AdvA": adv_mac,
                "AdvDataInfo": [
                    "did": did,
                    "sid": sid
                ]
            ]
        }
        
        return raw
    }
    
    private func buildIdType() -> String {
        if eventAttributes["type"]?.contains("-S") == true {
            return "Serial Number (ANSI/CTA-2063-A)"
        } else if eventAttributes["type"]?.contains("-R") == true {
            return "CAA Assigned Registration ID"
        }
        return ""
    }
    
    private func mapUAType(_ typeStr: String?) -> DroneSignature.IdInfo.UAType {
        guard let typeStr = typeStr else { return .helicopter }
        switch typeStr {
        case "Helicopter (or Multirotor)": return .helicopter
        case "Aeroplane", "Airplane": return .aeroplane
        case "Gyroplane": return .gyroplane
        case "Hybrid Lift": return .hybridLift
        case "Ornithopter": return .ornithopter
        case "Glider": return .glider
        case "Kite": return .kite
        case "Free Balloon": return .freeballoon
        case "Captive Balloon": return .captive
        case "Airship": return .airship
        case "Free Fall/Parachute": return .freeFall
        case "Rocket": return .rocket
        case "Tethered Powered Aircraft": return .tethered
        case "Ground Obstacle": return .groundObstacle
        default: return .helicopter
        }
    }
    
    private func mapUAType(_ typeInt: Int) -> DroneSignature.IdInfo.UAType {
        switch typeInt {
        case 0: return .none
        case 1: return .aeroplane
        case 2: return .helicopter
        case 3: return .gyroplane
        case 4: return .hybridLift
        case 5: return .ornithopter
        case 6: return .glider
        case 7: return .kite
        case 8: return .freeballoon
        case 9: return .captive
        case 10: return .airship
        case 11: return .freeFall
        case 12: return .rocket
        case 13: return .tethered
        case 14: return .groundObstacle
        default: return .helicopter
        }
    }
}
