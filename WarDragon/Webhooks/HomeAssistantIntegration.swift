//
//  HomeAssistantIntegration.swift
//  WarDragon
//
//  Home Assistant MQTT Discovery integration
//

import Foundation

/// Home Assistant MQTT Discovery helper
struct HomeAssistantIntegration {
    
    /// Device class for Home Assistant entities
    enum DeviceClass: String {
        case deviceTracker = "device_tracker"
        case sensor = "sensor"
        case binarySensor = "binary_sensor"
    }
    
    /// Generate Home Assistant discovery configuration for a drone
    static func droneDiscoveryConfig(
        macAddress: String,
        deviceName: String,
        manufacturer: String?,
        stateTopic: String,
        availabilityTopic: String,
        discoveryPrefix: String = "homeassistant"
    ) -> [String: Any] {
        
        let uniqueId = "wardragon_drone_\(macAddress.replacingOccurrences(of: ":", with: "_"))"
        
        return [
            "name": deviceName,
            "unique_id": uniqueId,
            "state_topic": stateTopic,
            "json_attributes_topic": stateTopic,
            "value_template": "{{ value_json.timestamp }}",
            "device": [
                "identifiers": [uniqueId],
                "name": deviceName,
                "model": "Remote ID Drone",
                "manufacturer": manufacturer ?? "Unknown",
                "sw_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                "via_device": "wardragon_\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")"
            ],
            "icon": "mdi:quadcopter",
            "availability": [
                [
                    "topic": availabilityTopic,
                    "payload_available": "online",
                    "payload_not_available": "offline"
                ]
            ]
        ]
    }
    
    /// Generate Home Assistant discovery topic
    static func discoveryTopic(
        deviceClass: DeviceClass,
        nodeId: String,
        objectId: String,
        discoveryPrefix: String = "homeassistant"
    ) -> String {
        return "\(discoveryPrefix)/\(deviceClass.rawValue)/\(nodeId)/\(objectId)/config"
    }
    
    /// Generate drone sensor discovery configs (altitude, speed, RSSI, etc.)
    static func droneSensorConfigs(
        macAddress: String,
        deviceName: String,
        stateTopic: String,
        availabilityTopic: String,
        discoveryPrefix: String = "homeassistant"
    ) -> [(topic: String, config: [String: Any])] {
        
        let nodeId = "wardragon_drone_\(macAddress.replacingOccurrences(of: ":", with: "_"))"
        let deviceInfo: [String: Any] = [
            "identifiers": [nodeId],
            "name": deviceName,
            "model": "Remote ID Drone",
            "manufacturer": "WarDragon"
        ]
        
        var sensors: [(String, [String: Any])] = []
        
        // Altitude sensor
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "altitude", discoveryPrefix: discoveryPrefix),
            [
                "name": "\(deviceName) Altitude",
                "unique_id": "\(nodeId)_altitude",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.altitude }}",
                "unit_of_measurement": "m",
                "device_class": "distance",
                "device": deviceInfo,
                "icon": "mdi:altimeter",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Speed sensor
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "speed", discoveryPrefix: discoveryPrefix),
            [
                "name": "\(deviceName) Speed",
                "unique_id": "\(nodeId)_speed",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.speed }}",
                "unit_of_measurement": "m/s",
                "device_class": "speed",
                "device": deviceInfo,
                "icon": "mdi:speedometer",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // RSSI sensor
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "rssi", discoveryPrefix: discoveryPrefix),
            [
                "name": "\(deviceName) Signal Strength",
                "unique_id": "\(nodeId)_rssi",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.rssi }}",
                "unit_of_measurement": "dBm",
                "device_class": "signal_strength",
                "device": deviceInfo,
                "icon": "mdi:signal",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Latitude sensor
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "latitude", discoveryPrefix: discoveryPrefix),
            [
                "name": "\(deviceName) Latitude",
                "unique_id": "\(nodeId)_latitude",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.latitude }}",
                "unit_of_measurement": "°",
                "device": deviceInfo,
                "icon": "mdi:latitude",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Longitude sensor
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "longitude", discoveryPrefix: discoveryPrefix),
            [
                "name": "\(deviceName) Longitude",
                "unique_id": "\(nodeId)_longitude",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.longitude }}",
                "unit_of_measurement": "°",
                "device": deviceInfo,
                "icon": "mdi:longitude",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Detection binary sensor
        sensors.append((
            discoveryTopic(deviceClass: .binarySensor, nodeId: nodeId, objectId: "detection", discoveryPrefix: discoveryPrefix),
            [
                "name": "\(deviceName) Detected",
                "unique_id": "\(nodeId)_detected",
                "state_topic": stateTopic,
                "value_template": "{{ 'ON' if value_json.timestamp else 'OFF' }}",
                "device_class": "occupancy",
                "device": deviceInfo,
                "icon": "mdi:radar",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        return sensors
    }
    
    /// Generate system status sensor configs
    static func systemSensorConfigs(
        stateTopic: String,
        availabilityTopic: String,
        discoveryPrefix: String = "homeassistant"
    ) -> [(topic: String, config: [String: Any])] {
        
        let nodeId = "wardragon_system_\(UIDevice.current.identifierForVendor?.uuidString.replacingOccurrences(of: "-", with: "_") ?? "unknown")"
        let deviceInfo: [String: Any] = [
            "identifiers": [nodeId],
            "name": "WarDragon System",
            "model": UIDevice.current.model,
            "manufacturer": "Apple",
            "sw_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]
        
        var sensors: [(String, [String: Any])] = []
        
        // CPU usage
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "cpu", discoveryPrefix: discoveryPrefix),
            [
                "name": "WarDragon CPU Usage",
                "unique_id": "\(nodeId)_cpu",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.cpuUsage }}",
                "unit_of_measurement": "%",
                "device": deviceInfo,
                "icon": "mdi:cpu-64-bit",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Memory usage
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "memory", discoveryPrefix: discoveryPrefix),
            [
                "name": "WarDragon Memory Usage",
                "unique_id": "\(nodeId)_memory",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.memoryUsed }}",
                "unit_of_measurement": "%",
                "device": deviceInfo,
                "icon": "mdi:memory",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Temperature
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "temperature", discoveryPrefix: discoveryPrefix),
            [
                "name": "WarDragon Temperature",
                "unique_id": "\(nodeId)_temperature",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.temperature }}",
                "unit_of_measurement": "°C",
                "device_class": "temperature",
                "device": deviceInfo,
                "icon": "mdi:thermometer",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        // Drones tracked
        sensors.append((
            discoveryTopic(deviceClass: .sensor, nodeId: nodeId, objectId: "drones", discoveryPrefix: discoveryPrefix),
            [
                "name": "WarDragon Drones Tracked",
                "unique_id": "\(nodeId)_drones",
                "state_topic": stateTopic,
                "value_template": "{{ value_json.dronesTracked }}",
                "device": deviceInfo,
                "icon": "mdi:counter",
                "availability": [["topic": availabilityTopic]]
            ]
        ))
        
        return sensors
    }
}
