//
//  DroneDetailView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//


import SwiftUI
import MapKit

struct DroneDetailView: View {
    let message: CoTViewModel.CoTMessage
    let flightPath: [CLLocationCoordinate2D]
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var mapCameraPosition: MapCameraPosition
    @State private var showAllLocations = true
    
    init(message: CoTViewModel.CoTMessage, flightPath: [CLLocationCoordinate2D], cotViewModel: CoTViewModel) {
        self.message = message
        self.flightPath = flightPath
        self.cotViewModel = cotViewModel
        
        // Calculate map region to show all relevant locations
        let allCoordinates = Self.getAllRelevantCoordinates(message: message, flightPath: flightPath)
        
        if allCoordinates.isEmpty {
            _mapCameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            ))
        } else {
            let region = Self.calculateRegionForCoordinates(allCoordinates)
            _mapCameraPosition = State(initialValue: .region(region))
        }
    }

    //MARK: - Main Detail View

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Show sections of details
                
                mapSection
            
                droneInfoSection
                
                locationDetailsSection
                
                if !flightPath.isEmpty {
                    flightPathStatsSection
                }
                
                // Signal information
                signalInfoSection
                
                // Raw data section
                rawDataSection
            }
            .padding()
        }
        .navigationTitle(message.uid)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var mapSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Flight Map")
                    .font(.headline)
                Spacer()
                Button {
                    showAllLocations.toggle()
                    updateMapRegion()
                } label: {
                    Text(showAllLocations ? "Drone Only" : "Show All")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }

            Map(position: $mapCameraPosition) {
                // Drone
                if let pt = message.coordinate {
                    Annotation("Drone", coordinate: pt) {
                        Image(systemName: "airplane")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .rotationEffect(.degrees(message.headingDeg))
                            .animation(.easeInOut(duration: 0.15), value: message.headingDeg)
                            .foregroundStyle(.blue)
                    }
                }

                // Home
                if message.homeLat != "0.0",
                   let lat = Double(message.homeLat),
                   let lon = Double(message.homeLon)
                {
                    Annotation("Home", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.green)
                            .background(Circle().fill(.white))
                            .frame(width: 18, height: 18)
                    }
                }

                // Pilot
                if message.pilotLat != "0.0",
                   let plat = Double(message.pilotLat),
                   let plon = Double(message.pilotLon)
                {
                    Annotation("Pilot", coordinate: CLLocationCoordinate2D(latitude: plat, longitude: plon)) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.orange)
                            .background(Circle().fill(.white))
                            .frame(width: 18, height: 18)
                    }
                }

                // Flight-path
                if flightPath.count > 1 {
                    MapPolyline(coordinates: flightPath)
                        .stroke(.purple, lineWidth: 3)
                }

                // Alert rings
                ForEach(cotViewModel.alertRings.filter { $0.droneId == message.uid }) { ring in
                    MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                        .stroke(.red.opacity(0.2), lineWidth: 2)
                }
            }
            .frame(height: 300)
            .cornerRadius(12)
            // Center on first appear
            .onAppear {
                updateMapRegion()
            }
            // Re-center whenever latitude changes (new closure signature)
            .onChange(of: message.coordinate?.latitude) { oldLat, newLat in
                updateMapRegion()
            }
        }
    }




    private var droneInfoSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Drone Information")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 4) {
                DroneInfoRow(title: "Type", value: message.type)
                DroneInfoRow(title: "ID", value: message.id)
                DroneInfoRow(title: "ID Type", value: message.idType)
                if !message.description.isEmpty {
                    DroneInfoRow(title: "Description", value: message.description)
                }
                if !message.selfIDText.isEmpty {
                    DroneInfoRow(title: "Self-ID", value: message.selfIDText)
                }
                if let manufacturer = message.manufacturer {
                    DroneInfoRow(title: "Manufacturer", value: manufacturer)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
    
    private var locationDetailsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Location Details")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 4) {
                // Current position
                DroneInfoRow(title: "Current Position", value: "\(message.lat), \(message.lon)")
                DroneInfoRow(title: "Altitude", value: "\(message.alt) m")
                if let height = message.height {
                    DroneInfoRow(title: "Height AGL", value: "\(height) m")
                }
                if message.speed != "" {
                    DroneInfoRow(title: "Speed", value: "\(message.speed) m/s")
                }
                
                DroneInfoRow(title: "Vertical Speed", value: "\(message.vspeed) m/s")
                
                // Track data from CoT messages
                if let course = message.trackSpeed, course != "0.0" && !course.isEmpty {
                    DroneInfoRow(title: "Course", value: "\(course)°")
                }
                if let speed = message.trackCourse, speed != "0.0" {
                    DroneInfoRow(title: "Track Speed", value: "\(speed) m/s")
                }
    
                
                Divider()
                
                // Home location
                if message.homeLat != "0.0" && message.homeLon != "0.0" {
                    DroneInfoRow(title: "Home Location", value: "\(message.homeLat), \(message.homeLon)")
                }
                
                // Pilot location
                if message.pilotLat != "0.0" && message.pilotLon != "0.0" {
                    DroneInfoRow(title: "Pilot Location", value: "\(message.pilotLat), \(message.pilotLon)")
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
    
    private var flightPathStatsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Flight Path Statistics")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 4) {
                DroneInfoRow(title: "Total Points", value: "\(flightPath.count)")
                
                if flightPath.count > 1 {
                    let distance = calculateTotalDistance()
                    DroneInfoRow(title: "Total Distance", value: String(format: "%.1f m", distance))
                    
                    if let bounds = calculateFlightBounds() {
                        DroneInfoRow(title: "Area Covered", value: String(format: "%.3f° × %.3f°", bounds.latSpan, bounds.lonSpan))
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
    
    private var signalInfoSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Signal Information")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 4) {
                if let rssi = message.rssi {
                    DroneInfoRow(title: "RSSI", value: "\(rssi) dBm")
                }
                
                if let mac = message.mac {
                    DroneInfoRow(title: "MAC Address", value: mac)
                }
                
                // Show MAC randomization if detected
                if let macs = cotViewModel.macIdHistory[message.uid], macs.count > 1 {
                    DroneInfoRow(title: "MAC Randomization", value: "Detected (\(macs.count) MACs)")
                }
                
                // Show signal sources if available
                if !message.signalSources.isEmpty {
                    DroneInfoRow(title: "Signal Sources", value: "\(message.signalSources.count)")
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
    
    private var rawDataSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Raw Data")
                    .font(.headline)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(formatRawMessage())
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemBackground))
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private static func getAllRelevantCoordinates(message: CoTViewModel.CoTMessage, flightPath: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        
        // Current drone position
        if let droneCoordinate = message.coordinate {
            coordinates.append(droneCoordinate)
        }
        
        // Home location
        if message.homeLat != "0.0" && message.homeLon != "0.0",
           let homeLat = Double(message.homeLat),
           let homeLon = Double(message.homeLon) {
            coordinates.append(CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon))
        }
        
        // Pilot location
        if message.pilotLat != "0.0" && message.pilotLon != "0.0",
           let pilotLat = Double(message.pilotLat),
           let pilotLon = Double(message.pilotLon) {
            coordinates.append(CLLocationCoordinate2D(latitude: pilotLat, longitude: pilotLon))
        }
        
        // Flight path
        coordinates.append(contentsOf: flightPath)
        
        return coordinates
    }
    
    private static func calculateRegionForCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let deltaLat = max((maxLat - minLat) * 1.3, 0.01) // Add 30% padding, minimum 0.01°
        let deltaLon = max((maxLon - minLon) * 1.3, 0.01)
        
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: deltaLat, longitudeDelta: deltaLon)
        )
    }
    
    private func updateMapRegion() {
        let coords = showAllLocations
            ? Self.getAllRelevantCoordinates(message: message, flightPath: flightPath)
            : (message.coordinate.map { [$0] } ?? [])

        let region = Self.calculateRegionForCoordinates(coords)
        withAnimation(.easeInOut(duration: 0.5)) {
            mapCameraPosition = .region(region)
        }
    }
    
    private func calculateTotalDistance() -> Double {
        guard flightPath.count > 1 else { return 0 }
        
        var totalDistance: Double = 0
        for i in 1..<flightPath.count {
            let location1 = CLLocation(latitude: flightPath[i-1].latitude, longitude: flightPath[i-1].longitude)
            let location2 = CLLocation(latitude: flightPath[i].latitude, longitude: flightPath[i].longitude)
            totalDistance += location1.distance(from: location2)
        }
        return totalDistance
    }
    
    private func calculateFlightBounds() -> (latSpan: Double, lonSpan: Double)? {
        guard flightPath.count > 1 else { return nil }
        
        let latitudes = flightPath.map(\.latitude)
        let longitudes = flightPath.map(\.longitude)
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        return (latSpan: maxLat - minLat, lonSpan: maxLon - minLon)
    }
    
    private func formatRawMessage() -> String {
        // Remove the unnecessary cast since rawMessage is already [String: Any]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message.rawMessage, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            return "Error formatting raw data: \(error.localizedDescription)"
        }
        return "No raw data available"
    }
}

struct DroneInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
