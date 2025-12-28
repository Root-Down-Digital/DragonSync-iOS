//
//  LiveMapView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import MapKit

struct LiveMapView: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State public var mapCameraPosition: MapCameraPosition
    @State private var showDroneList = false
    @State private var showDroneDetail = false
    @State private var selectedDrone: CoTViewModel.CoTMessage?
    @State private var selectedFlightPath: [CLLocationCoordinate2D] = []
    @State private var flightPaths: [String: [(coordinate: CLLocationCoordinate2D, timestamp: Date)]] = [:]
    @State private var lastProcessedDrones: [String: CoTViewModel.CoTMessage] = [:]
    @State private var shouldUpdateMapView: Bool = false
    @State private var userHasMovedMap = false
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    init(cotViewModel: CoTViewModel, initialMessage: CoTViewModel.CoTMessage) {
        self.cotViewModel = cotViewModel
        let lat = Double(initialMessage.lat) ?? 0
        let lon = Double(initialMessage.lon) ?? 0
        
        if lat == 0 && lon == 0,
           let ring = cotViewModel.alertRings.first(where: { $0.droneId == initialMessage.uid }) {
            let ringSpan = MKCoordinateSpan(
                latitudeDelta: max(ring.radius / 250, 0.1),
                longitudeDelta: max(ring.radius / 250, 0.1)
            )
            let ringRegion = MKCoordinateRegion(center: ring.centerCoordinate, span: ringSpan)
            _mapCameraPosition = State(initialValue: .region(ringRegion))
        } else {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            let region = MKCoordinateRegion(center: coordinate, span: span)
            _mapCameraPosition = State(initialValue: .region(region))
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
            
            let hasValidLat = coordinate.latitude != 0
            let hasValidLon = coordinate.longitude != 0
            guard hasValidLat || hasValidLon else { continue }
            
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
            guard hasValidLat || hasValidLon else { return nil }
            return coord
        }
    }
    
    private func createDroneDetailView(for message: CoTViewModel.CoTMessage) -> DroneDetailView {
        let flightPath = getValidFlightPath(for: message.uid)
        return DroneDetailView(message: message, flightPath: flightPath, cotViewModel: cotViewModel)
    }
    
    private func resetMapView() {
        userHasMovedMap = false
        
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
                ForEach(flightPaths.keys.sorted(), id: \.self) { droneId in
                    if let path = flightPaths[droneId], path.count > 1 {
                        let validPath = path.filter { pathPoint in
                            let coord = pathPoint.coordinate
                            return coord.latitude != 0 || coord.longitude != 0
                        }
                        if validPath.count > 1 {
                            let coordinates = validPath.map { $0.coordinate }
                            MapPolyline(coordinates: coordinates)
                                .stroke(Color.blue, lineWidth: 2)
                        }
                    }
                }
                
                ForEach(uniqueDrones, id: \.uid) { message in
                    if let coordinate = message.coordinate {
                        let hasValidLat = coordinate.latitude != 0
                        let hasValidLon = coordinate.longitude != 0
                        if hasValidLat || hasValidLon {
                            let isLastDrone = message.uid == uniqueDrones.last?.uid
                            let color = isLastDrone ? Color.red : Color.blue
                            
                            Annotation(message.uid, coordinate: coordinate) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
                
                // MARK: - Aircraft Annotations (ADS-B)
                ForEach(cotViewModel.aircraftTracks) { aircraft in
                    if let coordinate = aircraft.coordinate {
                        Annotation(aircraft.displayName, coordinate: coordinate) {
                            VStack(spacing: 2) {
                                ZStack {
                                    // Aircraft icon with rotation
                                    Image(systemName: "airplane")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(.green)
                                        .rotationEffect(.degrees((aircraft.track ?? 0) - 90))
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                }
                                
                                // Callsign/Hex label
                                Text(aircraft.displayName)
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.2))
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                                
                                // Altitude
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
                
                ForEach(cotViewModel.alertRings, id: \.id) { ring in
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
                if userHasMovedMap {
                    HStack {
                        Spacer()
                        Button(action: resetMapView) {
                            Image(systemName: "arrow.counterclockwise")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                        .padding()
                    }
                }
                
                Spacer()
                let droneCount = uniqueDrones.count
                let aircraftCount = cotViewModel.aircraftTracks.count
                Button(action: { showDroneList.toggle() }) {
                    VStack(spacing: 4) {
                        if droneCount > 0 {
                            Text("\(droneCount) Drone\(droneCount == 1 ? "" : "s")")
                                .font(.footnote)
                        }
                        if aircraftCount > 0 {
                            Text("\(aircraftCount) Aircraft")
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                        if droneCount == 0 && aircraftCount == 0 {
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
        .sheet(isPresented: $showDroneList) {
            NavigationView {
                List(uniqueDrones) { message in
                    let destination = createDroneDetailView(for: message)
                    NavigationLink(destination: destination) {
                        DroneListRowView(message: message, cotViewModel: cotViewModel)
                    }
                }
                .navigationTitle("Active Drones")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showDroneList = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
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
                    print("Rendering new flightpaths & map...")
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
