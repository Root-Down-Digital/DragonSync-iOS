//
//  CLLocationCoordinate2D+Extensions.swift
//  WarDragon
//
//  Utility extensions for coordinate validation and operations
//

import Foundation
import CoreLocation

extension CLLocationCoordinate2D {
    /// Check if coordinate is valid (not 0,0 and within valid ranges)
    var isValid: Bool {
        // Check for null island (0,0)
        let isNullIsland = (latitude == 0 && longitude == 0)
        
        // Check for valid ranges
        let isLatitudeValid = latitude >= -90 && latitude <= 90
        let isLongitudeValid = longitude >= -180 && longitude <= 180
        
        return !isNullIsland && isLatitudeValid && isLongitudeValid
    }
    
    /// Check if coordinate is within valid ranges (allows 0,0)
    var isInValidRange: Bool {
        let isLatitudeValid = latitude >= -90 && latitude <= 90
        let isLongitudeValid = longitude >= -180 && longitude <= 180
        return isLatitudeValid && isLongitudeValid
    }
    
    /// Distance to another coordinate in meters
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let toLocation = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    /// Check if this coordinate is approximately equal to another (within tolerance)
    func isApproximatelyEqual(to other: CLLocationCoordinate2D, tolerance: Double = 0.0001) -> Bool {
        let latDiff = abs(self.latitude - other.latitude)
        let lonDiff = abs(self.longitude - other.longitude)
        return latDiff < tolerance && lonDiff < tolerance
    }
}

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}
