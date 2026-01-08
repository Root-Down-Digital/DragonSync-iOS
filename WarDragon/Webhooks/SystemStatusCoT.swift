//
//  SystemStatusCoT.swift
//  WarDragon
//
//  System status to CoT XML converter
//  Matches Python DragonSync SystemStatus.to_cot_xml() functionality
//

import Foundation
import UIKit

extension StatusViewModel.StatusMessage {
    /// Convert system status to CoT XML for TAK/ATAK
    /// Matches Python DragonSync SystemStatus.to_cot_xml() format
    func toCoTXML() -> String {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let time = formatter.string(from: now)
        let stale = formatter.string(from: now.addingTimeInterval(120)) // 2 minutes stale time
        
        // Get kit ID (matches Python: f"wardragon-{serial_number}")
        let kitUID: String
        if !serialNumber.isEmpty && serialNumber != "unknown" {
            kitUID = "wardragon-\(serialNumber)"
        } else if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            let prefix = String(uuid.prefix(8))
            kitUID = "wardragon-\(prefix)"
        } else {
            kitUID = "wardragon-unknown"
        }
        
        // GPS coordinates with validation
        let lat = gpsData.latitude != 0.0 ? gpsData.latitude : 0.0
        let lon = gpsData.longitude != 0.0 ? gpsData.longitude : 0.0
        let alt = gpsData.altitude
        let ce = "10.0"  // Circular error (meters)
        let le = "15.0"  // Linear error (meters)
        let hae = String(format: "%.1f", alt)
        
        // CoT type for ground unit with sensor role
        let cotType = "a-f-G-E-S"  // Friendly-Ground-Equipment-Sensor
        
        // System health metrics (matching Python format)
        let cpuUsage = String(format: "%.1f", systemStats.cpuUsage)
        let memoryPercent = String(format: "%.1f", systemStats.memory.percent)
        let temp = String(format: "%.1f", systemStats.temperature)
        let uptime = String(format: "%.0f", systemStats.uptime)
        
        // ANTSDR temperatures (if available)
        let plutoTemp = antStats.plutoTemp > 0 ? String(format: "%.1f", antStats.plutoTemp) : "N/A"
        let zynqTemp = antStats.zynqTemp > 0 ? String(format: "%.1f", antStats.zynqTemp) : "N/A"
        
        // Memory stats in MB (matching Python)
        let memoryTotal = String(format: "%.0f", Double(systemStats.memory.total) / (1024 * 1024))
        let memoryAvailable = String(format: "%.0f", Double(systemStats.memory.available) / (1024 * 1024))
        
        // Disk stats in MB (matching Python)
        let diskTotal = String(format: "%.0f", Double(systemStats.disk.total) / (1024 * 1024))
        let diskUsed = String(format: "%.0f", Double(systemStats.disk.used) / (1024 * 1024))
        
        // Build CoT XML matching Python format
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<event version=\"2.0\" uid=\"\(kitUID)\" type=\"\(cotType)\" time=\"\(time)\" start=\"\(time)\" stale=\"\(stale)\" how=\"m-g\">\n"
        xml += "  <point lat=\"\(lat)\" lon=\"\(lon)\" hae=\"\(hae)\" ce=\"\(ce)\" le=\"\(le)\"/>\n"
        xml += "  <detail>\n"
        xml += "    <contact callsign=\"WarDragon-\(serialNumber.isEmpty ? "Unknown" : serialNumber)\"/>\n"
        xml += "    <__group name=\"Cyan\" role=\"Team Member\"/>\n"
        xml += "    <precisionlocation altsrc=\"GPS\" geopointsrc=\"GPS\"/>\n"
        xml += "    <status readiness=\"true\"/>\n"
        xml += "    <takv device=\"WarDragon iOS\" platform=\"Apple\" os=\"iOS\" version=\"\(appVersion)\"/>\n"
        
        // System health details (custom detail matching Python)
        xml += "    <system_health>\n"
        xml += "      <cpu_usage>\(cpuUsage)</cpu_usage>\n"
        xml += "      <memory_percent>\(memoryPercent)</memory_percent>\n"
        xml += "      <memory_total_mb>\(memoryTotal)</memory_total_mb>\n"
        xml += "      <memory_available_mb>\(memoryAvailable)</memory_available_mb>\n"
        xml += "      <disk_total_mb>\(diskTotal)</disk_total_mb>\n"
        xml += "      <disk_used_mb>\(diskUsed)</disk_used_mb>\n"
        xml += "      <temperature_c>\(temp)</temperature_c>\n"
        xml += "      <uptime_seconds>\(uptime)</uptime_seconds>\n"
        xml += "      <pluto_temp_c>\(plutoTemp)</pluto_temp_c>\n"
        xml += "      <zynq_temp_c>\(zynqTemp)</zynq_temp_c>\n"
        xml += "    </system_health>\n"
        
        xml += "    <remarks>WarDragon System Status</remarks>\n"
        xml += "  </detail>\n"
        xml += "</event>\n"
        
        return xml
    }
    
    /// Convert system status to JSON dictionary (for MQTT/API)
    func toSystemStatusDictionary() -> [String: Any] {
        let kitID: String
        if !serialNumber.isEmpty && serialNumber != "unknown" {
            kitID = "wardragon-\(serialNumber)"
        } else if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            let prefix = String(uuid.prefix(8))
            kitID = "wardragon-\(prefix)"
        } else {
            kitID = "wardragon-unknown"
        }
        
        return [
            "kit_id": kitID,
            "serial_number": serialNumber,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "gps_data": [
                "latitude": gpsData.latitude,
                "longitude": gpsData.longitude,
                "altitude": gpsData.altitude,
                "speed": gpsData.speed,
                "track": gpsData.track
            ],
            "system_stats": [
                "cpu_usage": systemStats.cpuUsage,
                "memory": [
                    "total": systemStats.memory.total,
                    "available": systemStats.memory.available,
                    "percent": systemStats.memory.percent,
                    "used": systemStats.memory.used,
                    "free": systemStats.memory.free,
                    "active": systemStats.memory.active,
                    "inactive": systemStats.memory.inactive,
                    "buffers": systemStats.memory.buffers,
                    "cached": systemStats.memory.cached,
                    "shared": systemStats.memory.shared,
                    "slab": systemStats.memory.slab
                ],
                "disk": [
                    "total": systemStats.disk.total,
                    "used": systemStats.disk.used,
                    "free": systemStats.disk.free,
                    "percent": systemStats.disk.percent
                ],
                "temperature": systemStats.temperature,
                "uptime": systemStats.uptime
            ],
            "ant_sdr_temps": [
                "pluto_temp": antStats.plutoTemp,
                "zynq_temp": antStats.zynqTemp
            ]
        ]
    }
    
    /// Get app version string
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
