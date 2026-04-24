//
//  DronesStatusTab.swift
//  WarDragon
//
//  Created on 1/19/26.
//

import SwiftUI
import Charts
import MapKit
import CoreLocation

struct DronesStatusTab: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var sortBy: SortOption = .lastSeen
    @State private var showFilters = false
    @State private var filterOptions = FilterOptions()
    @ObservedObject private var editorManager = DroneEditorManager.shared
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var selectedMapStyle: MapStyleOption = .standard
    @State private var showFlightPaths = true
    @State private var selectedDroneId: String? = nil
    @State private var animationProgress: Double = 0.0
    
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
    
    enum SortOption: String, CaseIterable {
        case lastSeen = "Last Seen"
        case rssi = "Signal Strength"
        case distance = "Distance"
        case manufacturer = "Manufacturer"
    }
    
    struct FilterOptions {
        var showSpoofed = true
        var showFPV = true
        var showNormal = true
        var minimumRSSI: Int = -100
    }
    
    private var filteredAndSortedDrones: [CoTViewModel.CoTMessage] {
        var drones = cotViewModel.parsedMessages
        
        // Apply filters
        drones = drones.filter { drone in
            // Filter by type
            if !filterOptions.showSpoofed && drone.isSpoofed { return false }
            if !filterOptions.showFPV && drone.isFPVDetection { return false }
            if !filterOptions.showNormal && !drone.isSpoofed && !drone.isFPVDetection { return false }
            
            // Filter by RSSI
            if let rssi = drone.rssi, rssi < filterOptions.minimumRSSI { return false }
            
            return true
        }
        
        // Sort
        switch sortBy {
        case .lastSeen:
            return drones.sorted { $0.lastUpdated > $1.lastUpdated }
        case .rssi:
            return drones.sorted { ($0.rssi ?? -100) > ($1.rssi ?? -100) }
        case .distance:
            // Would need user location for true distance sorting
            return drones.sorted { ($0.rssi ?? -100) > ($1.rssi ?? -100) }
        case .manufacturer:
            return drones.sorted { $0.idType < $1.idType }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main list
            if cotViewModel.parsedMessages.isEmpty {
                emptyStateView
            } else {
                List {
                    // Overview Map Section
                    Section {
                        overviewMapView
                            .listRowInsets(EdgeInsets())
                    } header: {
                        HStack {
                            Text("OVERVIEW")
                            Spacer()
                            Text("\(filteredAndSortedDrones.count) DRONE\(filteredAndSortedDrones.count == 1 ? "" : "S")")
                        }
                        .textCase(nil)
                    }
                    
                    // Active drones list
                    Section(header: sectionHeader) {
                        ForEach(filteredAndSortedDrones) { drone in
                            MessageRow(message: drone, cotViewModel: cotViewModel, isCompact: false)
                                .id(drone.uid) // Preserve view identity to prevent sheet dismissal
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    // Just complete immediately - updates are automatic
                    return
                }
            }
        }
        .navigationTitle("Drones")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Filter button
                Button {
                    showFilters.toggle()
                } label: {
                    Label("Filter", systemImage: filterOptions.showAll ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .help("Filter drones")
                
                // Sort menu
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                Spacer()
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                        .labelStyle(.iconOnly)
                }
                .help("Sort drones")
                
                // Clear button
                Button {
                    clearAllDrones()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Clear all drone detections")
                .disabled(cotViewModel.parsedMessages.isEmpty)
            }
        }
        .sheet(isPresented: $showFilters) {
            filterSheet
        }
        .sheet(isPresented: $editorManager.isPresented) {
            DroneInfoEditorSheet()
        }
    }
    
    // MARK: - Subviews
    
    private var overviewMapView: some View {
        VStack(spacing: 0) {
            // Map controls row
            HStack(spacing: 12) {
                // Flight Path Toggle
                Button {
                    showFlightPaths.toggle()
                } label: {
                    Label(showFlightPaths ? "Paths" : "Paths", systemImage: showFlightPaths ? "arrow.triangle.turn.up.right.diamond.fill" : "arrow.triangle.turn.up.right.diamond")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
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
                    Label("Map Style", systemImage: "map")
                        .font(.caption)
                }
                
                // Fit to View button
                Button {
                    fitMapToAllDrones()
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            
            // Map
            Map(position: $mapCameraPosition) {
                // Show drone flight paths if toggle is on
                if showFlightPaths {
                    ForEach(filteredAndSortedDrones, id: \.uid) { drone in
                        let validPath = getValidFlightPathWithCurrent(for: drone)
                        
                        if validPath.count > 1 {
                            let smoothedPath = FlightPathSmoother.smoothPath(validPath, smoothness: 4)
                            MapPolyline(coordinates: smoothedPath)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                
                // Show animated line from selected drone to pilot
                if let selectedId = selectedDroneId,
                   let selectedDrone = filteredAndSortedDrones.first(where: { $0.uid == selectedId }),
                   let droneCoord = selectedDrone.coordinate,
                   let pilotCoord = getPilotLocation(for: selectedDrone),
                   droneCoord.isValid {
                    
                    // Create animated dashed line
                    MapPolyline(coordinates: [droneCoord, pilotCoord])
                        .stroke(Color.orange, style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            dash: [10, 5],
                            dashPhase: animationProgress * 15
                        ))
                }
                
                // Show drones
                ForEach(filteredAndSortedDrones, id: \.uid) { drone in
                    if let coordinate = drone.coordinate, coordinate.isValid {
                        Annotation(drone.uid, coordinate: coordinate) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedDroneId = (selectedDroneId == drone.uid) ? nil : drone.uid
                                    animationProgress = 0.0
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    ZStack {
                                        Circle()
                                            .fill(drone.isFPVDetection ? .orange : (selectedDroneId == drone.uid ? .green : .blue))
                                            .frame(width: selectedDroneId == drone.uid ? 40 : 34, height: selectedDroneId == drone.uid ? 40 : 34)
                                            .shadow(color: .black.opacity(0.3), radius: selectedDroneId == drone.uid ? 4 : 3, x: 0, y: 2)
                                        
                                        Image(systemName: drone.isFPVDetection ? "antenna.radiowaves.left.and.right" : "airplane")
                                            .resizable()
                                            .frame(width: selectedDroneId == drone.uid ? 24 : 20, height: selectedDroneId == drone.uid ? 24 : 20)
                                            .foregroundStyle(.white)
                                            .rotationEffect(.degrees(drone.headingDeg - 90))
                                    }
                                    
                                    if filteredAndSortedDrones.count <= 3 || selectedDroneId == drone.uid {
                                        Text(drone.uid)
                                            .font(.caption2)
                                            .bold()
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background((selectedDroneId == drone.uid ? .green : .blue).opacity(0.2))
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Show home locations for all drones
                ForEach(filteredAndSortedDrones, id: \.uid) { drone in
                    if let homeCoord = getHomeLocation(for: drone) {
                        Annotation("Takeoff", coordinate: homeCoord) {
                            ZStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 24, height: 24)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                Image(systemName: "house.fill")
                                    .foregroundStyle(.white)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                // Show pilot locations for all drones (using latest pilot location from history)
                ForEach(filteredAndSortedDrones, id: \.uid) { drone in
                    if let pilotCoord = getPilotLocation(for: drone) {
                        Annotation("Pilot", coordinate: pilotCoord) {
                            ZStack {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: selectedDroneId == drone.uid ? 28 : 24, height: selectedDroneId == drone.uid ? 28 : 24)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.white)
                                    .font(selectedDroneId == drone.uid ? .body : .caption)
                            }
                            .scaleEffect(selectedDroneId == drone.uid ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: selectedDroneId)
                        }
                    }
                }
                
                // Show alert rings for encrypted/FPV drones
                ForEach(cotViewModel.alertRings.filter { ring in
                    return cotViewModel.parsedMessages.contains { message in
                        let baseRingId = ring.droneId.components(separatedBy: "-").dropLast().joined(separator: "-")
                        let baseMessageId = message.uid
                        let isMatch = ring.droneId == baseMessageId || baseRingId == baseMessageId
                        let hasZeroCoords = (Double(message.lat) ?? 0) == 0 && (Double(message.lon) ?? 0) == 0
                        return isMatch && hasZeroCoords
                    }
                }, id: \.id) { ring in
                    MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                        .foregroundStyle(.yellow.opacity(0.1))
                        .stroke(.yellow, lineWidth: 2)
                    
                    Annotation("FPV", coordinate: ring.centerCoordinate) {
                        VStack {
                            Text("Encrypted")
                                .font(.caption2)
                            Text("\(Int(ring.radius))m")
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                    }
                }
            }
            .mapStyle(selectedMapStyle.mapStyle)
            .frame(height: 250)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onAppear {
                // Start animation loop
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    animationProgress = 1.0
                }
            }
        }
    }
    
    private var sectionHeader: some View {
        HStack {
            Text("\(filteredAndSortedDrones.count) DRONES")
            Spacer()
            if spoofedCount > 0 {
                Label("\(spoofedCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            if fpvCount > 0 {
                Label("\(fpvCount)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .textCase(nil)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Drones Detected")
                .font(.headline)
            
            Text("Drone detections will appear here when Remote ID signals are received")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Drone Types")) {
                    Toggle("Show Normal Drones", isOn: $filterOptions.showNormal)
                    Toggle("Show Spoofed Drones", isOn: $filterOptions.showSpoofed)
                    Toggle("Show FPV Drones", isOn: $filterOptions.showFPV)
                }
                
                Section(header: Text("Signal Strength")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum RSSI: \(filterOptions.minimumRSSI) dBm")
                            .font(.caption)
                        
                        Slider(value: Binding(
                            get: { Double(filterOptions.minimumRSSI) },
                            set: { filterOptions.minimumRSSI = Int($0) }
                        ), in: -100...(-30), step: 5)
                        
                        HStack {
                            Text("Weak (-100)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Strong (-30)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button("Reset Filters") {
                        filterOptions = FilterOptions()
                    }
                }
            }
            .navigationTitle("Filter Drones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showFilters = false
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func detectionTimelineChart(data: [TimelineDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETECTION TIMELINE (Last Hour)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
            
            Chart(data) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(.blue.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.minute())
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var droneStatisticsList: some View {
        Group {
            HStack {
                Text("Total Detections")
                Spacer()
                Text("\(cotViewModel.parsedMessages.count)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Unique MAC Addresses")
                Spacer()
                Text("\(uniqueMACCount)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("ID Randomizing")
                Spacer()
                Text("\(randomizingCount)")
                    .foregroundColor(randomizingCount > 0 ? .yellow : .secondary)
            }
            
            if let avgRSSI = averageRSSI {
                HStack {
                    Text("Average Signal")
                    Spacer()
                    Text("\(avgRSSI) dBm")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("Manufacturers Detected")
                Spacer()
                Text("\(uniqueManufacturers)")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var uniqueMACCount: Int {
        Set(cotViewModel.parsedMessages.compactMap { $0.mac }).count
    }
    
    private var spoofedCount: Int {
        cotViewModel.parsedMessages.filter { $0.isSpoofed }.count
    }
    
    private var fpvCount: Int {
        cotViewModel.parsedMessages.filter { $0.isFPVDetection }.count
    }
    
    private var averageRSSI: Int? {
        let rssiValues = cotViewModel.parsedMessages.compactMap { $0.rssi }
        guard !rssiValues.isEmpty else { return nil }
        return rssiValues.reduce(0, +) / rssiValues.count
    }
    
    private var strongestSignal: Int? {
        cotViewModel.parsedMessages.compactMap { $0.rssi }.max()
    }
    
    private var timeActive: String {
        guard let oldestMessage = cotViewModel.parsedMessages.min(by: { $0.lastUpdated < $1.lastUpdated }) else {
            return "0m"
        }
        
        let duration = Date().timeIntervalSince(oldestMessage.lastUpdated)
        let minutes = Int(duration / 60)
        
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    private var randomizingCount: Int {
        cotViewModel.parsedMessages.filter { msg in
            !msg.idType.contains("CAA") && // Exclude CAA-only
            (cotViewModel.macIdHistory[msg.uid]?.count ?? 0 > 1)
        }.count
    }
    
    private var uniqueManufacturers: Int {
        Set(cotViewModel.parsedMessages.map { $0.idType }).count
    }
    
    private var detectionTimelineData: [TimelineDataPoint]? {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        // Get messages from the last hour
        let recentMessages = cotViewModel.parsedMessages.filter { $0.lastUpdated >= oneHourAgo }
        guard !recentMessages.isEmpty else { return nil }
        
        // Create 12 five-minute buckets
        var buckets: [Date: Int] = [:]
        for i in 0..<12 {
            let bucketTime = oneHourAgo.addingTimeInterval(Double(i) * 300) // 300 seconds = 5 minutes
            buckets[bucketTime] = 0
        }
        
        // Count messages in each bucket
        for message in recentMessages {
            let timeSinceStart = message.lastUpdated.timeIntervalSince(oneHourAgo)
            let bucketIndex = min(11, max(0, Int(timeSinceStart / 300)))
            let bucketTime = oneHourAgo.addingTimeInterval(Double(bucketIndex) * 300)
            buckets[bucketTime, default: 0] += 1
        }
        
        return buckets.sorted { $0.key < $1.key }.map { TimelineDataPoint(time: $0.key, count: $0.value) }
    }
    
    // MARK: - Helper Functions
    
    private func fitMapToAllDrones() {
        let validCoords = filteredAndSortedDrones.compactMap { drone -> CLLocationCoordinate2D? in
            guard let coord = drone.coordinate, coord.isValid else { return nil }
            return coord
        }
        
        guard !validCoords.isEmpty else { return }
        
        let latitudes = validCoords.map(\.latitude)
        let longitudes = validCoords.map(\.longitude)
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
        withAnimation {
            mapCameraPosition = .region(region)
        }
    }
    
    private func getValidFlightPath(for uid: String) -> [CLLocationCoordinate2D] {
        guard let encounter = DroneStorageManager.shared.fetchEncounter(id: uid) else {
            return []
        }
        
        let sortedPoints = encounter.flightPath
            .filter { !$0.isProximityPoint }
            .filter { !($0.latitude == 0 && $0.longitude == 0) }
            .sorted { $0.timestamp < $1.timestamp }
        
        return sortedPoints.map { $0.coordinate }
    }
    
    private func getValidFlightPathWithCurrent(for drone: CoTViewModel.CoTMessage) -> [CLLocationCoordinate2D] {
        var validPath = getValidFlightPath(for: drone.uid)
        
        if let currentCoord = drone.coordinate, validPath.count > 0 {
            if let lastPathCoord = validPath.last,
               !currentCoord.isApproximatelyEqual(to: lastPathCoord, tolerance: 0.0000001) {
                validPath.append(currentCoord)
            }
        }
        
        return validPath
    }
    
    private func clearAllDrones() {
        cotViewModel.parsedMessages.removeAll()
        cotViewModel.droneSignatures.removeAll()
        cotViewModel.macIdHistory.removeAll()
        cotViewModel.macProcessing.removeAll()
        cotViewModel.alertRings.removeAll()
    }
    
    // MARK: - Pilot & Home Location Helpers
    
    /// Get the most recent pilot location from stored operator locations or current message
    private func getPilotLocation(for drone: CoTViewModel.CoTMessage) -> CLLocationCoordinate2D? {
        // First try to get from stored encounter's operator locations (most recent)
        if let encounter = DroneStorageManager.shared.fetchEncounter(id: drone.uid),
           let latestOperatorLocation = encounter.operatorLocations.sorted(by: { $0.timestamp > $1.timestamp }).first {
            return latestOperatorLocation.coordinate
        }
        
        // Fallback to current message pilot location
        if drone.pilotLat != "0.0" && drone.pilotLon != "0.0",
           let plat = Double(drone.pilotLat),
           let plon = Double(drone.pilotLon),
           !(plat == 0 && plon == 0) {
            return CLLocationCoordinate2D(latitude: plat, longitude: plon)
        }
        
        return nil
    }
    
    /// Get the most recent home location from stored home locations or current message
    private func getHomeLocation(for drone: CoTViewModel.CoTMessage) -> CLLocationCoordinate2D? {
        // First try to get from stored encounter's home locations (most recent)
        if let encounter = DroneStorageManager.shared.fetchEncounter(id: drone.uid),
           let latestHomeLocation = encounter.homeLocations.sorted(by: { $0.timestamp > $1.timestamp }).first {
            return latestHomeLocation.coordinate
        }
        
        // Fallback to current message home location
        if drone.homeLat != "0.0" && drone.homeLon != "0.0",
           let lat = Double(drone.homeLat),
           let lon = Double(drone.homeLon),
           !(lat == 0 && lon == 0) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        return nil
    }
    
    /// Get unique pilot locations to avoid duplicates on map
    private func getUniquePilotLocations() -> [(droneId: String, coordinate: CLLocationCoordinate2D)] {
        var uniqueLocations: [String: CLLocationCoordinate2D] = [:]
        
        for drone in filteredAndSortedDrones {
            if let pilotCoord = getPilotLocation(for: drone) {
                // Use coordinate as key to deduplicate
                let key = "\(pilotCoord.latitude),\(pilotCoord.longitude)"
                if uniqueLocations[key] == nil {
                    uniqueLocations[key] = pilotCoord
                }
            }
        }
        
        return uniqueLocations.map { ($0.key, $0.value) }
    }
    
    /// Get unique home locations to avoid duplicates on map
    private func getUniqueHomeLocations() -> [(droneId: String, coordinate: CLLocationCoordinate2D)] {
        var uniqueLocations: [String: CLLocationCoordinate2D] = [:]
        
        for drone in filteredAndSortedDrones {
            if let homeCoord = getHomeLocation(for: drone) {
                // Use coordinate as key to deduplicate
                let key = "\(homeCoord.latitude),\(homeCoord.longitude)"
                if uniqueLocations[key] == nil {
                    uniqueLocations[key] = homeCoord
                }
            }
        }
        
        return uniqueLocations.map { ($0.key, $0.value) }
    }
}

// MARK: - Supporting Views

private struct DroneStatusRow: View {
    let drone: CoTViewModel.CoTMessage
    @ObservedObject var cotViewModel: CoTViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Status indicator
                Circle()
                    .fill(signalColor)
                    .frame(width: 10, height: 10)
                
                // Drone ID
                Text(drone.uid)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                Spacer()
                
                // Time since last update
                Text(timeSinceUpdate)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Details row
            HStack(spacing: 16) {
                // RSSI
                if let rssi = drone.rssi {
                    DetailItem(
                        icon: "antenna.radiowaves.left.and.right",
                        label: "\(rssi) dBm",
                        color: signalColor
                    )
                }
                
                // ID Type
                DetailItem(
                    icon: "tag",
                    label: drone.idType,
                    color: .blue
                )
                
                // Drone Type
                DetailItem(
                    icon: "airplane",
                    label: formatDroneType(drone.uaType),
                    color: .purple
                )
            }
            
            // Badges row
            HStack(spacing: 8) {
                if drone.isSpoofed {
                    Badge(text: "SPOOFED", color: .yellow)
                }
                
                if drone.isFPVDetection {
                    Badge(text: "FPV", color: .orange)
                }
                
                if let macCount = cotViewModel.macIdHistory[drone.uid]?.count, macCount > 1 {
                    Badge(text: "RANDOMIZING", color: .red)
                }
                
                if let mac = drone.mac {
                    Badge(text: "MAC: \(String(mac.suffix(8)))", color: .gray)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var signalColor: Color {
        guard let rssi = drone.rssi else { return .gray }
        switch rssi {
        case ..<(-75): return .red
        case (-75)...(-60): return .yellow
        default: return .green
        }
    }
    
    private var timeSinceUpdate: String {
        let interval = Date().timeIntervalSince(drone.lastUpdated)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
    
    private func formatDroneType(_ type: DroneSignature.IdInfo.UAType) -> String {
        switch type {
        case .helicopter: return "Helicopter"
        case .aeroplane: return "Aeroplane"
        case .gyroplane: return "Gyroplane"
        default: return "Other"
        }
    }
}

private struct DetailItem: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(4)
    }
}

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon in circular background
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
            }
            
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Data Models

private struct TimelineDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let count: Int
}

// MARK: - Extensions

private extension DronesStatusTab.FilterOptions {
    var showAll: Bool {
        showNormal && showSpoofed && showFPV && minimumRSSI == -100
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DronesStatusTab(cotViewModel: CoTViewModel(statusViewModel: StatusViewModel()))
    }
}
