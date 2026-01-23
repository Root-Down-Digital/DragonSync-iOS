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
    @Published private(set) var isUpdatingLocation = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters  // Lower accuracy for battery life
        locationManager.distanceFilter = 100  // Only update every 100 meters (increased from 50)
        locationManager.pausesLocationUpdatesAutomatically = true  // Save battery
        locationManager.activityType = .other
        locationManager.allowsBackgroundLocationUpdates = false  // Disable background updates to save resources
        locationPermissionStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        // Don't request if already authorized
        if locationPermissionStatus == .authorizedWhenInUse || locationPermissionStatus == .authorizedAlways {
            startLocationUpdates()
            return
        }
        
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        guard locationPermissionStatus == .authorizedWhenInUse || locationPermissionStatus == .authorizedAlways else {
            return
        }
        guard !isUpdatingLocation else { return }
        
        print("📍 LocationManager: Starting location updates")
        locationManager.startUpdatingLocation()
        isUpdatingLocation = true
    }
    
    func stopLocationUpdates() {
        guard isUpdatingLocation else { return } // Only stop if running
        
        print("📍 LocationManager: Stopping location updates")
        locationManager.stopUpdatingLocation()
        isUpdatingLocation = false
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
                // Don't auto-start - let the app control when location is needed
                print("📍 LocationManager: Location authorized but not auto-starting")
            case .denied, .restricted:
                userLocation = nil
                stopLocationUpdates()
            default:
                break
            }
        }
    }
}
