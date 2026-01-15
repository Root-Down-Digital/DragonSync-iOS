//
//  LocationManager.swift
//  WarDragon
//
//  Created by Luke on 7/29/25.
//

import Foundation
import CoreLocation

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    @Published var userLocation: CLLocation?
    @Published var locationPermissionStatus: CLAuthorizationStatus = .notDetermined
    
    // Track which features are actively using location
    private var activeConsumers: Set<LocationConsumer> = []
    
    enum LocationConsumer: String, Hashable {
        case adsb = "ADS-B"
        case opensky = "OpenSky"
        case tak = "TAK"
        case status = "Status"
        case other = "Other"
    }
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Use distance filter to save battery - only update when moved 100m
        locationManager.distanceFilter = 100
        locationPermissionStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        // Don't auto-start if already authorized - let consumers request explicitly
        if locationPermissionStatus == .authorizedWhenInUse || locationPermissionStatus == .authorizedAlways {
            print(" Location already authorized")
            return
        }
        
        print(" Requesting location permission")
        locationManager.requestWhenInUseAuthorization()
    }
    
    // Start location updates for a specific consumer
    func startLocationUpdates(for consumer: LocationConsumer) {
        guard locationPermissionStatus == .authorizedWhenInUse || locationPermissionStatus == .authorizedAlways else {
            print("⚠️ Location not authorized for \(consumer.rawValue)")
            return
        }
        
        activeConsumers.insert(consumer)
        print(" Starting location updates for \(consumer.rawValue) (total consumers: \(activeConsumers.count))")
        
        // Only start if not already running
        locationManager.startUpdatingLocation()
    }
    
    // Stop location updates for a specific consumer
    func stopLocationUpdates(for consumer: LocationConsumer) {
        activeConsumers.remove(consumer)
        print(" Stopped location updates for \(consumer.rawValue)")
        
        // Only stop if no other consumers are active
        if activeConsumers.isEmpty {
            print(" No active consumers, stopping location manager")
            locationManager.stopUpdatingLocation()
        } else {
            print(" \(activeConsumers.count) consumers still active: \(activeConsumers.map { $0.rawValue }.joined(separator: ", "))")
        }
    }
    
    // For backward compatibility
    func startLocationUpdates() {
        startLocationUpdates(for: .other)
    }
    
    func stopLocationUpdates() {
        stopLocationUpdates(for: .other)
    }
    
    // Stop all location updates (for app termination, etc.)
    func stopAllLocationUpdates() {
        activeConsumers.removeAll()
        locationManager.stopUpdatingLocation()
        print(" Stopped all location updates")
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            userLocation = locations.last
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            locationPermissionStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // Don't auto-start - let consumers request explicitly
                print(" Location authorization granted: \(status == .authorizedWhenInUse ? "When In Use" : "Always")")
            case .denied, .restricted:
                print("⚠️ Location access denied or restricted")
                userLocation = nil
                activeConsumers.removeAll()
                locationManager.stopUpdatingLocation()
            default:
                break
            }
        }
    }
}
