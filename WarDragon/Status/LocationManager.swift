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
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
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
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
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
                startLocationUpdates()
            case .denied, .restricted:
                userLocation = nil
            default:
                break
            }
        }
    }
}
