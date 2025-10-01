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
        
        if message.isFPVDetection {
            // For FPV, try to center on alert ring
            if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }) {
                let span = MKCoordinateSpan(
                    latitudeDelta: max(ring.radius / 55000, 0.01),
                    longitudeDelta: max(ring.radius / 55000, 0.01)
                )
                let region = MKCoordinateRegion(center: ring.centerCoordinate, span: span)
                _mapCameraPosition = State(initialValue: .region(region))
            } else {
                // Default region if no ring yet
                _mapCameraPosition = State(initialValue: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )
                ))
            }
        } else {
            // Regular drone handling
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
                Text(message.isFPVDetection ? "Signal Range Map" : "Flight Map")
                    .font(.headline)
                Spacer()
                if !message.isFPVDetection {
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
            }

            Map(position: $mapCameraPosition) {
                if message.isFPVDetection {
                    ForEach(cotViewModel.alertRings.filter { $0.droneId == message.uid }) { ring in
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .foregroundStyle(.orange.opacity(0.1))
                            .stroke(.orange, lineWidth: 3)
                        
                        Annotation("Monitor", coordinate: ring.centerCoordinate) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                                .font(.title2)
                                .background(Circle().fill(.white))
                        }
                        
                        Annotation("FPV \(message.fpvFrequency ?? 0)MHz", coordinate: ring.centerCoordinate) {
                            VStack {
                                Text("FPV Signal")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("\(Int(ring.radius))m radius")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                    }
                } else {
                    if let pt = message.coordinate {
                        Annotation("Drone", coordinate: pt) {
                            Image(systemName: "airplane")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .rotationEffect(.degrees(message.headingDeg - 90))
                                .animation(.easeInOut(duration: 0.15), value: message.headingDeg)
                                .foregroundStyle(.blue)
                        }
                    }

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

                    let cleanFlightPath = DroneStorageManager.shared
                        .encounters[message.uid]?.flightPath
                        .filter { !$0.isProximityPoint }
                        .map { $0.coordinate } ?? flightPath
                    
                    if cleanFlightPath.count > 1 {
                        MapPolyline(coordinates: cleanFlightPath)
                            .stroke(.purple, lineWidth: 3)
                    }

                    ForEach(cotViewModel.alertRings.filter { $0.droneId == message.uid }) { ring in
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .stroke(.red.opacity(0.2), lineWidth: 2)
                    }
                }
            }
            .frame(height: 300)
            .cornerRadius(12)
            .onAppear {
                updateMapRegion()
            }
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
                
                // FPV specific information
                if message.isFPVDetection {
                    if let frequency = message.fpvFrequency {
                        DroneInfoRow(title: "Frequency", value: "\(frequency) MHz")
                    }
                    if let bandwidth = message.fpvBandwidth {
                        DroneInfoRow(title: "Bandwidth", value: bandwidth)
                    }
                    if let source = message.fpvSource {
                        DroneInfoRow(title: "Detection Source", value: source)
                    }
                } else {
                    // Regular drone information
                    if !message.description.isEmpty {
                        DroneInfoRow(title: "Description", value: message.description)
                    }
                    if !message.selfIDText.isEmpty {
                        DroneInfoRow(title: "Self-ID", value: message.selfIDText)
                    }
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
                if message.isFPVDetection {
                    // FPV doesn't have location data
                    DroneInfoRow(title: "Current Position", value: "0, 0")
                    DroneInfoRow(title: "Altitude", value: "0 m")
                    DroneInfoRow(title: "Speed", value: "0 m/s")
                    DroneInfoRow(title: "Vertical Speed", value: "0 m/s")
                    
                    Text("FPV signals do not provide location data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                } else {
                    // Regular drone location data
                    DroneInfoRow(title: "Current Position", value: "\(message.lat), \(message.lon)")
                    
                    if let formattedAlt = message.formattedAltitude {
                        DroneInfoRow(title: "Altitude", value: formattedAlt)
                    } else {
                        DroneInfoRow(title: "Altitude", value: "\(message.alt) m")
                    }
                    
                    if let formattedHeight = message.formattedHeight {
                        DroneInfoRow(title: "Height AGL", value: formattedHeight)
                    }
                    
                    if message.speed != "0.0" && !message.speed.isEmpty {
                        DroneInfoRow(title: "Speed", value: "\(message.speed) m/s")
                    }
                    
                    if message.vspeed != "0.0" && !message.vspeed.isEmpty {
                        DroneInfoRow(title: "Vertical Speed", value: "\(message.vspeed) m/s")
                    }
                    
                    // Track data from CoT messages
                    if message.headingDeg != 0.0 {
                        DroneInfoRow(title: "Heading", value: String(format: "%.1f°", message.headingDeg))
                    }
                    
                    if let trackSpeed = message.trackSpeedFormatted {
                        DroneInfoRow(title: "Track Speed", value: trackSpeed)
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
                if message.isFPVDetection {
                    // FPV specific signal information
                    if let fpvRSSI = message.fpvRSSI {
                        DroneInfoRow(title: "Signal Strength", value: String(format: "%.1f", fpvRSSI))
                    } else if let rssi = message.rssi {
                        DroneInfoRow(title: "RSSI", value: "\(rssi) dBm")
                    }
                    
                    if let timestamp = message.fpvTimestamp {
                        DroneInfoRow(title: "Last Detection", value: formatTimestamp(timestamp))
                    }
                } else {
                    // Regular drone signal information
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
                }
                
                // Show signal sources if available (common to both)
                if !message.signalSources.isEmpty {
                    DroneInfoRow(title: "Signal Sources", value: "\(message.signalSources.count)")
                    
                    // Show signal source details
                    ForEach(Array(message.signalSources.enumerated()), id: \.offset) { index, source in
                        HStack {
                            Text(source.type.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(source.rssi) dBm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 16)
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

    private var flightPathStatsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Flight Path Statistics")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 4) {
                if message.isFPVDetection {
                    // FPV doesn't have flight path
                    DroneInfoRow(title: "Total Points", value: "0")
                    DroneInfoRow(title: "Total Distance", value: "0.0 m")
                    DroneInfoRow(title: "Area Covered", value: "0 m × 0 m")
                    
                    Text("FPV signals do not provide flight path data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                } else {
                    DroneInfoRow(title: "Total Points", value: "\(flightPath.count)")
                    
                    if flightPath.count > 1 {
                        let distance = calculateTotalDistance()
                        DroneInfoRow(title: "Total Distance", value: String(format: "%.1f m", distance))
                        
                        if let bounds = calculateFlightBounds() {
                            DroneInfoRow(
                                title: "Area Covered",
                                value: String(format: "%.0f m × %.0f m", bounds.northSouthSpan, bounds.eastWestSpan)
                            )
                        }
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

    // Helper method to format FPV timestamps
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .none
            displayFormatter.timeStyle = .medium
            return displayFormatter.string(from: date)
        }
        
        return timestamp
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
        
        if message.isFPVDetection {
            // For FPV, we don't have drone coordinates, but we might have monitor location from alert ring
            return [] // Will be handled by updateMapRegion for FPV
        }
        
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
        if message.isFPVDetection {
            // For FPV, center on alert ring if available
            if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }) {
                let span = MKCoordinateSpan(
                    latitudeDelta: max(ring.radius / 55000, 0.01),
                    longitudeDelta: max(ring.radius / 55000, 0.01)
                )
                let region = MKCoordinateRegion(center: ring.centerCoordinate, span: span)
                withAnimation(.easeInOut(duration: 0.5)) {
                    mapCameraPosition = .region(region)
                }
            }
        } else {
            // Drone
            let coords = showAllLocations
                ? Self.getAllRelevantCoordinates(message: message, flightPath: flightPath)
                : (message.coordinate.map { [$0] } ?? [])

            let region = Self.calculateRegionForCoordinates(coords)
            withAnimation(.easeInOut(duration: 0.5)) {
                mapCameraPosition = .region(region)
            }
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
    
    private func calculateFlightBounds() -> (northSouthSpan: Double, eastWestSpan: Double)? {
        guard flightPath.count > 1 else { return nil }
        let latitudes = flightPath.map { $0.latitude }
        let longitudes = flightPath.map { $0.longitude }
        let latDelta = (latitudes.max() ?? 0) - (latitudes.min() ?? 0)
        let lonDelta = (longitudes.max() ?? 0) - (longitudes.min() ?? 0)
        let midLatitude = ((latitudes.max() ?? 0) + (latitudes.min() ?? 0)) / 2
        let metersPerDegree = 111_000.0
        let metersPerDegreeLon = metersPerDegree * cos(midLatitude * .pi / 180)
        let northSouthSpan = latDelta * metersPerDegree
        let eastWestSpan = lonDelta * metersPerDegreeLon
        return (northSouthSpan, eastWestSpan)
    }



    private func formatRawMessage() -> String {
        if message.isFPVDetection {
            // Format FPV raw data more cleanly
            var fpvData: [String: Any] = [:]
            
            if let frequency = message.fpvFrequency {
                fpvData["frequency"] = frequency
            }
            if let rssi = message.fpvRSSI {
                fpvData["signal_strength"] = rssi
            }
            if let bandwidth = message.fpvBandwidth {
                fpvData["bandwidth"] = bandwidth
            }
            if let source = message.fpvSource {
                fpvData["detection_source"] = source
            }
            if let timestamp = message.fpvTimestamp {
                fpvData["timestamp"] = timestamp
            }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: fpvData, options: [.prettyPrinted]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        }
        
        // Fall back to original raw message formatting
        if let jsonData = try? JSONSerialization.data(withJSONObject: message.rawMessage, options: [.prettyPrinted]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return message.originalRawString ?? "No raw data available"
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
