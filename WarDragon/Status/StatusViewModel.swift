//
//  StatusViewModel.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import Foundation
import CoreLocation
import SwiftUI
import SwiftData

extension Notification.Name {
    static let statusThresholdExceeded = Notification.Name("statusThresholdExceeded")
}

@MainActor
class StatusViewModel: ObservableObject {
    @Published var statusMessages: [StatusMessage] = []
    @Published var lastStatusMessageReceived: Date?
    @Published var showESP32LocationAlert = false
    @Published var adsbEncounterHistory: [ADSBEncounter] = []
    private var locationManager = LocationManager.shared
    
    // Reference to model context for SwiftData
    var modelContext: ModelContext?
    
    // MARK: - ADS-B Encounter Tracking
    
    /// Simple ADS-B encounter record for history
    struct ADSBEncounter: Identifiable, Codable {
        let id: String  // ICAO hex
        let callsign: String
        let firstSeen: Date
        var lastSeen: Date
        var maxAltitude: Double
        var minAltitude: Double
        var totalSightings: Int
        
        var displayName: String {
            callsign.isEmpty ? id.uppercased() : callsign
        }
        
        var duration: TimeInterval {
            lastSeen.timeIntervalSince(firstSeen)
        }
        
        var formattedDuration: String {
            let interval = duration
            if interval < 60 {
                return "\(Int(interval))s"
            } else if interval < 3600 {
                return "\(Int(interval / 60))m"
            } else {
                return "\(Int(interval / 3600))h \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60))m"
            }
        }
    }
    
    /// Track an aircraft encounter
    func trackAircraft(hex: String, callsign: String?, altitude: Double?) {
        let now = Date()
        let cleanCallsign = callsign?.trimmingCharacters(in: .whitespaces) ?? ""
        
        if let index = adsbEncounterHistory.firstIndex(where: { $0.id == hex }) {
            // Update existing encounter
            var encounter = adsbEncounterHistory[index]
            encounter.lastSeen = now
            encounter.totalSightings += 1
            
            if let altitude = altitude {
                encounter.maxAltitude = max(encounter.maxAltitude, altitude)
                encounter.minAltitude = min(encounter.minAltitude, altitude)
            }
            
            adsbEncounterHistory[index] = encounter
            
            // Update in SwiftData
            if let context = modelContext {
                let predicate = #Predicate<StoredADSBEncounter> { stored in
                    stored.id == hex
                }
                let descriptor = FetchDescriptor(predicate: predicate)
                if let stored = try? context.fetch(descriptor).first {
                    stored.lastSeen = now
                    stored.totalSightings += 1
                    if let altitude = altitude {
                        stored.maxAltitude = max(stored.maxAltitude, altitude)
                        stored.minAltitude = min(stored.minAltitude, altitude)
                    }
                    try? context.save()
                }
            }
        } else {
            // Create new encounter
            let encounter = ADSBEncounter(
                id: hex,
                callsign: cleanCallsign,
                firstSeen: now,
                lastSeen: now,
                maxAltitude: altitude ?? 0,
                minAltitude: altitude ?? 0,
                totalSightings: 1
            )
            adsbEncounterHistory.append(encounter)
            
            // Save to SwiftData
            if let context = modelContext {
                let stored = StoredADSBEncounter(
                    id: hex,
                    callsign: cleanCallsign,
                    firstSeen: now,
                    lastSeen: now,
                    maxAltitude: altitude ?? 0,
                    minAltitude: altitude ?? 0,
                    totalSightings: 1
                )
                context.insert(stored)
                try? context.save()
            }
        }
        
        // Keep only last 500 encounters to prevent memory issues
        if adsbEncounterHistory.count > 500 {
            adsbEncounterHistory.removeFirst(adsbEncounterHistory.count - 500)
        }
    }
    
    /// Clear ADS-B encounter history
    func clearADSBHistory() {
        adsbEncounterHistory.removeAll()
        
        // Clear from SwiftData too
        if let context = modelContext {
            do {
                // Fetch all encounters fresh from context
                let descriptor = FetchDescriptor<StoredADSBEncounter>()
                let allEncounters = try context.fetch(descriptor)
                
                print("🗑️ Clearing \(allEncounters.count) ADSB encounters from SwiftData...")
                
                // Delete all
                for encounter in allEncounters {
                    context.delete(encounter)
                }
                
                // Save the deletions
                try context.save()
                
                print("Successfully cleared ADSB history")
            } catch {
                print("❌ Failed to clear ADSB history: \(error)")
            }
        }
    }
    
    /// Load ADS-B encounters from SwiftData
    func loadADSBEncounters() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<StoredADSBEncounter>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        
        if let stored = try? context.fetch(descriptor) {
            adsbEncounterHistory = stored.map { $0.toLegacy() }
        }
    }
    
    // MARK: - Status Connection Logic
    
    var isSystemOnline: Bool {
        guard let lastReceived = lastStatusMessageReceived else { return false }
        return Date().timeIntervalSince(lastReceived) < 300 // Consider offline if no message in 5min
    }
    
    var statusColor: Color {
        isSystemOnline ? .green : .red
    }
    
    var statusText: String {
        isSystemOnline ? "ONLINE" : "OFFLINE"
    }
    
    var lastReceivedText: String {
        guard let lastReceived = lastStatusMessageReceived else { return "Never" }
        
        let timeInterval = Date().timeIntervalSince(lastReceived)
        
        if timeInterval < 60 {
            return "\(Int(timeInterval))s ago"
        } else if timeInterval < 3600 {
            return "\(Int(timeInterval / 60))m ago"
        } else if timeInterval < 86400 {
            return "\(Int(timeInterval / 3600))h ago"
        } else {
            return "\(Int(timeInterval / 86400))d ago"
        }
    }
    
    struct StatusMessage: Identifiable  {
        var id: String { uid }
        let uid: String
        var serialNumber: String
        var timestamp: Double
        var gpsData: GPSData
        var systemStats: SystemStats
        var antStats: ANTStats
        
        
        struct GPSData {
            var latitude: Double
            var longitude: Double
            var altitude: Double
            var speed: Double
            
            var coordinate: CLLocationCoordinate2D {
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        
        struct SystemStats {
            var cpuUsage: Double
            var memory: MemoryStats
            var disk: DiskStats
            var temperature: Double
            var uptime: Double
            
            struct MemoryStats {
                var total: Int64
                var available: Int64
                var percent: Double
                var used: Int64
                var free: Int64
                var active: Int64
                var inactive: Int64
                var buffers: Int64
                var cached: Int64
                var shared: Int64
                var slab: Int64
            }
            
            struct DiskStats {
                var total: Int64
                var used: Int64
                var free: Int64
                var percent: Double
            }
        }
        
        struct ANTStats {
            var plutoTemp: Double
            var zynqTemp: Double
        }
    }
    
    // MARK: - Message Management
    
    func addStatusMessage(_ message: StatusMessage) {
        let processedMessage = processStatusMessage(message)
        statusMessages.append(processedMessage)
        lastStatusMessageReceived = Date()
        
        // Debug log to verify antStats values
        print("DEBUG StatusViewModel: Received status message with antStats - Pluto: \(processedMessage.antStats.plutoTemp)°C, Zynq: \(processedMessage.antStats.zynqTemp)°C")
        
        // Keep only the last 100 messages to prevent memory issues
        if statusMessages.count > 100 {
            statusMessages.removeFirst(statusMessages.count - 100)
        }
        
        // Check thresholds after adding new message
        checkSystemThresholds()
    }
    
    func updateExistingStatusMessage(_ message: StatusMessage) {
        let processedMessage = processStatusMessage(message)
        
        if let index = statusMessages.firstIndex(where: { $0.uid == message.uid }) {
            statusMessages[index] = processedMessage
        } else {
            addStatusMessage(processedMessage)
        }
        lastStatusMessageReceived = Date()
    }
    
    private func processStatusMessage(_ message: StatusMessage) -> StatusMessage {
        var processedMessage = message
        
        if needsLocationSubstitution(message) {
            if !Settings.shared.hasShownStatusLocationPrompt {
                DispatchQueue.main.async { self.showESP32LocationAlert = true }
            }
            
            if Settings.shared.useUserLocationForStatus, let userLocation = locationManager.userLocation {
                processedMessage.gpsData.latitude = userLocation.coordinate.latitude
                processedMessage.gpsData.longitude = userLocation.coordinate.longitude
                processedMessage.gpsData.altitude = userLocation.altitude
                processedMessage.gpsData.speed = max(0, userLocation.speed)
            }
        }
        return processedMessage
    }

    private func needsLocationSubstitution(_ message: StatusMessage) -> Bool {
        let isESP32 = message.serialNumber.contains("ESP32")
        let hasNoGPS = message.gpsData.latitude == 0.0 && message.gpsData.longitude == 0.0
        return isESP32 || hasNoGPS
    }
    
    func checkSystemThresholds() {
        // Check system thresholds and send notifications if needed
        guard let latestMessage = statusMessages.last else { return }
        guard Settings.shared.notificationsEnabled else { return }
        
        let cpuThreshold = Settings.shared.cpuWarningThreshold
        let memoryThreshold = Settings.shared.memoryWarningThreshold
        let tempThreshold = Settings.shared.tempWarningThreshold
        
        // Check CPU
        if latestMessage.systemStats.cpuUsage > cpuThreshold {
            sendNotification(
                title: "High CPU Usage",
                body: "CPU usage is at \(Int(latestMessage.systemStats.cpuUsage))%"
            )
        }
        
        // Check Memory (memoryWarningThreshold is 0-1.0, memory.percent is 0-100)
        if latestMessage.systemStats.memory.percent > (memoryThreshold * 100) {
            sendNotification(
                title: "High Memory Usage",
                body: "Memory usage is at \(Int(latestMessage.systemStats.memory.percent))%"
            )
        }
        
        // Check Temperature
        if latestMessage.systemStats.temperature > tempThreshold {
            sendNotification(
                title: "High Temperature",
                body: "System temperature is at \(Int(latestMessage.systemStats.temperature))°C"
            )
        }
    }
    
    private func sendNotification(title: String, body: String) {
        // Rate limit notifications - only send once every 5 minutes per type
        let key = title
        let now = Date()
        
        if let lastSent = lastNotificationSent[key],
           now.timeIntervalSince(lastSent) < 300 {
            return
        }
        
        lastNotificationSent[key] = now
        
        NotificationCenter.default.post(
            name: .statusThresholdExceeded,
            object: nil,
            userInfo: ["title": title, "body": body]
        )
    }
    
    private var lastNotificationSent: [String: Date] = [:]
}


