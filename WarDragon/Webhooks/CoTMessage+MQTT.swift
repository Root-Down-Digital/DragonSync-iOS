//
//  CoTMessage+MQTT.swift
//  WarDragon
//
//  Extension to convert CoT messages to MQTT payloads
//

import Foundation

extension CoTViewModel.CoTMessage {
    
    /// Convert CoT message to MQTT drone message
    func toMQTTDroneMessage() -> MQTTDroneMessage {
        let lat = Double(lat) ?? 0.0
        let lon = Double(lon) ?? 0.0
        let alt = Double(alt) ?? nil
        let spd = Double(speed) ?? nil
        let dir = Double(direction ?? "") ?? nil
        let pilotLat = Double(pilotLat) ?? nil
        let pilotLon = Double(pilotLon) ?? nil
        let homeLat = Double(homeLat) ?? nil
        let homeLon = Double(homeLon) ?? nil
        
        return MQTTDroneMessage(
            mac: mac ?? uid,
            manufacturer: manufacturer,
            rssi: rssi,
            latitude: lat,
            longitude: lon,
            altitude: alt,
            speed: spd,
            heading: dir,
            pilotLatitude: pilotLat,
            pilotLongitude: pilotLon,
            homeLatitude: homeLat,
            homeLongitude: homeLon,
            timestamp: timestamp ?? ISO8601DateFormatter().string(from: Date()),
            uaType: uaType.rawValue,
            serialNumber: uid,
            caaRegistration: caaRegistration,
            freq: freq,
            seenBy: seen_by,
            observedAt: observed_at
        )
    }
    
    /// Get device name for MQTT and Home Assistant
    var deviceName: String {
        if let caa = caaRegistration, !caa.isEmpty {
            return caa
        }
        
        if let mfr = manufacturer, !mfr.isEmpty {
            return "\(mfr) Drone"
        }
        
        return "Drone \(uid.prefix(8))"
    }
}

// MARK: - System Status Conversion

extension CoTViewModel {
    
    /// Create MQTT system message from current app state
    func createMQTTSystemMessage(dronesTracked: Int) -> MQTTSystemMessage {
        // Get system metrics if available from StatusViewModel
        let cpuUsage: Double? = nil // Implement if needed
        let memoryUsed: Double? = nil // Implement if needed
        let temperature: Double? = nil // From device
        
        return MQTTSystemMessage(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            cpuUsage: cpuUsage,
            memoryUsed: memoryUsed,
            temperature: temperature,
            plutoTemp: nil,  // N/A for iOS
            zynqTemp: nil,   // N/A for iOS
            gpsFix: nil,     // Could add location manager status
            dronesTracked: dronesTracked,
            uptime: nil      // Could track app uptime
        )
    }
}
