//
//  CoTMessage+TAK.swift
//  WarDragon
//
//  Extension to convert CoT messages to TAK CoT XML format
//  Matches Python DragonSync drone.to_cot_xml() functionality
//

import Foundation

extension CoTViewModel.CoTMessage {
    
    /// Convert drone message to TAK CoT XML
    /// Matches Python DragonSync Drone.to_cot_xml() format
    func toCoTXML() -> String {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let time = formatter.string(from: now)
        let stale = formatter.string(from: now.addingTimeInterval(60.0)) // 60 second stale time for drones
        
        // Coordinates - use drone location
        let lat = self.lat
        let lon = self.lon
        let alt = self.alt
        let ce = "10.0"  // Circular error (meters)
        let le = "15.0"  // Linear error (meters)
        let hae = alt  // Height above ellipsoid
        
        // Build CoT type from message type or construct from properties
        let cotType = self.type.isEmpty ? buildCoTType() : self.type
        
        // Build remarks with all metadata (matching Python format)
        let remarksContent = buildRemarks()
        
        // Build CoT XML
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<event version=\"2.0\" uid=\"\(uid)\" type=\"\(cotType)\" time=\"\(time)\" start=\"\(time)\" stale=\"\(stale)\" how=\"m-g\">\n"
        xml += "  <point lat=\"\(lat)\" lon=\"\(lon)\" hae=\"\(hae)\" ce=\"\(ce)\" le=\"\(le)\"/>\n"
        
        // Add track element if we have course/speed
        if let course = trackCourse, let speed = trackSpeed, !course.isEmpty, !speed.isEmpty {
            xml += "  <track course=\"\(course)\" speed=\"\(speed)\"/>\n"
        }
        
        xml += "  <detail>\n"
        
        // Contact callsign - use description or ID
        let callsign = description.isEmpty ? uid : description
        xml += "    <contact callsign=\"\(xmlEscape(callsign))\"/>\n"
        
        // Group and status
        xml += "    <__group name=\"Cyan\" role=\"Team Member\"/>\n"
        xml += "    <precisionlocation altsrc=\"GPS\" geopointsrc=\"GPS\"/>\n"
        xml += "    <status readiness=\"true\"/>\n"
        xml += "    <takv device=\"WarDragon iOS\" platform=\"Drone\" os=\"RemoteID\" version=\"1.0\"/>\n"
        
        // Remarks with all metadata
        xml += "    <remarks>\(xmlEscape(remarksContent))</remarks>\n"
        
        xml += "  </detail>\n"
        xml += "</event>\n"
        
        return xml
    }
    
    /// Build CoT type string based on drone properties
    /// Format: a-u-A-M-H-{R|S|U}-{O}
    /// - a: Atom (core CoT element)
    /// - u: Unmanned (UAS)
    /// - A: Air
    /// - M: Military
    /// - H: Helicopter/Multirotor
    /// - R: CAA Registration / S: Serial Number / U: Unknown ID
    /// - O: Has operator location
    private func buildCoTType() -> String {
        var type = "a-u-A-M-H"
        
        // Add ID type suffix
        if !idType.isEmpty {
            if idType.contains("CAA") {
                type += "-R"
            } else if idType.contains("Serial") {
                type += "-S"
            } else {
                type += "-U"
            }
        } else {
            type += "-U"
        }
        
        // Add operator suffix if we have operator location
        if let pilotLatValue = Double(pilotLat), let pilotLonValue = Double(pilotLon),
           pilotLatValue != 0.0 && pilotLonValue != 0.0 {
            type += "-O"
        }
        
        return type
    }
    
    /// Build remarks field with all metadata (matching Python format)
    private func buildRemarks() -> String {
        var parts: [String] = []
        
        // MAC and RSSI
        if let mac = mac, !mac.isEmpty {
            parts.append("MAC: \(mac)")
        }
        if let rssi = rssi {
            parts.append("RSSI: \(rssi)dBm")
        }
        
        // Manufacturer
        if let mfr = manufacturer, !mfr.isEmpty, mfr != "Unknown" {
            parts.append("Manufacturer: \(mfr)")
        }
        
        // ID Type
        if !idType.isEmpty {
            parts.append("ID Type: \(idType)")
        }
        
        // UA Type
        parts.append("UA Type: \(uaType.rawValue)")
        
        // Protocol Version
        if let protocolVer = protocolVersion, !protocolVer.isEmpty {
            parts.append("Protocol Version: \(protocolVer)")
        }
        
        // Location/Vector block
        var locationParts: [String] = []
        locationParts.append("Speed: \(speed)m/s")
        locationParts.append("Vert Speed: \(vspeed)m/s")
        locationParts.append("Geodetic Altitude: \(alt)m")
        if let height = height, !height.isEmpty {
            locationParts.append("Height AGL: \(height)m")
        }
        if let direction = direction, !direction.isEmpty {
            locationParts.append("Direction: \(direction)°")
        }
        parts.append("Location/Vector: [\(locationParts.joined(separator: ", "))]")
        
        // System block (operator and home location)
        var systemParts: [String] = []
        if let pilotLatValue = Double(pilotLat), let pilotLonValue = Double(pilotLon),
           pilotLatValue != 0.0 && pilotLonValue != 0.0 {
            systemParts.append("Operator Lat: \(pilotLatValue)")
            systemParts.append("Operator Lon: \(pilotLonValue)")
        }
        if let homeLatValue = Double(homeLat), let homeLonValue = Double(homeLon),
           homeLatValue != 0.0 && homeLonValue != 0.0 {
            systemParts.append("Home Lat: \(homeLatValue)")
            systemParts.append("Home Lon: \(homeLonValue)")
        }
        if !systemParts.isEmpty {
            parts.append("System: [\(systemParts.joined(separator: ", "))]")
        }
        
        // Operational Status
        if let status = op_status, !status.isEmpty {
            parts.append("Operational Status: \(status)")
        }
        
        // Height Type
        if let heightType = height_type, !heightType.isEmpty {
            parts.append("Height Type: \(heightType)")
        }
        
        // Accuracies
        if let horizAcc = horizontal_accuracy, !horizAcc.isEmpty {
            parts.append("Horizontal Accuracy: \(horizAcc)")
        }
        if let vertAcc = vertical_accuracy, !vertAcc.isEmpty {
            parts.append("Vertical Accuracy: \(vertAcc)")
        }
        if let baroAcc = baro_accuracy, !baroAcc.isEmpty {
            parts.append("Baro Accuracy: \(baroAcc)")
        }
        if let speedAcc = speed_accuracy, !speedAcc.isEmpty {
            parts.append("Speed Accuracy: \(speedAcc)")
        }
        
        // Timestamp
        if let timestamp = timestamp, !timestamp.isEmpty {
            parts.append("Timestamp: \(timestamp)")
        }
        
        // Operator ID
        if let opID = operator_id, !opID.isEmpty {
            parts.append("Operator ID: \(opID)")
        }
        
        // Self-ID text/description
        if !selfIDText.isEmpty {
            parts.append("Self-ID: \(selfIDText)")
        } else if !description.isEmpty {
            parts.append("Description: \(description)")
        }
        
        // Backend metadata (from dragonsync.py)
        if let freq = freq {
            // Format frequency - if > 100000 it's in Hz, otherwise MHz
            if freq > 100000 {
                parts.append("Freq: \(String(format: "%.0f", freq)) Hz")
            } else {
                parts.append("Freq: \(String(format: "%.2f", freq)) MHz")
            }
        }
        if let seenByValue = seenBy, !seenByValue.isEmpty {
            parts.append("Seen By: \(seenByValue)")
        }
        if let observedAt = observedAt {
            parts.append("Observed At: \(String(format: "%.3f", observedAt))")
        }
        if let ridTimestamp = ridTimestamp, !ridTimestamp.isEmpty {
            parts.append("RID Time: \(ridTimestamp)")
        }
        
        // FAA RID enrichment
        if let make = ridMake, let model = ridModel, !make.isEmpty, !model.isEmpty {
            let source = ridSource ?? "UNKNOWN"
            parts.append("RID: \(make) \(model) (\(source))")
        }
        
        // Index and runtime
        if let index = index, !index.isEmpty {
            parts.append("Index: \(index)")
        }
        if let runtimeValue = runtime, !runtimeValue.isEmpty {
            parts.append("Runtime: \(runtimeValue)")
        }
        
        return parts.joined(separator: ", ")
    }
    
    /// Escape XML special characters
    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Extension for aircraft/ADS-B tracks to CoT XML
extension Aircraft {
    
    /// Convert ADS-B aircraft to TAK CoT XML
    /// Matches Python aircraft.py format
    func toCoTXML(seenBy: String? = nil) -> String {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let time = formatter.string(from: now)
        let stale = formatter.string(from: now.addingTimeInterval(15.0)) // 15 second stale for aircraft
        
        // Use ADS-B coordinate
        let latValue = lat ?? 0.0
        let lonValue = lon ?? 0.0
        let altValue = altitude ?? 0.0
        let latStr = String(format: "%.6f", latValue)
        let lonStr = String(format: "%.6f", lonValue)
        let altStr = String(format: "%.1f", altValue)
        let ce = "50.0"  // Circular error (meters) - aircraft less precise
        let le = "100.0"  // Linear error (meters)
        let hae = altStr
        
        // CoT type for aircraft: a-f-A (Friendly-Air)
        let cotType = "a-f-A"
        
        // UID: adsb-{hex}
        let uid = "adsb-\(hex)"
        
        // Build callsign
        let flightStr = flight ?? ""
        let callsign = !flightStr.isEmpty ? flightStr.trimmingCharacters(in: .whitespaces) : hex
        
        // Build remarks
        var parts: [String] = []
        parts.append("ICAO: \(hex)")
        if !flightStr.isEmpty {
            parts.append("Flight: \(flightStr)")
        }
        parts.append("Altitude: \(Int(altValue))ft")
        let speedValue = groundSpeed ?? 0.0
        parts.append("Speed: \(Int(speedValue))kts")
        if let track = track {
            parts.append("Track: \(Int(track))°")
        }
        if let vertRate = verticalRate {
            parts.append("Vert Rate: \(Int(vertRate))ft/min")
        }
        if let categoryStr = category, !categoryStr.isEmpty {
            parts.append("Category: \(categoryStr)")
        }
        if let seenByStr = seenBy, !seenByStr.isEmpty {
            parts.append("Seen By: \(seenByStr)")
        }
        
        let remarksContent = parts.joined(separator: ", ")
        
        // Build CoT XML
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<event version=\"2.0\" uid=\"\(uid)\" type=\"\(cotType)\" time=\"\(time)\" start=\"\(time)\" stale=\"\(stale)\" how=\"m-g\">\n"
        xml += "  <point lat=\"\(latStr)\" lon=\"\(lonStr)\" hae=\"\(hae)\" ce=\"\(ce)\" le=\"\(le)\"/>\n"
        
        // Add track element if we have heading/speed
        if let track = track {
            xml += "  <track course=\"\(String(format: "%.1f", track))\" speed=\"\(String(format: "%.1f", speedValue * 0.514444))\"/>\n" // Convert knots to m/s
        }
        
        xml += "  <detail>\n"
        xml += "    <contact callsign=\"\(xmlEscape(callsign))\"/>\n"
        xml += "    <__group name=\"Cyan\" role=\"Team Member\"/>\n"
        xml += "    <precisionlocation altsrc=\"GPS\" geopointsrc=\"GPS\"/>\n"
        xml += "    <status readiness=\"true\"/>\n"
        xml += "    <takv device=\"WarDragon iOS\" platform=\"Aircraft\" os=\"ADS-B\" version=\"1.0\"/>\n"
        xml += "    <remarks>\(xmlEscape(remarksContent))</remarks>\n"
        xml += "  </detail>\n"
        xml += "</event>\n"
        
        return xml
    }
    
    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
