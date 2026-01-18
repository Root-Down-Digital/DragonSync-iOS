//
//  DroneSignature.swift
//  WarDragon
//
//  Created by Luke on 12/6/24.
//

import Foundation
import CoreLocation
import SwiftUI


public struct DroneSignature: Hashable {
    
    public var userInfo: UserDefinedInfo?
    
    // User defined drone info
    public struct UserDefinedInfo: Hashable {
        var customName: String
        var trustStatus: TrustStatus
        
        enum TrustStatus: String, Codable, Hashable {
            case trusted
            case untrusted
            case unknown
            
            var color: Color {
                switch self {
                case .trusted: return .green
                case .untrusted: return .red
                case .unknown: return .gray
                }
            }
            
            var icon: String {
                switch self {
                case .trusted: return "checkmark.shield.fill"
                case .untrusted: return "xmark.shield.fill"
                case .unknown: return "shield.fill"
                }
            }
        }
    }

    //MARK: - ID, MAC and broadcast data
    public struct IdInfo: Hashable {
        public let id: String
        public let type: IdType
        public let protocolVersion: String
        public let uaType: UAType
        public let macAddress: String?
        
        public enum IdType: String, Hashable {
            case serialNumber = "Serial Number (ANSI/CTA-2063-A)"
            case caaRegistration = "CAA Assigned Registration ID"
            case utmAssigned = "UTM (USS) Assigned ID"
            case sessionId = "Specific Session ID"
            case unknown = "Unknown"
        }
        
        public enum UAType: String, Hashable {
            case none = "None"
            case aeroplane = "Aeroplane"
            case helicopter = "Helicopter/Multirotor"
            case gyroplane = "Gyroplane"
            case hybridLift = "Hybrid Lift"
            case ornithopter = "Ornithopter"
            case glider = "Glider"
            case kite = "Kite"
            case freeballoon = "Free Balloon"
            case captive = "Captive Balloon"
            case airship = "Airship"
            case freeFall = "Free Fall/Parachute"
            case rocket = "Rocket"
            case tethered = "Tethered Powered Aircraft"
            case groundObstacle = "Ground Obstacle"
            case other = "Other"
            
            // Icon to display in messageRow
            var icon: String {
                switch self {
                case .none: return "airplane" // Fallback
                case .aeroplane: return "airplane"
                case .helicopter: return "airplane"
                case .gyroplane: return "airplane.circle"
                case .hybridLift: return "airplane.circle"
                case .ornithopter: return "bird"
                case .glider: return "paperplane"
                case .kite: return "wind"
                case .freeballoon: return "balloon"
                case .captive: return "balloon.fill"
                case .airship: return "airplane.circle"
                case .freeFall: return "arrow.down.circle"
                case .rocket: return "rocket"
                case .tethered: return "link.circle"
                case .groundObstacle: return "exclamationmark.triangle"
                case .other: return "questionmark.circle"
                }
            }
        }
        
        public init(id: String, type: IdType, protocolVersion: String, uaType: UAType, macAddress: String? = nil) {
            self.id = id
            self.type = type
            self.protocolVersion = protocolVersion
            self.uaType = uaType
            self.macAddress = macAddress
        }
    }
    
    // MARK: - Positioning & Location
    
    public struct PositionInfo: Hashable {
        public let coordinate: CLLocationCoordinate2D
        public let altitude: Double
        public let altitudeReference: AltitudeReference
        public let lastKnownGoodPosition: CLLocationCoordinate2D?
        public let operatorLocation: CLLocationCoordinate2D?
        public let homeLocation: CLLocationCoordinate2D?
        public let horizontalAccuracy: Double?
        public let verticalAccuracy: Double?
        public let timestamp: TimeInterval
        
        public enum AltitudeReference: String {
            case takeoff = "Takeoff Location"
            case ground = "Ground Level"
            case wgs84 = "WGS84"
        }
        
        public init(coordinate: CLLocationCoordinate2D,
                    altitude: Double,
                    altitudeReference: AltitudeReference,
                    lastKnownGoodPosition: CLLocationCoordinate2D?,
                    operatorLocation: CLLocationCoordinate2D?,
                    homeLocation: CLLocationCoordinate2D?,
                    horizontalAccuracy: Double?,
                    verticalAccuracy: Double?,
                    timestamp: TimeInterval) {
            self.coordinate = coordinate
            self.altitude = altitude
            self.altitudeReference = altitudeReference
            self.lastKnownGoodPosition = lastKnownGoodPosition
            self.operatorLocation = operatorLocation
            self.homeLocation = homeLocation
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.timestamp = timestamp
        }
        
        public static func == (lhs: PositionInfo, rhs: PositionInfo) -> Bool {
            return lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.altitude == rhs.altitude &&
            lhs.altitudeReference == rhs.altitudeReference &&
            lhs.timestamp == rhs.timestamp &&
            compareOptionalCoordinates(lhs.lastKnownGoodPosition, rhs.lastKnownGoodPosition) &&
            compareOptionalCoordinates(lhs.operatorLocation, rhs.operatorLocation) &&
            compareOptionalCoordinates(lhs.homeLocation, rhs.homeLocation) &&
            lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
            lhs.verticalAccuracy == rhs.verticalAccuracy
        }
        
        private static func compareOptionalCoordinates(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D?) -> Bool {
            guard let lhs = lhs, let rhs = rhs else {
                return lhs == nil && rhs == nil
            }
            return lhs.latitude == rhs.latitude &&
            lhs.longitude == rhs.longitude
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
            hasher.combine(altitude)
            hasher.combine(altitudeReference)
            hasher.combine(timestamp)
            if let lastKnown = lastKnownGoodPosition {
                hasher.combine(lastKnown.latitude)
                hasher.combine(lastKnown.longitude)
            }
            if let opLocation = operatorLocation {
                hasher.combine(opLocation.latitude)
                hasher.combine(opLocation.longitude)
            }
            hasher.combine(horizontalAccuracy)
            hasher.combine(verticalAccuracy)
        }
    }
    
    public struct MovementVector: Hashable {
        public let groundSpeed: Double
        public let verticalSpeed: Double
        public let heading: Double
        public let climbRate: Double?
        public let turnRate: Double?
        public let flightPath: [CLLocationCoordinate2D]?
        public let timestamp: TimeInterval
        
        public init(groundSpeed: Double,
                    verticalSpeed: Double,
                    heading: Double,
                    climbRate: Double?,
                    turnRate: Double?,
                    flightPath: [CLLocationCoordinate2D]?,
                    timestamp: TimeInterval) {
            self.groundSpeed = groundSpeed
            self.verticalSpeed = verticalSpeed
            self.heading = heading
            self.climbRate = climbRate
            self.turnRate = turnRate
            self.flightPath = flightPath
            self.timestamp = timestamp
        }
        
        public static func == (lhs: MovementVector, rhs: MovementVector) -> Bool {
            return lhs.groundSpeed == rhs.groundSpeed &&
            lhs.verticalSpeed == rhs.verticalSpeed &&
            lhs.heading == rhs.heading &&
            lhs.climbRate == rhs.climbRate &&
            lhs.turnRate == rhs.turnRate &&
            lhs.timestamp == rhs.timestamp &&
            compareFlightPaths(lhs.flightPath, rhs.flightPath)
        }
        
        private static func compareFlightPaths(_ path1: [CLLocationCoordinate2D]?, _ path2: [CLLocationCoordinate2D]?) -> Bool {
            guard let p1 = path1, let p2 = path2 else {
                return path1 == nil && path2 == nil
            }
            guard p1.count == p2.count else { return false }
            return zip(p1, p2).allSatisfy { coord1, coord2 in
                coord1.latitude == coord2.latitude &&
                coord1.longitude == coord2.longitude
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(groundSpeed)
            hasher.combine(verticalSpeed)
            hasher.combine(heading)
            hasher.combine(climbRate)
            hasher.combine(turnRate)
            hasher.combine(timestamp)
            if let path = flightPath {
                for coord in path {
                    hasher.combine(coord.latitude)
                    hasher.combine(coord.longitude)
                }
            }
        }
    }
    
    public struct HeightInfo: Hashable {
        public let heightAboveGround: Double
        public let heightAboveTakeoff: Double?
        public let referenceType: HeightReferenceType
        public let horizontalAccuracy: Double?
        public let verticalAccuracy: Double?
        public let consistencyScore: Double
        public let lastKnownGoodHeight: Double?
        public let timestamp: TimeInterval
        
        public enum HeightReferenceType: String {
            case ground = "Above Ground Level"
            case takeoff = "Above Takeoff"
            case pressureAltitude = "Pressure Altitude"
            case wgs84 = "WGS84"
        }
        
        public init(heightAboveGround: Double,
                    heightAboveTakeoff: Double?,
                    referenceType: HeightReferenceType,
                    horizontalAccuracy: Double?,
                    verticalAccuracy: Double?,
                    consistencyScore: Double,
                    lastKnownGoodHeight: Double?,
                    timestamp: TimeInterval) {
            self.heightAboveGround = heightAboveGround
            self.heightAboveTakeoff = heightAboveTakeoff
            self.referenceType = referenceType
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.consistencyScore = consistencyScore
            self.lastKnownGoodHeight = lastKnownGoodHeight
            self.timestamp = timestamp
        }
    }
    
    public struct TransmissionInfo: Hashable {
        public let transmissionType: TransmissionType
        public let signalStrength: Double?
        public let expectedSignalStrength: Double?
        public let macAddress: String?
        public let frequency: Double?
        public let protocolType: ProtocolType
        public let messageTypes: Set<MessageType>
        public let timestamp: TimeInterval
        public let metadata: [String: Any]?
        public let channel: Int?
        public let advMode: String?
        public let advAddress: String?
        public let did: Int?
        public let sid: Int?
        public let accessAddress: Int?
        public let phy: Int?
        
        public enum TransmissionType: String {
            case ble = "BT4/5 DroneID"
            case wifi = "WiFi DroneID"
            case esp32 = "ESP32 DroneID"
            case fpv = "FPV Camera"
            case unknown = "Unknown"
        }
        
        public enum ProtocolType: String {
            case openDroneID = "Open Drone ID"
            case legacyRemoteID = "Legacy Remote ID"
            case astmF3411 = "ASTM F3411"
            case custom = "Custom"
        }
        
        public enum MessageType: String, Hashable {
            case bt45 = "BT4/5 DroneID"
            case wifi = "WiFi DroneID"
            case esp32 = "ESP32 DroneID"
            case fpv = "FPV Camera"
        }
        
        public init(transmissionType: TransmissionType,
                    signalStrength: Double?,
                    expectedSignalStrength: Double?,
                    macAddress incomingMacAddress: String? = nil,
                    frequency: Double?,
                    protocolType: ProtocolType,
                    messageTypes: Set<MessageType>,
                    timestamp: TimeInterval,
                    metadata: [String: Any]? = nil,
                    channel: Int? = nil,
                    advMode: String? = nil,
                    advAddress: String? = nil,
                    did: Int? = nil,
                    sid: Int? = nil,
                    accessAddress: Int? = nil,
                    phy: Int? = nil) {
            self.transmissionType = transmissionType
            self.signalStrength = signalStrength
            self.expectedSignalStrength = expectedSignalStrength
            self.macAddress = incomingMacAddress
            self.frequency = frequency
            self.protocolType = protocolType
            self.messageTypes = messageTypes
            self.timestamp = timestamp
            self.metadata = metadata
            self.channel = channel
            self.advMode = advMode
            self.advAddress = advAddress
            self.did = did
            self.sid = sid
            self.accessAddress = accessAddress
            self.phy = phy
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(transmissionType)
                hasher.combine(signalStrength)
                hasher.combine(expectedSignalStrength)
                hasher.combine(macAddress)
                hasher.combine(frequency)
                hasher.combine(protocolType)
                hasher.combine(messageTypes)
                hasher.combine(timestamp)
                hasher.combine(channel)
                hasher.combine(advMode)
                hasher.combine(advAddress)
                hasher.combine(did)
                hasher.combine(sid)
            }

        public static func == (lhs: TransmissionInfo, rhs: TransmissionInfo) -> Bool {
            return lhs.transmissionType == rhs.transmissionType &&
                lhs.signalStrength == rhs.signalStrength &&
                lhs.expectedSignalStrength == rhs.expectedSignalStrength &&
                lhs.macAddress == rhs.macAddress &&
                lhs.frequency == rhs.frequency &&
                lhs.protocolType == rhs.protocolType &&
                lhs.messageTypes == rhs.messageTypes &&
                lhs.timestamp == rhs.timestamp &&
                lhs.channel == rhs.channel &&
                lhs.advMode == rhs.advMode &&
                lhs.advAddress == rhs.advAddress &&
                lhs.did == rhs.did &&
                lhs.sid == rhs.sid
                // Skip metadata in equality check since [String:Any] can't be compared
        }
    }
    

    public struct BroadcastPattern: Hashable {
        public let messageSequence: [TransmissionInfo.MessageType]
        public let intervalPattern: [TimeInterval]
        public let consistency: Double
        public let startTime: TimeInterval
        public let lastUpdate: TimeInterval
        
        public init(messageSequence: [TransmissionInfo.MessageType],
                    intervalPattern: [TimeInterval],
                    consistency: Double,
                    startTime: TimeInterval,
                    lastUpdate: TimeInterval) {
            self.messageSequence = messageSequence
            self.intervalPattern = intervalPattern
            self.consistency = consistency
            self.startTime = startTime
            self.lastUpdate = lastUpdate
        }
    }
    
    public let primaryId: IdInfo
    public let secondaryId: IdInfo?
    public let operatorId: String?
    public let sessionId: String?
    public let position: PositionInfo
    public let movement: MovementVector
    public let heightInfo: HeightInfo
    public let transmissionInfo: TransmissionInfo
    public let broadcastPattern: BroadcastPattern
    public let timestamp: TimeInterval
    public let firstSeen: TimeInterval
    public let messageInterval: TimeInterval?
    
    public init(primaryId: IdInfo,
                secondaryId: IdInfo?,
                operatorId: String?,
                sessionId: String?,
                position: PositionInfo,
                movement: MovementVector,
                heightInfo: HeightInfo,
                transmissionInfo: TransmissionInfo,
                broadcastPattern: BroadcastPattern,
                timestamp: TimeInterval,
                firstSeen: TimeInterval,
                messageInterval: TimeInterval?) {
        self.primaryId = primaryId
        self.secondaryId = secondaryId
        self.operatorId = operatorId
        self.sessionId = sessionId
        self.position = position
        self.movement = movement
        self.heightInfo = heightInfo
        self.transmissionInfo = transmissionInfo
        self.broadcastPattern = broadcastPattern
        self.timestamp = timestamp
        self.firstSeen = firstSeen
        self.messageInterval = messageInterval
    }
}
