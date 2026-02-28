import Foundation
import CoreLocation

public extension CLLocationCoordinate2D {
    var isValid: Bool {
        let isNullIsland = (latitude == 0 && longitude == 0)
        let isLatitudeValid = latitude >= -90 && latitude <= 90
        let isLongitudeValid = longitude >= -180 && longitude <= 180
        return !isNullIsland && isLatitudeValid && isLongitudeValid
    }
    
    var isInValidRange: Bool {
        let isLatitudeValid = latitude >= -90 && latitude <= 90
        let isLongitudeValid = longitude >= -180 && longitude <= 180
        return isLatitudeValid && isLongitudeValid
    }
    
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
    
    func isApproximatelyEqual(to other: CLLocationCoordinate2D, tolerance: Double = 0.0001) -> Bool {
        abs(latitude - other.latitude) < tolerance && abs(longitude - other.longitude) < tolerance
    }
}

extension CLLocationCoordinate2D: @retroactive Codable {
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
