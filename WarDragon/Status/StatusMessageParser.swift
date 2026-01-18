//
//  StatusMessageParser.swift
//  WarDragon
//
//  Created to fix status JSON parsing issues
//

import Foundation
import OSLog

struct StatusMessageParser {
    private static let logger = Logger(subsystem: "com.wardragon", category: "StatusParser")
    
    /// Parse status JSON string into StatusMessage
    static func parse(_ jsonString: String) -> StatusViewModel.StatusMessage? {
        logger.debug("🔍 Attempting to parse status JSON of length: \(jsonString.count)")
        
        guard let data = jsonString.data(using: .utf8) else {
            logger.error("❌ Failed to convert JSON string to Data")
            return nil
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("❌ JSON is not a dictionary")
                logger.debug("Raw JSON: \(jsonString.prefix(500))")
                return nil
            }
            
            logger.debug("✅ JSON parsed successfully, keys: \(json.keys.joined(separator: ", "))")
            
            // Try to extract required fields with detailed logging
            guard let uid = json["uid"] as? String ?? json["id"] as? String ?? json["device_id"] as? String else {
                logger.error("❌ Missing 'uid' field in JSON")
                logger.debug("Available keys: \(json.keys.joined(separator: ", "))")
                return nil
            }
            
            let serialNumber = json["serial_number"] as? String 
                ?? json["serialNumber"] as? String 
                ?? json["device_id"] as? String 
                ?? "Unknown"
            
            let timestamp = json["timestamp"] as? Double ?? Date().timeIntervalSince1970
            
            // Parse GPS data
            let gpsData = parseGPSData(from: json)
            logger.debug("📍 GPS parsed: lat=\(gpsData.latitude), lon=\(gpsData.longitude)")
            
            // Parse system stats
            let systemStats = parseSystemStats(from: json)
            logger.debug("💻 System stats parsed: CPU=\(systemStats.cpuUsage)%, Temp=\(systemStats.temperature)°C")
            
            // Parse ANT stats
            let antStats = parseANTStats(from: json)
            logger.debug("📡 ANT stats parsed: Pluto=\(antStats.plutoTemp)°C, Zynq=\(antStats.zynqTemp)°C")
            
            let message = StatusViewModel.StatusMessage(
                uid: uid,
                serialNumber: serialNumber,
                timestamp: timestamp,
                gpsData: gpsData,
                systemStats: systemStats,
                antStats: antStats
            )
            
            logger.info("✅ Successfully parsed status message for \(serialNumber)")
            return message
            
        } catch {
            logger.error("❌ JSON parsing error: \(error.localizedDescription)")
            logger.debug("Raw JSON: \(jsonString.prefix(1000))")
            return nil
        }
    }
    
    private static func parseGPSData(from json: [String: Any]) -> StatusViewModel.StatusMessage.GPSData {
        var latitude: Double = 0
        var longitude: Double = 0
        var altitude: Double = 0
        var speed: Double = 0
        
        // Try multiple possible JSON structures
        if let gps = json["gps"] as? [String: Any] ?? json["gps_data"] as? [String: Any] ?? json["location"] as? [String: Any] {
            latitude = gps["latitude"] as? Double ?? gps["lat"] as? Double ?? 0
            longitude = gps["longitude"] as? Double ?? gps["lon"] as? Double ?? gps["lng"] as? Double ?? 0
            altitude = gps["altitude"] as? Double ?? gps["alt"] as? Double ?? 0
            speed = gps["speed"] as? Double ?? 0
        } else {
            // Try flat structure
            latitude = json["latitude"] as? Double ?? json["lat"] as? Double ?? 0
            longitude = json["longitude"] as? Double ?? json["lon"] as? Double ?? json["lng"] as? Double ?? 0
            altitude = json["altitude"] as? Double ?? json["alt"] as? Double ?? 0
            speed = json["speed"] as? Double ?? 0
        }
        
        return StatusViewModel.StatusMessage.GPSData(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            speed: speed
        )
    }
    
    private static func parseSystemStats(from json: [String: Any]) -> StatusViewModel.StatusMessage.SystemStats {
        var cpuUsage: Double = 0
        var memory = StatusViewModel.StatusMessage.SystemStats.MemoryStats(
            total: 0, available: 0, percent: 0, used: 0, free: 0,
            active: 0, inactive: 0, buffers: 0, cached: 0, shared: 0, slab: 0
        )
        var disk = StatusViewModel.StatusMessage.SystemStats.DiskStats(
            total: 0, used: 0, free: 0, percent: 0
        )
        var temperature: Double = 0
        var uptime: Double = 0
        
        if let stats = json["system_stats"] as? [String: Any] ?? json["stats"] as? [String: Any] ?? json["system"] as? [String: Any] {
            cpuUsage = stats["cpu_usage"] as? Double ?? stats["cpu_percent"] as? Double ?? stats["cpu"] as? Double ?? 0
            temperature = stats["temperature"] as? Double ?? stats["temp"] as? Double ?? 0
            uptime = stats["uptime"] as? Double ?? stats["uptime_seconds"] as? Double ?? 0
            
            // Parse memory
            if let mem = stats["memory"] as? [String: Any] {
                memory = StatusViewModel.StatusMessage.SystemStats.MemoryStats(
                    total: mem["total"] as? Int64 ?? 0,
                    available: mem["available"] as? Int64 ?? 0,
                    percent: mem["percent"] as? Double ?? 0,
                    used: mem["used"] as? Int64 ?? 0,
                    free: mem["free"] as? Int64 ?? 0,
                    active: mem["active"] as? Int64 ?? 0,
                    inactive: mem["inactive"] as? Int64 ?? 0,
                    buffers: mem["buffers"] as? Int64 ?? 0,
                    cached: mem["cached"] as? Int64 ?? 0,
                    shared: mem["shared"] as? Int64 ?? 0,
                    slab: mem["slab"] as? Int64 ?? 0
                )
            }
            
            // Parse disk
            if let diskInfo = stats["disk"] as? [String: Any] {
                disk = StatusViewModel.StatusMessage.SystemStats.DiskStats(
                    total: diskInfo["total"] as? Int64 ?? 0,
                    used: diskInfo["used"] as? Int64 ?? 0,
                    free: diskInfo["free"] as? Int64 ?? 0,
                    percent: diskInfo["percent"] as? Double ?? 0
                )
            }
        }
        
        return StatusViewModel.StatusMessage.SystemStats(
            cpuUsage: cpuUsage,
            memory: memory,
            disk: disk,
            temperature: temperature,
            uptime: uptime
        )
    }
    
    private static func parseANTStats(from json: [String: Any]) -> StatusViewModel.StatusMessage.ANTStats {
        var plutoTemp: Double = 0
        var zynqTemp: Double = 0
        
        // Try multiple possible structures
        if let ant = json["ant_stats"] as? [String: Any] ?? json["antsdr"] as? [String: Any] ?? json["sdr"] as? [String: Any] {
            plutoTemp = ant["pluto_temp"] as? Double ?? ant["plutoTemp"] as? Double ?? ant["pluto_temperature"] as? Double ?? 0
            zynqTemp = ant["zynq_temp"] as? Double ?? ant["zynqTemp"] as? Double ?? ant["zynq_temperature"] as? Double ?? 0
        } else {
            // Try flat structure
            plutoTemp = json["pluto_temp"] as? Double ?? json["plutoTemp"] as? Double ?? 0
            zynqTemp = json["zynq_temp"] as? Double ?? json["zynqTemp"] as? Double ?? 0
        }
        
        logger.debug("🔧 Parsed ANT temps - Pluto: \(plutoTemp), Zynq: \(zynqTemp)")
        
        return StatusViewModel.StatusMessage.ANTStats(
            plutoTemp: plutoTemp,
            zynqTemp: zynqTemp
        )
    }
}
