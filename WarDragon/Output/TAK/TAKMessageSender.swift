//
//  TAKMessageSender.swift
//  WarDragon
//
//  Service to send drone and aircraft CoT messages to TAK server
//  Matches Python DragonSync messaging.py/manager.py functionality
//

import Foundation
import os.log

/// Centralized service for sending CoT messages to TAK
/// Manages rate limiting and queuing similar to Python DragonSync
@MainActor
class TAKMessageSender {
    static let shared = TAKMessageSender()
    
    private let logger = Logger(subsystem: "com.wardragon", category: "TAKMessageSender")
    
    // Rate limiting per drone/aircraft
    private var lastSendTimes: [String: Date] = [:]
    private let droneRateLimit: TimeInterval = 1.0  // Match Python default
    private let aircraftRateLimit: TimeInterval = 3.0  // Match Python adsb_rate_limit
    
    private init() {}
    
    /// Send a drone CoT message to TAK (with rate limiting)
    /// Returns true if sent, false if rate limited
    @discardableResult
    func sendDrone(_ message: CoTViewModel.CoTMessage) async -> Bool {
        guard Settings.shared.takEnabled, let takClient = Settings.shared.takClient else {
            return false
        }
        
        // Check rate limiting
        let uid = message.uid
        if let lastSend = lastSendTimes[uid] {
            let elapsed = Date().timeIntervalSince(lastSend)
            if elapsed < droneRateLimit {
                logger.debug("Rate limited drone \(uid, privacy: .public), \(elapsed, privacy: .public)s since last send")
                return false
            }
        }
        
        // Generate CoT XML
        let cotXML = message.toCoTXML()
        
        // Send to TAK
        do {
            try await takClient.send(cotXML)
            lastSendTimes[uid] = Date()
            logger.debug("Sent drone CoT to TAK: \(uid, privacy: .public)")
            return true
        } catch {
            logger.error("Failed to send drone CoT to TAK: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    /// Send an aircraft CoT message to TAK (with rate limiting)
    /// Returns true if sent, false if rate limited
    @discardableResult
    func sendAircraft(_ aircraft: Aircraft, seenBy: String? = nil) async -> Bool {
        guard Settings.shared.takEnabled, let takClient = Settings.shared.takClient else {
            return false
        }
        
        // Check rate limiting
        let uid = "adsb-\(aircraft.hex)"
        if let lastSend = lastSendTimes[uid] {
            let elapsed = Date().timeIntervalSince(lastSend)
            if elapsed < aircraftRateLimit {
                logger.debug("Rate limited aircraft \(uid, privacy: .public), \(elapsed, privacy: .public)s since last send")
                return false
            }
        }
        
        // Generate CoT XML
        let cotXML = aircraft.toCoTXML(seenBy: seenBy)
        
        // Send to TAK
        do {
            try await takClient.send(cotXML)
            lastSendTimes[uid] = Date()
            logger.debug("Sent aircraft CoT to TAK: \(uid, privacy: .public)")
            return true
        } catch {
            logger.error("Failed to send aircraft CoT to TAK: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    /// Send a system status CoT message to TAK (no rate limiting)
    func sendSystemStatus(_ status: StatusViewModel.StatusMessage, enrollmentManager: TAKEnrollmentManager? = nil) async {
        guard Settings.shared.takEnabled, let takClient = Settings.shared.takClient else {
            return
        }
        
        // Generate CoT XML
        let cotXML = status.toCoTXML(enrollmentManager: enrollmentManager)
        
        // Send to TAK
        do {
            try await takClient.send(cotXML)
            logger.debug("Sent system status CoT to TAK")
        } catch {
            logger.error("Failed to send system status CoT to TAK: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Clean up old rate limit entries (called periodically)
    func cleanupOldEntries() {
        let now = Date()
        let maxAge: TimeInterval = 300.0  // 5 minutes
        
        lastSendTimes = lastSendTimes.filter { uid, lastSend in
            now.timeIntervalSince(lastSend) < maxAge
        }
        
        if !lastSendTimes.isEmpty {
            logger.debug("Cleaned up rate limit tracking, \(self.lastSendTimes.count) entries remain")
        }
    }
}
