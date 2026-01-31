//
//  FlightPathSmoother.swift
//  WarDragon
//
//  Created by Assistant on 1/31/26.
//

import CoreLocation
import MapKit

public struct FlightPathSmoother {
    
    public static func smoothPath(_ coordinates: [CLLocationCoordinate2D], smoothness: Int = 3) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        
        var smoothedPath: [CLLocationCoordinate2D] = []
        
        // Add first point
        smoothedPath.append(coordinates[0])
        
        // For each segment between points, interpolate using Catmull-Rom spline
        for i in 0..<(coordinates.count - 1) {
            let p0 = i > 0 ? coordinates[i - 1] : coordinates[i]
            let p1 = coordinates[i]
            let p2 = coordinates[i + 1]
            let p3 = i + 2 < coordinates.count ? coordinates[i + 2] : coordinates[i + 1]
            
            // Generate interpolated points
            for j in 1...smoothness {
                let t = Double(j) / Double(smoothness + 1)
                let interpolated = catmullRomInterpolate(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
                smoothedPath.append(interpolated)
            }
            
            // Add the next control point
            smoothedPath.append(p2)
        }
        
        return smoothedPath
    }
    
    /// Performs Catmull-Rom spline interpolation between four control points
    /// - Parameters:
    ///   - p0: Point before start
    ///   - p1: Start point
    ///   - p2: End point
    ///   - p3: Point after end
    ///   - t: Interpolation parameter (0.0 to 1.0)
    /// - Returns: Interpolated coordinate
    private static func catmullRomInterpolate(
        p0: CLLocationCoordinate2D,
        p1: CLLocationCoordinate2D,
        p2: CLLocationCoordinate2D,
        p3: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let t2 = t * t
        let t3 = t2 * t
        
        // Catmull-Rom basis functions
        let lat = 0.5 * (
            (2.0 * p1.latitude) +
            (-p0.latitude + p2.latitude) * t +
            (2.0 * p0.latitude - 5.0 * p1.latitude + 4.0 * p2.latitude - p3.latitude) * t2 +
            (-p0.latitude + 3.0 * p1.latitude - 3.0 * p2.latitude + p3.latitude) * t3
        )
        
        let lon = 0.5 * (
            (2.0 * p1.longitude) +
            (-p0.longitude + p2.longitude) * t +
            (2.0 * p0.longitude - 5.0 * p1.longitude + 4.0 * p2.longitude - p3.longitude) * t2 +
            (-p0.longitude + 3.0 * p1.longitude - 3.0 * p2.longitude + p3.longitude) * t3
        )
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    public static func smoothPathSimple(_ coordinates: [CLLocationCoordinate2D], windowSize: Int = 3) -> [CLLocationCoordinate2D] {
        guard coordinates.count > windowSize else { return coordinates }
        
        var smoothed: [CLLocationCoordinate2D] = []
        
        for i in 0..<coordinates.count {
            let start = max(0, i - windowSize / 2)
            let end = min(coordinates.count, i + windowSize / 2 + 1)
            let window = coordinates[start..<end]
            
            let avgLat = window.map(\.latitude).reduce(0, +) / Double(window.count)
            let avgLon = window.map(\.longitude).reduce(0, +) / Double(window.count)
            
            smoothed.append(CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon))
        }
        
        return smoothed
    }
    
    public static func smoothPathGeodesic(_ coordinates: [CLLocationCoordinate2D], segmentLength: Double = 50) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        
        var smoothedPath: [CLLocationCoordinate2D] = []
        smoothedPath.append(coordinates[0])
        
        for i in 0..<(coordinates.count - 1) {
            let start = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            let end = CLLocation(latitude: coordinates[i + 1].latitude, longitude: coordinates[i + 1].longitude)
            
            let distance = start.distance(from: end)
            
            // Skip if distance is too small
            guard distance > 1.0 else { continue }
            
            let numSegments = max(1, Int(distance / segmentLength))
            
            // Generate intermediate points along geodesic
            for j in 1..<numSegments {
                let fraction = Double(j) / Double(numSegments)
                let interpolated = interpolateGeodesic(from: start, to: end, fraction: fraction)
                smoothedPath.append(interpolated.coordinate)
            }
            
            smoothedPath.append(coordinates[i + 1])
        }
        
        return smoothedPath
    }
    
    /// Interpolates a point along a geodesic path
    /// - Parameters:
    ///   - from: Start location
    ///   - to: End location
    ///   - fraction: Interpolation fraction (0.0 to 1.0)
    /// - Returns: Interpolated location
    private static func interpolateGeodesic(from: CLLocation, to: CLLocation, fraction: Double) -> CLLocation {
        let lat1 = from.coordinate.latitude * .pi / 180
        let lon1 = from.coordinate.longitude * .pi / 180
        let lat2 = to.coordinate.latitude * .pi / 180
        let lon2 = to.coordinate.longitude * .pi / 180
        
        // Calculate great circle distance
        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1
        
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        let d = c
        
        // Interpolate along the great circle
        let A = sin((1 - fraction) * d) / sin(d)
        let B = sin(fraction * d) / sin(d)
        
        let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
        let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
        let z = A * sin(lat1) + B * sin(lat2)
        
        let lat = atan2(z, sqrt(x * x + y * y))
        let lon = atan2(y, x)
        
        return CLLocation(
            latitude: lat * 180 / .pi,
            longitude: lon * 180 / .pi
        )
    }
}
