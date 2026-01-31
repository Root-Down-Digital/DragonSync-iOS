//
//  LiveMapView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import MapKit
import CoreLocation

struct LiveMapView: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State public var mapCameraPosition: MapCameraPosition
    @State private var showDroneDetail = false
    @State private var selectedDrone: CoTViewModel.CoTMessage?
    @State private var selectedFlightPath: [CLLocationCoordinate2D] = []
    @State private var flightPaths: [String: [(coordinate: CLLocationCoordinate2D, timestamp: Date)]] = [:]
    @State private var lastProcessedDrones: [String: CoTViewModel.CoTMessage] = [:]
    @State private var shouldUpdateMapView: Bool = false
    @State private var userHasMovedMap = false
    @State private var showFlightPaths = true
    @State private var selectedMapStyle: MapStyleOption = .standard
    let filterMode: FilterMode
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    enum MapStyleOption {
        case standard
        case hybrid
        case satellite
        
        var mapStyle: MapStyle {
            switch self {
            case .standard: return .standard
            case .hybrid: return .hybrid
            case .satellite: return .imagery
            }
        }
    }
    
    enum FilterMode {
        case drones
        case aircraft
        case both
    }
    
    init(cotViewModel: CoTViewModel, initialMessage: CoTViewModel.CoTMessage, filterMode: FilterMode = .both) {
        self.filterMode = filterMode
        self.cotViewModel = cotViewModel
        let lat = Double(initialMessage.lat) ?? 0
        let lon = Double(initialMessage.lon) ?? 0
        
        var initialFlightPaths: [String: [(coordinate: CLLocationCoordinate2D, timestamp: Date)]] = [:]
        for (droneId, encounter) in DroneStorageManager.shared.encounters {
            let pathPoints = encounter.flightPath.map { point in
                (coordinate: point.coordinate, timestamp: Date(timeIntervalSince1970: point.timestamp))
            }
            if !pathPoints.isEmpty {
                initialFlightPaths[droneId] = pathPoints
            }
        }
        _flightPaths = State(initialValue: initialFlightPaths)
        
        // Try to fit all visible targets (drones + aircraft) based on filter mode
        var allCoords: [CLLocationCoordinate2D] = []
        
        // Add drone coordinates (only if not filtering to aircraft only)
        if filterMode != .aircraft {
            allCoords += cotViewModel.parsedMessages.compactMap { message -> CLLocationCoordinate2D? in
                guard let coord = message.coordinate else { return nil }
                let hasValidCoord = coord.latitude != 0 || coord.longitude != 0
                return hasValidCoord ? coord : nil
            }
        }
        
        // Add aircraft coordinates (only if not filtering to drones only)
        if filterMode != .drones {
            allCoords += cotViewModel.aircraftTracks.compactMap { $0.coordinate }
        }
        
        // If we have multiple targets, fit them all in view
        if allCoords.count > 1 {
            let latitudes = allCoords.map(\.latitude)
            let longitudes = allCoords.map(\.longitude)
            let minLat = latitudes.min()!
            let maxLat = latitudes.max()!
            let minLon = longitudes.min()!
            let maxLon = longitudes.max()!
            
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            
            let span = MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
            )
            
            let region = MKCoordinateRegion(center: center, span: span)
            _mapCameraPosition = State(initialValue: .region(region))
        }
        // Check for FPV detection with alert ring (single target)
        else if lat == 0 && lon == 0,
           let ring = cotViewModel.alertRings.first(where: { $0.droneId == initialMessage.uid }) {
            let ringSpan = MKCoordinateSpan(
                latitudeDelta: max(ring.radius / 250, 0.1),
                longitudeDelta: max(ring.radius / 250, 0.1)
            )
            let ringRegion = MKCoordinateRegion(center: ring.centerCoordinate, span: ringSpan)
            _mapCameraPosition = State(initialValue: .region(ringRegion))
        }
        // If we have valid coordinates for initial message, use them
        else if lat != 0 || lon != 0 {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            let region = MKCoordinateRegion(center: coordinate, span: span)
            _mapCameraPosition = State(initialValue: .region(region))
        }
        // If we have a single aircraft, use its location
        else if let firstAircraft = cotViewModel.aircraftTracks.first,
                let coord = firstAircraft.coordinate {
            let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            let region = MKCoordinateRegion(center: coord, span: span)
            _mapCameraPosition = State(initialValue: .region(region))
        }
        // Default fallback
        else {
            _mapCameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            ))
        }
    }
    
    private func cleanOldPathPoints() {
        let maxAge: TimeInterval = 3600
        let now = Date()
        
        for (droneId, path) in flightPaths {
            let updatedPath = path.filter { now.timeIntervalSince($0.timestamp) < maxAge }
            flightPaths[droneId] = updatedPath
        }
    }
    
    private var uniqueDrones: [CoTViewModel.CoTMessage] {
        var latestDronePositions: [String: CoTViewModel.CoTMessage] = [:]
        var droneOrder: [String] = []
        
        for message in cotViewModel.parsedMessages {
            let hasCoordinate = message.coordinate != nil
            let isNotCAA = !message.idType.contains("CAA")
            
            if isNotCAA && hasCoordinate {
                if latestDronePositions[message.uid] == nil {
                    droneOrder.append(message.uid)
                }
                latestDronePositions[message.uid] = message
            }
        }
        
        return droneOrder.compactMap { latestDronePositions[$0] }
    }
    
    private var uniqueAircraft: [Aircraft] {
        var latestAircraftPositions: [String: Aircraft] = [:]
        var aircraftOrder: [String] = []
        
        for aircraft in cotViewModel.aircraftTracks {
            let identifier = aircraft.hex // Use hex as unique identifier
            
            if latestAircraftPositions[identifier] == nil {
                aircraftOrder.append(identifier)
            }
            latestAircraftPositions[identifier] = aircraft
        }
        
        return aircraftOrder.compactMap { latestAircraftPositions[$0] }
    }
    
    func updateFlightPathsIfNewData() {
        let newMessages = cotViewModel.parsedMessages.filter { message in
            guard let lastMessage = lastProcessedDrones[message.uid] else {
                return true
            }
            
            let latChanged = message.lat != lastMessage.lat
            let lonChanged = message.lon != lastMessage.lon
            return latChanged || lonChanged
        }
        
        guard !newMessages.isEmpty else { return }
        
        for message in newMessages {
            guard let coordinate = message.coordinate else { continue }
            
            // Both lat and lon must be non-zero (use AND not OR)
            let hasValidLat = coordinate.latitude != 0
            let hasValidLon = coordinate.longitude != 0
            guard hasValidLat && hasValidLon else { continue }
            
            var path = flightPaths[message.uid] ?? []
            
            if let lastPoint = path.last {
                let lastLocation = CLLocation(
                    latitude: lastPoint.coordinate.latitude,
                    longitude: lastPoint.coordinate.longitude
                )
                let currentLocation = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                let distance = lastLocation.distance(from: currentLocation)
                let timeDiff = Date().timeIntervalSince(lastPoint.timestamp)
                
                if distance < 1.0 && timeDiff < 5.0 {
                    continue
                }
            }
            
            let pathPoint = (coordinate: coordinate, timestamp: Date())
            path.append(pathPoint)
            
            if path.count > 200 {
                path.removeFirst()
            }
            
            flightPaths[message.uid] = path
            lastProcessedDrones[message.uid] = message
        }
    }
    
    private func getValidFlightPath(for uid: String) -> [CLLocationCoordinate2D] {
        guard let path = flightPaths[uid] else { return [] }
        return path.compactMap { pathPoint in
            let coord = pathPoint.coordinate
            let hasValidLat = coord.latitude != 0
            let hasValidLon = coord.longitude != 0
            // Both coordinates must be non-zero (use AND not OR)
            guard hasValidLat && hasValidLon else { return nil }
            return coord
        }
    }
    
    /// Get flight path for a drone and ensure it ends at current position
    private func getValidFlightPathWithCurrent(for drone: CoTViewModel.CoTMessage) -> [CLLocationCoordinate2D] {
        var validPath = getValidFlightPath(for: drone.uid)
        
        // Ensure path ends at current position
        if let currentCoord = drone.coordinate, validPath.count > 0 {
            if let lastPathCoord = validPath.last {
                let latDiff = abs(currentCoord.latitude - lastPathCoord.latitude)
                let lonDiff = abs(currentCoord.longitude - lastPathCoord.longitude)
                // If moved at all, append current position
                if latDiff > 0.0000001 || lonDiff > 0.0000001 {
                    validPath.append(currentCoord)
                }
            }
        }
        
        return validPath
    }
    
    /// Get flight path for an aircraft and ensure it ends at current position
    private func getAircraftFlightPathWithCurrent(for aircraft: Aircraft) -> [CLLocationCoordinate2D] {
        guard let currentCoord = aircraft.coordinate else {
            return []
        }
        
        var coordinates = aircraft.positionHistory.map { $0.coordinate }
        
        if coordinates.isEmpty {
            return [currentCoord]
        }
        
        // Always replace the last point with current position to ensure perfect alignment
        coordinates[coordinates.count - 1] = currentCoord
        
        return coordinates
    }
    
    private func createDroneDetailView(for message: CoTViewModel.CoTMessage) -> DroneDetailView {
        let flightPath = getValidFlightPath(for: message.uid)
        return DroneDetailView(message: message, flightPath: flightPath, cotViewModel: cotViewModel)
    }
    
    private func resetMapView() {
        userHasMovedMap = false
        
        // Collect coordinates from both drones and aircraft based on filter mode
        var validCoords: [CLLocationCoordinate2D] = []
        
        // Add drone coordinates (only if not filtering to aircraft only)
        if filterMode != .aircraft {
            validCoords += uniqueDrones.compactMap { drone -> CLLocationCoordinate2D? in
                guard let coord = drone.coordinate else { return nil }
                let hasValidLat = coord.latitude != 0
                let hasValidLon = coord.longitude != 0
                guard hasValidLat || hasValidLon else { return nil }
                return coord
            }
        }
        
        // Add aircraft coordinates (only if not filtering to drones only)
        if filterMode != .drones {
            validCoords += uniqueAircraft.compactMap { aircraft -> CLLocationCoordinate2D? in
                aircraft.coordinate
            }
        }
        
        guard !validCoords.isEmpty else { return }
        
        let latitudes = validCoords.map(\.latitude)
        let longitudes = validCoords.map(\.longitude)
        let minLat = latitudes.min()!
        let maxLat = latitudes.max()!
        let minLon = longitudes.min()!
        let maxLon = longitudes.max()!
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        let deltaLat = max((maxLat - minLat) * 1.2, 0.05)
        let deltaLon = max((maxLon - minLon) * 1.2, 0.05)
        let span = MKCoordinateSpan(latitudeDelta: deltaLat, longitudeDelta: deltaLon)
        let region = MKCoordinateRegion(center: center, span: span)
        
        withAnimation {
            mapCameraPosition = .region(region)
        }
    }
    
    var body: some View {
        ZStack {
            Map(position: $mapCameraPosition, interactionModes: .all) {
                // Show drone flight paths only if showing drones and toggle is on
                if filterMode != .aircraft && showFlightPaths {
                    ForEach(uniqueDrones, id: \.uid) { drone in
                        let validPath = getValidFlightPathWithCurrent(for: drone)
                        
                        if validPath.count > 1 {
                            // Smooth the path for better visual appearance
                            let smoothedPath = FlightPathSmoother.smoothPath(validPath, smoothness: 4)
                            MapPolyline(coordinates: smoothedPath)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                
                // Show aircraft flight paths only if showing aircraft and toggle is on
                if filterMode != .drones && showFlightPaths {
                    ForEach(uniqueAircraft, id: \.hex) { aircraft in
                        let coordinates = getAircraftFlightPathWithCurrent(for: aircraft)
                        
                        if coordinates.count > 1 {
                            // Smooth the path for better visual appearance
                            let smoothedPath = FlightPathSmoother.smoothPath(coordinates, smoothness: 4)
                            MapPolyline(coordinates: smoothedPath)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                
                // Show drone markers only if showing drones
                if filterMode != .aircraft {
                    ForEach(uniqueDrones, id: \.uid) { message in
                        if let coordinate = message.coordinate {
                            let hasValidLat = coordinate.latitude != 0
                            let hasValidLon = coordinate.longitude != 0
                            if hasValidLat || hasValidLon {
                                let isLastDrone = message.uid == uniqueDrones.last?.uid
                                let color = isLastDrone ? Color.red : Color.blue
                                
                                Annotation("", coordinate: coordinate) {
                                    VStack(spacing: 2) {
                                        ZStack {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 30, height: 30)
                                            
                                            Image(systemName: "airplane")
                                                .resizable()
                                                .frame(width: 18, height: 18)
                                                .foregroundStyle(.white)
                                                .rotationEffect(.degrees(message.headingDeg - 90))
                                        }
                                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                                        
                                        Text(message.uid)
                                            .font(.caption2)
                                            .bold()
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(color.opacity(0.2))
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if filterMode != .drones {
                    ForEach(uniqueAircraft, id: \.hex) { aircraft in
                        if let coordinate = aircraft.coordinate {
                            Annotation(aircraft.displayName, coordinate: coordinate) {
                                VStack(spacing: 2) {
                                    ZStack {
                                        Image(systemName: "airplane")
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                            .foregroundStyle(.green)
                                            .rotationEffect(.degrees((aircraft.track ?? 0) - 90))
                                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                    }
                                    
                                    Text(aircraft.displayName)
                                        .font(.caption2)
                                        .bold()
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.2))
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(4)
                                    
                                    if let alt = aircraft.altitudeFeet {
                                        Text("\(alt)ft")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Only show alert rings for encrypted/FPV drones if showing drones
                if filterMode != .aircraft {
                    ForEach(cotViewModel.alertRings.filter { ring in
                        // Only show alert rings if there are actual drones (not just aircraft)
                        let hasDrones = !uniqueDrones.isEmpty
                        guard hasDrones else { return false }
                        
                        // Check if this ring belongs to an actual drone/FPV detection in parsedMessages
                        return cotViewModel.parsedMessages.contains { message in
                            // Match ring to message, accounting for ID suffixes like "-highest", "-lowest", "-median"
                            let baseRingId = ring.droneId.components(separatedBy: "-").dropLast().joined(separator: "-")
                            let baseMessageId = message.uid
                            
                            // Only show if it matches AND the message has zero coordinates (encrypted/FPV)
                            let isMatch = ring.droneId == baseMessageId || baseRingId == baseMessageId
                            let hasZeroCoords = (Double(message.lat) ?? 0) == 0 && (Double(message.lon) ?? 0) == 0
                            
                            return isMatch && hasZeroCoords
                        }
                    }, id: \.id) { ring in
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .foregroundStyle(.yellow.opacity(0.1))
                            .stroke(.yellow, lineWidth: 2)
                        
                        let rssiText = "RSSI: \(ring.rssi) dBm"
                        Annotation(rssiText, coordinate: ring.centerCoordinate) {
                            VStack {
                                Text("Encrypted Drone")
                                    .font(.caption)
                                Text("\(Int(ring.radius))m radius")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .mapStyle(selectedMapStyle.mapStyle)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        userHasMovedMap = true
                    }
            )
            .gesture(
                MagnificationGesture(minimumScaleDelta: 0.01)
                    .onChanged { _ in
                        userHasMovedMap = true
                    }
            )
            
            VStack {
                // Top buttons - Fit to View, Flight Path Toggle, and Map Style
                HStack {
                    Spacer()
                    
                    // Flight Path Toggle
                    Button {
                        showFlightPaths.toggle()
                    } label: {
                        Label(showFlightPaths ? "Paths" : "Paths", systemImage: showFlightPaths ? "arrow.triangle.turn.up.right.diamond.fill" : "arrow.triangle.turn.up.right.diamond")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding(.top)
                    
                    // Map Style Picker
                    Menu {
                        Button {
                            selectedMapStyle = .standard
                        } label: {
                            Label("Standard", systemImage: selectedMapStyle == .standard ? "checkmark" : "map")
                        }
                        
                        Button {
                            selectedMapStyle = .hybrid
                        } label: {
                            Label("Hybrid", systemImage: selectedMapStyle == .hybrid ? "checkmark" : "map.fill")
                        }
                        
                        Button {
                            selectedMapStyle = .satellite
                        } label: {
                            Label("Satellite", systemImage: selectedMapStyle == .satellite ? "checkmark" : "globe.americas.fill")
                        }
                    } label: {
                        Label("Map", systemImage: "map")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding(.top)
                    
                    // Fit to View button
                    Button(action: resetMapView) {
                        Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding(.top)
                    .padding(.trailing)
                }
                
                Spacer()
                let droneCount = uniqueDrones.count
                let aircraftCount = cotViewModel.aircraftTracks.count
                // Detection count button - tapping dismisses the map and returns to Detections tab
                Button(action: { 
                    // Dismiss this view to return to the calling screen (Detections tab)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let presentingVC = window.rootViewController?.presentedViewController {
                        presentingVC.dismiss(animated: true)
                    }
                }) {
                    VStack(spacing: 4) {
                        // Show counts based on filter mode
                        if filterMode != .aircraft && droneCount > 0 {
                            Text("\(droneCount) Drone\(droneCount == 1 ? "" : "s")")
                                .font(.footnote)
                        }
                        if filterMode != .drones && aircraftCount > 0 {
                            Text("\(aircraftCount) Aircraft")
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                        // Show "No Targets" only if the current filter has no data
                        if (filterMode == .drones && droneCount == 0) ||
                           (filterMode == .aircraft && aircraftCount == 0) ||
                           (filterMode == .both && droneCount == 0 && aircraftCount == 0) {
                            Text("No Targets")
                                .font(.footnote)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showDroneDetail) {
            if let drone = selectedDrone {
                NavigationView {
                    DroneDetailView(
                        message: drone,
                        flightPath: selectedFlightPath,
                        cotViewModel: cotViewModel
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showDroneDetail = false
                            }
                        }
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            updateFlightPathsIfNewData()
            
            if !userHasMovedMap && shouldUpdateMapView {
                // Collect coordinates from both drones and aircraft
                var validCoords: [CLLocationCoordinate2D] = []
                
                // Add drone coordinates
                validCoords += uniqueDrones.compactMap { drone -> CLLocationCoordinate2D? in
                    guard let coord = drone.coordinate else { return nil }
                    let hasValidLat = coord.latitude != 0
                    let hasValidLon = coord.longitude != 0
                    guard hasValidLat || hasValidLon else { return nil }
                    return coord
                }
                
                // Add aircraft coordinates
                validCoords += cotViewModel.aircraftTracks.compactMap { aircraft -> CLLocationCoordinate2D? in
                    aircraft.coordinate
                }
                
                if !validCoords.isEmpty {
                    // Only update if something meaningful has changed
                    let latitudes = validCoords.map(\.latitude)
                    let longitudes = validCoords.map(\.longitude)
                    let minLat = latitudes.min()!
                    let maxLat = latitudes.max()!
                    let minLon = longitudes.min()!
                    let maxLon = longitudes.max()!
                    
                    let centerLat = (minLat + maxLat) / 2
                    let centerLon = (minLon + maxLon) / 2
                    let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
                    
                    let deltaLat = max((maxLat - minLat) * 1.2, 0.05)
                    let deltaLon = max((maxLon - minLon) * 1.2, 0.05)
                    let span = MKCoordinateSpan(latitudeDelta: deltaLat, longitudeDelta: deltaLon)
                    let region = MKCoordinateRegion(center: center, span: span)
                    
                    withAnimation {
                        mapCameraPosition = .region(region)
                    }
                }
            }
        }
    }
}

struct DroneListRowView: View {
    let message: CoTViewModel.CoTMessage
    let cotViewModel: CoTViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(message.uid)
                .font(.appHeadline)
            
            let positionText = "Position: \(message.lat), \(message.lon)"
            Text(positionText)
                .font(.appCaption)
            
            if !message.description.isEmpty {
                let descText = "Description: \(message.description)"
                Text(descText)
                    .font(.appCaption)
            }
            
            let pilotLatValid = message.pilotLat != "0.0"
            let pilotLonValid = message.pilotLon != "0.0"
            if pilotLatValid && pilotLonValid {
                let pilotText = "Pilot: \(message.pilotLat), \(message.pilotLon)"
                Text(pilotText)
                    .font(.appCaption)
            }
            
            if let macs = cotViewModel.macIdHistory[message.uid] {
                let macCount = macs.count
                if macCount > 1 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        let macText = "MAC randomizing (\(macCount))"
                        Text(macText)
                            .font(.appCaption)
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
    }
}
