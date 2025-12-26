//
//  RateLimiter.swift
//  WarDragon
//
//  Rate limiting system for throttling message publishing
//

import Foundation

/// Rate limiting strategy
enum RateLimitStrategy {
    case perSecond(Int)           // Max N messages per second
    case perMinute(Int)           // Max N messages per minute
    case interval(TimeInterval)   // Minimum interval between messages
    case burst(count: Int, period: TimeInterval)  // Max N messages in period
    
    var description: String {
        switch self {
        case .perSecond(let count):
            return "\(count)/sec"
        case .perMinute(let count):
            return "\(count)/min"
        case .interval(let interval):
            return "Every \(interval)s"
        case .burst(let count, let period):
            return "\(count) per \(period)s"
        }
    }
}

/// Rate limiter for throttling events
class RateLimiter {
    private var lastEventTime: Date?
    private var eventTimestamps: [Date] = []
    private let strategy: RateLimitStrategy
    private let queue = DispatchQueue(label: "com.wardragon.ratelimiter", attributes: .concurrent)
    
    init(strategy: RateLimitStrategy) {
        self.strategy = strategy
    }
    
    /// Check if an event should be allowed
    /// - Returns: true if event is allowed, false if rate limited
    func shouldAllow() -> Bool {
        queue.sync {
            let now = Date()
            
            switch strategy {
            case .perSecond(let maxCount):
                return shouldAllowPerSecond(now: now, maxCount: maxCount)
                
            case .perMinute(let maxCount):
                return shouldAllowPerMinute(now: now, maxCount: maxCount)
                
            case .interval(let minInterval):
                return shouldAllowWithInterval(now: now, minInterval: minInterval)
                
            case .burst(let count, let period):
                return shouldAllowBurst(now: now, count: count, period: period)
            }
        }
    }
    
    /// Record that an event occurred (call after shouldAllow returns true)
    func recordEvent() {
        queue.async(flags: .barrier) {
            let now = Date()
            self.lastEventTime = now
            self.eventTimestamps.append(now)
            
            // Clean up old timestamps (keep last 1000)
            if self.eventTimestamps.count > 1000 {
                self.eventTimestamps.removeFirst(self.eventTimestamps.count - 1000)
            }
        }
    }
    
    /// Check and record in one call
    func tryAllow() -> Bool {
        if shouldAllow() {
            recordEvent()
            return true
        }
        return false
    }
    
    /// Reset the rate limiter
    func reset() {
        queue.async(flags: .barrier) {
            self.lastEventTime = nil
            self.eventTimestamps.removeAll()
        }
    }
    
    /// Get current rate (events per second)
    func currentRate() -> Double {
        queue.sync {
            let now = Date()
            let recentEvents = eventTimestamps.filter { now.timeIntervalSince($0) <= 1.0 }
            return Double(recentEvents.count)
        }
    }
    
    // MARK: - Private Strategy Implementations
    
    private func shouldAllowPerSecond(now: Date, maxCount: Int) -> Bool {
        // Remove timestamps older than 1 second
        eventTimestamps.removeAll { now.timeIntervalSince($0) > 1.0 }
        return eventTimestamps.count < maxCount
    }
    
    private func shouldAllowPerMinute(now: Date, maxCount: Int) -> Bool {
        // Remove timestamps older than 60 seconds
        eventTimestamps.removeAll { now.timeIntervalSince($0) > 60.0 }
        return eventTimestamps.count < maxCount
    }
    
    private func shouldAllowWithInterval(now: Date, minInterval: TimeInterval) -> Bool {
        guard let lastTime = lastEventTime else { return true }
        return now.timeIntervalSince(lastTime) >= minInterval
    }
    
    private func shouldAllowBurst(now: Date, count: Int, period: TimeInterval) -> Bool {
        // Remove timestamps outside the burst period
        eventTimestamps.removeAll { now.timeIntervalSince($0) > period }
        return eventTimestamps.count < count
    }
}

// MARK: - Per-Item Rate Limiter

/// Rate limiter that tracks separate limits per item (e.g., per drone MAC address)
class PerItemRateLimiter<Key: Hashable> {
    private var limiters: [Key: RateLimiter] = [:]
    private let strategy: RateLimitStrategy
    private let queue = DispatchQueue(label: "com.wardragon.peritemratelimiter", attributes: .concurrent)
    
    init(strategy: RateLimitStrategy) {
        self.strategy = strategy
    }
    
    /// Check if an event for a specific item should be allowed
    func shouldAllow(for key: Key) -> Bool {
        queue.sync {
            getLimiter(for: key).shouldAllow()
        }
    }
    
    /// Record an event for a specific item
    func recordEvent(for key: Key) {
        queue.async(flags: .barrier) {
            self.getLimiter(for: key).recordEvent()
        }
    }
    
    /// Check and record in one call
    func tryAllow(for key: Key) -> Bool {
        var allowed = false
        queue.sync {
            allowed = getLimiter(for: key).shouldAllow()
        }
        
        if allowed {
            queue.async(flags: .barrier) {
                self.getLimiter(for: key).recordEvent()
            }
        }
        
        return allowed
    }
    
    /// Reset rate limiter for specific item
    func reset(for key: Key) {
        queue.async(flags: .barrier) {
            self.limiters[key]?.reset()
        }
    }
    
    /// Reset all rate limiters
    func resetAll() {
        queue.async(flags: .barrier) {
            self.limiters.removeAll()
        }
    }
    
    /// Get current rate for a specific item
    func currentRate(for key: Key) -> Double {
        queue.sync {
            getLimiter(for: key).currentRate()
        }
    }
    
    /// Get all tracked items
    func trackedItems() -> [Key] {
        queue.sync {
            Array(limiters.keys)
        }
    }
    
    /// Remove old limiters that haven't been used recently
    func cleanupStale(olderThan interval: TimeInterval) {
        queue.async(flags: .barrier) {
            let now = Date()
            self.limiters = self.limiters.filter { key, limiter in
                // Keep if used recently
                if let lastTime = limiter.lastEventTime {
                    return now.timeIntervalSince(lastTime) < interval
                }
                return false
            }
        }
    }
    
    // MARK: - Private
    
    private func getLimiter(for key: Key) -> RateLimiter {
        if let limiter = limiters[key] {
            return limiter
        }
        
        let newLimiter = RateLimiter(strategy: strategy)
        limiters[key] = newLimiter
        return newLimiter
    }
}

// MARK: - Rate Limiter Configuration

/// Configuration for rate limiting across the app
struct RateLimitConfiguration: Codable, Equatable {
    var enabled: Bool
    
    // Per-drone rate limiting
    var dronePublishInterval: TimeInterval  // Minimum seconds between publishes for same drone
    var droneMaxPerMinute: Int              // Maximum publishes per drone per minute
    
    // MQTT rate limiting
    var mqttMaxPerSecond: Int               // Maximum MQTT messages per second (total)
    var mqttBurstCount: Int                 // Maximum burst size
    var mqttBurstPeriod: TimeInterval       // Burst period in seconds
    
    // TAK rate limiting
    var takMaxPerSecond: Int                // Maximum TAK messages per second (total)
    var takPublishInterval: TimeInterval    // Minimum interval between TAK publishes
    
    // Webhook rate limiting
    var webhookMaxPerMinute: Int            // Maximum webhook calls per minute
    var webhookPublishInterval: TimeInterval // Minimum interval between webhooks
    
    init(
        enabled: Bool = true,
        dronePublishInterval: TimeInterval = 1.0,
        droneMaxPerMinute: Int = 30,
        mqttMaxPerSecond: Int = 10,
        mqttBurstCount: Int = 20,
        mqttBurstPeriod: TimeInterval = 5.0,
        takMaxPerSecond: Int = 5,
        takPublishInterval: TimeInterval = 0.5,
        webhookMaxPerMinute: Int = 20,
        webhookPublishInterval: TimeInterval = 2.0
    ) {
        self.enabled = enabled
        self.dronePublishInterval = dronePublishInterval
        self.droneMaxPerMinute = droneMaxPerMinute
        self.mqttMaxPerSecond = mqttMaxPerSecond
        self.mqttBurstCount = mqttBurstCount
        self.mqttBurstPeriod = mqttBurstPeriod
        self.takMaxPerSecond = takMaxPerSecond
        self.takPublishInterval = takPublishInterval
        self.webhookMaxPerMinute = webhookMaxPerMinute
        self.webhookPublishInterval = webhookPublishInterval
    }
    
    /// Conservative preset (low bandwidth)
    static var conservative: RateLimitConfiguration {
        RateLimitConfiguration(
            dronePublishInterval: 2.0,
            droneMaxPerMinute: 20,
            mqttMaxPerSecond: 5,
            mqttBurstCount: 10,
            takMaxPerSecond: 3,
            webhookMaxPerMinute: 10
        )
    }
    
    /// Balanced preset (recommended)
    static var balanced: RateLimitConfiguration {
        RateLimitConfiguration()
    }
    
    /// Aggressive preset (high frequency)
    static var aggressive: RateLimitConfiguration {
        RateLimitConfiguration(
            dronePublishInterval: 0.5,
            droneMaxPerMinute: 60,
            mqttMaxPerSecond: 20,
            mqttBurstCount: 40,
            takMaxPerSecond: 10,
            webhookMaxPerMinute: 40
        )
    }
}

// MARK: - Rate Limiter Manager

/// Centralized rate limiter manager
class RateLimiterManager {
    static let shared = RateLimiterManager()
    
    private(set) var config: RateLimitConfiguration
    
    // Per-drone rate limiters
    let dronePublishLimiter: PerItemRateLimiter<String>  // Key: MAC or UID
    
    // Global rate limiters
    let mqttLimiter: RateLimiter
    let takLimiter: RateLimiter
    let webhookLimiter: RateLimiter
    
    private init() {
        self.config = Settings.shared.rateLimitConfiguration
        
        // Initialize per-drone limiter
        self.dronePublishLimiter = PerItemRateLimiter(
            strategy: .interval(config.dronePublishInterval)
        )
        
        // Initialize global limiters
        self.mqttLimiter = RateLimiter(
            strategy: .burst(count: config.mqttBurstCount, period: config.mqttBurstPeriod)
        )
        
        self.takLimiter = RateLimiter(
            strategy: .interval(config.takPublishInterval)
        )
        
        self.webhookLimiter = RateLimiter(
            strategy: .perMinute(config.webhookMaxPerMinute)
        )
        
        // Clean up stale limiters every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.dronePublishLimiter.cleanupStale(olderThan: 600) // 10 minutes
        }
    }
    
    /// Update configuration and recreate limiters
    func updateConfiguration(_ config: RateLimitConfiguration) {
        self.config = config
        Settings.shared.updateRateLimitConfiguration(config)
        
        // Note: Existing limiters keep running with old config
        // A full restart would be needed to apply new limits to existing limiters
        // For now, just store the new config for next launch
    }
    
    /// Check if drone publish should be allowed
    func shouldAllowDronePublish(for droneId: String) -> Bool {
        guard config.enabled else { return true }
        return dronePublishLimiter.tryAllow(for: droneId)
    }
    
    /// Check if MQTT publish should be allowed
    func shouldAllowMQTTPublish() -> Bool {
        guard config.enabled else { return true }
        return mqttLimiter.tryAllow()
    }
    
    /// Check if TAK publish should be allowed
    func shouldAllowTAKPublish() -> Bool {
        guard config.enabled else { return true }
        return takLimiter.tryAllow()
    }
    
    /// Check if webhook should be allowed
    func shouldAllowWebhook() -> Bool {
        guard config.enabled else { return true }
        return webhookLimiter.tryAllow()
    }
    
    /// Get statistics
    func getStatistics() -> RateLimitStatistics {
        RateLimitStatistics(
            mqttRate: mqttLimiter.currentRate(),
            takRate: takLimiter.currentRate(),
            webhookRate: webhookLimiter.currentRate(),
            trackedDrones: dronePublishLimiter.trackedItems().count
        )
    }
}

// MARK: - Statistics

struct RateLimitStatistics {
    let mqttRate: Double      // Messages per second
    let takRate: Double       // Messages per second
    let webhookRate: Double   // Messages per second
    let trackedDrones: Int    // Number of drones being tracked
}
