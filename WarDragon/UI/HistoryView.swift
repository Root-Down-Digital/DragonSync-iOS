//
//  HistoryView.swift
//  WarDragon
//
//  Created by Luke on 1/21/25.
//

import Foundation
import UIKit
import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct StoredEncountersView: View {
    @Query(
        sort: \StoredDroneEncounter.lastSeen, 
        order: .reverse
    ) private var encounters: [StoredDroneEncounter]
    
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .lastSeen
    let cotViewModel: CoTViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var storage = SwiftDataStorageManager.shared
    
    // Cache for expensive computed values
    @State private var cachedEncounterStats: [String: EncounterStats] = [:]
    
    enum SortOrder {
        case lastSeen, firstSeen, maxAltitude, maxSpeed
    }
    
    struct EncounterStats {
        let maxAltitude: Double
        let maxSpeed: Double
        let averageRSSI: Double
        let flightPointCount: Int
        let signatureCount: Int
    }
    
    var sortedEncounters: [StoredDroneEncounter] {
        // Group by MAC address to deduplicate (only if needed)
        let uniqueEncounters: [StoredDroneEncounter]
        
        // Skip expensive deduplication if not needed
        let hasDuplicates = Set(encounters.map { $0.metadata["mac"] ?? $0.id }).count != encounters.count
        
        if hasDuplicates {
            uniqueEncounters = Dictionary(grouping: encounters) { encounter in
                encounter.metadata["mac"] ?? encounter.id
            }.values.map { encounters in
                encounters.max { $0.lastSeen < $1.lastSeen }!
            }
        } else {
            uniqueEncounters = encounters
        }
        
        // Fast filter
        let filtered: [StoredDroneEncounter]
        if searchText.isEmpty {
            filtered = uniqueEncounters
        } else {
            let lowercasedSearch = searchText.lowercased()
            filtered = uniqueEncounters.filter { encounter in
                encounter.id.lowercased().contains(lowercasedSearch) ||
                (encounter.metadata["caaRegistration"]?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }
        
        // Sort efficiently
        return filtered.sorted { first, second in
            switch sortOrder {
            case .lastSeen: 
                return first.lastSeen > second.lastSeen
            case .firstSeen: 
                return first.firstSeen < second.firstSeen
            case .maxAltitude:
                // Use cached values if available
                let firstAlt = cachedEncounterStats[first.id]?.maxAltitude ?? computeMaxAltitude(first)
                let secondAlt = cachedEncounterStats[second.id]?.maxAltitude ?? computeMaxAltitude(second)
                return firstAlt > secondAlt
            case .maxSpeed:
                // Use cached values if available
                let firstSpeed = cachedEncounterStats[first.id]?.maxSpeed ?? computeMaxSpeed(first)
                let secondSpeed = cachedEncounterStats[second.id]?.maxSpeed ?? computeMaxSpeed(second)
                return firstSpeed > secondSpeed
            }
        }
    }
    
    private func computeMaxAltitude(_ encounter: StoredDroneEncounter) -> Double {
        // Use cached value from model - NEVER access relationships
        return encounter.cachedMaxAltitude
    }
    
    private func computeMaxSpeed(_ encounter: StoredDroneEncounter) -> Double {
        // Use cached value from model - NEVER access relationships
        return encounter.cachedMaxSpeed
    }
    
    private func updateCache(for encounter: StoredDroneEncounter, maxAltitude: Double? = nil, maxSpeed: Double? = nil) {
        var stats = cachedEncounterStats[encounter.id] ?? EncounterStats(
            maxAltitude: 0,
            maxSpeed: 0,
            averageRSSI: 0,
            flightPointCount: 0,
            signatureCount: 0
        )
        
        if let maxAlt = maxAltitude {
            stats = EncounterStats(
                maxAltitude: maxAlt,
                maxSpeed: stats.maxSpeed,
                averageRSSI: stats.averageRSSI,
                flightPointCount: stats.flightPointCount,
                signatureCount: stats.signatureCount
            )
        }
        
        if let maxSpd = maxSpeed {
            stats = EncounterStats(
                maxAltitude: stats.maxAltitude,
                maxSpeed: maxSpd,
                averageRSSI: stats.averageRSSI,
                flightPointCount: stats.flightPointCount,
                signatureCount: stats.signatureCount
            )
        }
        
        cachedEncounterStats[encounter.id] = stats
    }
    
    var body: some View {
        List {
            // MARK: - Aircraft History Section
            Section {
                NavigationLink(destination: ADSBHistoryChartView()) {
                    HStack {
                        Image(systemName: "airplane.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aircraft History")
                                .font(.appHeadline)
                            Text("View/visualize all tracked aircraft")
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // MARK: - Drone Encounters Section
            // Group encounters by type
            let fpvEncounters = sortedEncounters.filter { $0.id.hasPrefix("fpv-") || $0.metadata["isFPVDetection"] == "true" }
            let regularEncounters = sortedEncounters.filter { !$0.id.hasPrefix("fpv-") && $0.metadata["isFPVDetection"] != "true" }
            
            // FPV Detections Section
            if !fpvEncounters.isEmpty {
                Section {
                    ForEach(fpvEncounters) { encounter in
                        NavigationLink(destination: EncounterDetailView(encounter: encounter)
                            .environmentObject(cotViewModel)) {
                                EncounterRow(encounter: encounter)
                            }
                            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                    }
                    .onDelete { indexSet in
                        // Disable animations during delete to prevent accessing deleted objects
                        withAnimation(nil) {
                            for index in indexSet {
                                let encounterToDelete = fpvEncounters[index]
                                modelContext.delete(encounterToDelete)
                                // Clean up cache
                                cachedEncounterStats.removeValue(forKey: encounterToDelete.id)
                            }
                            // Force immediate save to prevent faulting issues
                            try? modelContext.save()
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                        Text("FPV Detections")
                        Spacer()
                        Text("\(fpvEncounters.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Regular Drone Encounters Section
            if !regularEncounters.isEmpty {
                Section {
                    ForEach(regularEncounters) { encounter in
                        NavigationLink(destination: EncounterDetailView(encounter: encounter)
                            .environmentObject(cotViewModel)) {
                                EncounterRow(encounter: encounter)
                            }
                            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                    }
                    .onDelete { indexSet in
                        // Disable animations during delete to prevent accessing deleted objects
                        withAnimation(nil) {
                            for index in indexSet {
                                let encounterToDelete = regularEncounters[index]
                                modelContext.delete(encounterToDelete)
                                // Clean up cache
                                cachedEncounterStats.removeValue(forKey: encounterToDelete.id)
                            }
                            // Force immediate save to prevent faulting issues
                            try? modelContext.save()
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "airplane")
                            .foregroundStyle(.blue)
                        Text("Remote ID Drones")
                        Spacer()
                        Text("\(regularEncounters.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped) // Better performance than plain list
        .searchable(text: $searchText, prompt: "Search by ID or CAA Registration")
        .navigationTitle("Encounter History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        storage.shareCSV(from: rootVC)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        Text("Last Seen").tag(SortOrder.lastSeen)
                        Text("First Seen").tag(SortOrder.firstSeen)
                        Text("Max Altitude").tag(SortOrder.maxAltitude)
                        Text("Max Speed").tag(SortOrder.maxSpeed)
                    }
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .alert("Delete All Encounters", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                storage.deleteAllEncounters()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    struct EncounterRow: View {
        let encounter: StoredDroneEncounter
        
        private var isValid: Bool {
            encounter.modelContext != nil
        }
        
        private var isFPVDetection: Bool {
            guard isValid else { return false }
            return encounter.id.hasPrefix("fpv-") || encounter.metadata["isFPVDetection"] == "true"
        }
        
        private var cachedMaxAltitude: Double {
            guard isValid else { return 0 }
            return encounter.maxAltitude
        }
        
        private var cachedMaxSpeed: Double {
            guard isValid else { return 0 }
            return encounter.maxSpeed
        }
        
        private var cachedAverageRSSI: Double {
            guard isValid else { return 0 }
            return encounter.averageRSSI
        }
        
        private var flightPointCount: Int {
            guard isValid else { return 0 }
            return encounter.cachedFlightPointCount
        }
        
        private var caaRegistration: String? {
            guard isValid else { return nil }
            return encounter.metadata["caaRegistration"]
        }
        
        private var macAddress: String? {
            guard isValid else { return nil }
            return encounter.metadata["mac"]
        }
        
        private var metadata: [String: String] {
            guard isValid else { return [:] }
            return encounter.metadata
        }
        
        // FPV-specific properties
        private var fpvFrequency: String? {
            guard isValid, isFPVDetection else { return nil }
            return encounter.metadata["fpvFrequency"] ?? encounter.metadata["frequency"]
        }
        
        private var fpvSource: String? {
            guard isValid, isFPVDetection else { return nil }
            return encounter.metadata["fpvSource"]
        }
        
        var body: some View {
            if !isValid {
                EmptyView()
            } else {
                actualBody
            }
        }
        
        private var actualBody: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Show FPV badge for FPV detections
                    if isFPVDetection {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                    
                    if !encounter.customName.isEmpty {
                        Text(encounter.customName)
                            .font(.appHeadline)
                            .foregroundColor(.primary)
                        
                        Text(isFPVDetection ? encounter.id : ensureDronePrefix(encounter.id))
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    } else {
                        if isFPVDetection {
                            // For FPV, show frequency prominently
                            if let freq = fpvFrequency {
                                Text("FPV \(freq) MHz")
                                    .font(.appHeadline)
                            } else {
                                Text(encounter.id)
                                    .font(.appHeadline)
                            }
                        } else {
                            Text(ensureDronePrefix(encounter.id))
                                .font(.appHeadline)
                        }
                    }
                    
                    if let caaReg = caaRegistration {
                        Text("CAA: \(caaReg)")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Only show heading icon for non-FPV drones
                    if !isFPVDetection {
                        let heading: Double = {
                            func parseHeading(_ key: String) -> Double? {
                                guard let raw = metadata[key]?
                                    .replacingOccurrences(of: "°", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines),
                                      let value = Double(raw)
                                else { return nil }
                                return (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                            }
                            
                            if let trackCourse = metadata["trackCourse"], let course = Double(trackCourse) {
                                return course
                            } else if let direction = metadata["direction"], let dir = Double(direction) {
                                return dir
                            } else {
                                return parseHeading("course") ?? parseHeading("bearing") ?? parseHeading("direction") ?? 0
                            }
                        }()
                        
                        Image(systemName: "airplane")
                            .foregroundStyle(.blue)
                            .rotationEffect(.degrees(heading - 90))
                    }
                }
                
                // FPV-specific metadata
                if isFPVDetection {
                    if let source = fpvSource {
                        Text("Source: \(source)")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Regular drone MAC address
                    if let mac = metadata["mac"] {
                        Text("MAC: \(mac)")
                            .font(.appCaption)
                    }
                }
                
                // Stats row - different for FPV vs regular drones
                if isFPVDetection {
                    fpvStatsRow
                } else {
                    regularDroneStatsRow
                }
                
                Text("Duration: \(formatDuration(encounter.totalFlightTime))")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        
        // FPV-specific stats display
        private var fpvStatsRow: some View {
            HStack(spacing: 4) {
                VStack(spacing: 2) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f", cachedAverageRSSI))
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("dBm")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Image(systemName: "waveform")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    if let freq = fpvFrequency {
                        Text(freq)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("N/A")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                    }
                    Text("MHz")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Image(systemName: "map")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    let totalDetections = Int(metadata["totalDetections"] ?? "0") ?? 0
                    let displayCount = totalDetections > 0 ? totalDetections : flightPointCount
                    Text("\(displayCount)")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("detections")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        
        // Regular drone stats display
        private var regularDroneStatsRow: some View {
            HStack(spacing: 4) {
                VStack(spacing: 2) {
                    Image(systemName: "map")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("\(flightPointCount)")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("points")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f", cachedMaxAltitude))
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("m")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Image(systemName: "speedometer")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f", cachedMaxSpeed))
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("m/s")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                if cachedAverageRSSI != 0 {
                    VStack(spacing: 2) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f", cachedAverageRSSI))
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text("dB")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        
        private func formatDuration(_ time: TimeInterval) -> String {
            let hours = Int(time) / 3600
            let minutes = Int(time) % 3600 / 60
            let seconds = Int(time) % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        
        private func ensureDronePrefix(_ id: String) -> String {
            return id.hasPrefix("drone-") ? id : "drone-\(id)"
        }
    }
    
    struct EncounterDetailView: View {
        let encounter: StoredDroneEncounter
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var modelContext
        @State private var showingDeleteConfirmation = false
        @State private var showingInfoEditor = false
        @State private var showFlightPath = true
        @State private var selectedMapType: MapStyle = .standard
        @State private var mapCameraPosition: MapCameraPosition = .automatic
        @EnvironmentObject var cotViewModel: CoTViewModel
        @State private var flightPoints: [StoredFlightPoint] = []
        @State private var signatures: [StoredSignature] = []
        @State private var isDataLoaded = false
        @State private var isFPVDetection = false
        
        enum MapStyle {
            case standard, satellite, hybrid
        }
        
        var body: some View {
            // Guard against deleted/faulted encounters
            if encounter.modelContext == nil {
                ContentUnavailableView(
                    "Encounter Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This encounter may have been deleted.")
                )
            } else {
                encounterDetailContent
            }
        }
        
        @ViewBuilder
        private var encounterDetailContent: some View {
            ScrollView {
                VStack(spacing: 16) {
                    // Custom name and trust status section
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Show FPV badge for FPV detections
                                if isFPVDetection {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 24))
                                }
                                
                                if !encounter.customName.isEmpty {
                                    Text(encounter.customName)
                                        .font(.system(.title2, design: .monospaced))
                                        .foregroundColor(.primary)
                                } else {
                                    if isFPVDetection {
                                        // Extract frequency from ID or metadata
                                        if let freq = encounter.metadata["fpvFrequency"] ?? encounter.metadata["frequency"] {
                                            Text("FPV \(freq) MHz")
                                                .font(.system(.title2, design: .monospaced))
                                                .foregroundColor(.primary)
                                        } else {
                                            Text("FPV Detection")
                                                .font(.system(.title2, design: .monospaced))
                                                .foregroundColor(.primary)
                                        }
                                    } else {
                                        Text("Unnamed Drone")
                                            .font(.system(.title2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Only show FAA lookup for regular drones
                                if !isFPVDetection {
                                    if let mac = encounter.metadata["mac"],
                                       !encounter.id.isEmpty {
                                        let remoteId = encounter.id.replacingOccurrences(of: "drone-", with: "")
                                        FAALookupButton(mac: mac, remoteId: remoteId)
                                    }
                                    
                                    Image(systemName: encounter.trustStatus.icon)
                                        .foregroundColor(encounter.trustStatus.color)
                                        .font(.system(size: 24))
                                }
                                
                                Button(action: { showingInfoEditor = true }) {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(encounter.id)
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    //MARK - View Sections
                    
                    // Map - only show if we have flight data and data is loaded (or if FPV with alert ring)
                    if isDataLoaded && (encounter.cachedFlightPointCount > 0 || isFPVDetection) {
                        mapSection
                    }
                    
                    // Encounters section
                    encounterStats
                    
                    //                  metadataSection // TODO metadata section
                    
                    if !encounter.macAddresses.isEmpty && encounter.macAddresses.count > 1 {
                        macSection
                    }
                    
                    // Flight data stats - only show if data is loaded
                    if isDataLoaded {
                        flightDataSection
                    }
                    
                    // Raw message
                    rawMessagesSection
                }
                .padding()
            }
            .navigationTitle("Encounter Details")
            .onAppear {
                loadRelationshipData()
                setupInitialMapPosition()
            }
            .sheet(isPresented: $showingInfoEditor) {
                NavigationView {
                    DroneInfoEditor(droneId: encounter.id)
                        .navigationTitle("Edit Drone Info")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingInfoEditor = false
                                }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("Show Flight Path", isOn: $showFlightPath)
                        
                        Divider()
                        
                        Picker("Map Style", selection: $selectedMapType) {
                            Text("Standard").tag(MapStyle.standard)
                            Text("Satellite").tag(MapStyle.satellite)
                            Text("Hybrid").tag(MapStyle.hybrid)
                        }
                        
                        Divider()
                        
                        Button {
                            exportKML()
                        } label: {
                            Label("Export KML", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete Encounter", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        modelContext.delete(encounter)
                        try? modelContext.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this encounter? This action cannot be undone.")
            }
            .onChange(of: encounter.modelContext) { oldValue, newValue in
                if newValue == nil {
                    dismiss()
                }
            }
        }
        
        private var mapSection: some View {
            // Use @State loaded data instead of direct relationship access
            let droneFlightPoints = flightPoints.filter { !$0.isProximityPoint }
            let proximityPointsWithRssi = flightPoints.filter { $0.isProximityPoint && $0.proximityRssi != nil }
            
            let pilotItems = buildPilotItems()
            let homeItems = buildHomeItems()
            let alertRings = cotViewModel.alertRings.filter { ring in
                ring.droneId == encounter.id ||
                ring.droneId.hasPrefix("\(encounter.id)-")
            }
            
            return Map(position: $mapCameraPosition) {
                Group {
                    if showFlightPath && droneFlightPoints.count > 1 {
                        // Smooth the path for better visual appearance
                        let smoothedPath = FlightPathSmoother.smoothPath(droneFlightPoints.map { $0.coordinate }, smoothness: 4)
                        MapPolyline(coordinates: smoothedPath)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    
                    if let start = droneFlightPoints.first {
                        Annotation("First Detection", coordinate: start.coordinate) {
                            Image(systemName: "1.circle.fill")
                                .foregroundStyle(.green)
                                .background(Circle().fill(.white))
                        }
                    }
                    
                    if droneFlightPoints.count > 1, let end = droneFlightPoints.last {
                        Annotation("Latest Detection", coordinate: end.coordinate) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.red)
                                .background(Circle().fill(.white))
                        }
                    }
                }
                
                Group {
                    if !proximityPointsWithRssi.isEmpty {
                        ForEach(proximityPointsWithRssi.indices, id: \.self) { idx in
                            let point = proximityPointsWithRssi[idx]
                            let rssi = point.proximityRssi!
                            let radius = point.proximityRadius ?? 100.0
                            
                            MapCircle(center: point.coordinate, radius: radius)
                                .foregroundStyle(.orange.opacity(0.1))
                                .stroke(.orange, lineWidth: 2)
                            
                            Annotation("RSSI: \(Int(rssi))dBm", coordinate: point.coordinate) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(.orange)
                                    .background(Circle().fill(.white))
                            }
                        }
                    }
                }
                
                Group {
                    // Draw pilot trail if there's movement
                    let pilotCoordinates = pilotItems.map { $0.coordinate }
                    if pilotCoordinates.count > 1 {
                        // Smooth the pilot path for better visual appearance
                        let smoothedPilotPath = FlightPathSmoother.smoothPath(pilotCoordinates, smoothness: 4)
                        MapPolyline(coordinates: smoothedPilotPath)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Only show latest pilot position
                    if let latestPilot = pilotItems.last {
                        Annotation("Pilot", coordinate: latestPilot.coordinate) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.orange)
                                .background(Circle().fill(.white))
                        }
                    }
                }
                
                Group {
                    // Draw home trail if there's movement
                    let homeCoordinates = homeItems.map { $0.coordinate }
                    if homeCoordinates.count > 1 {
                        MapPolyline(coordinates: homeCoordinates)
                            .stroke(.yellow, lineWidth: 2)
                    }
                    
                    // Only show latest home position
                    if let latestHome = homeItems.last {
                        Annotation("Home", coordinate: latestHome.coordinate) {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.green)
                                .background(Circle().fill(.white))
                        }
                    }
                }
                
                Group {
                    ForEach(alertRings) { ring in
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .foregroundStyle(.red.opacity(0.1))
                            .stroke(.red, lineWidth: 2)
                    }
                }
            }
            .mapStyle(mapStyleForSelectedType())
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        
        private struct MapPointItem: Identifiable {
            let id = UUID()
            let title: String
            let coordinate: CLLocationCoordinate2D
            let systemImageName: String
            let tintColor: Color
        }
        
        private func buildPilotItems() -> [MapPointItem] {
            var items: [MapPointItem] = []
            var seenCoordinates = Set<String>()
            
            if let pilotLatStr = encounter.metadata["pilotLat"],
               let pilotLonStr = encounter.metadata["pilotLon"],
               let lat = Double(pilotLatStr), let lon = Double(pilotLonStr),
               lat != 0 || lon != 0 {
                let coordKey = "\(lat),\(lon)"
                if !seenCoordinates.contains(coordKey) {
                    items.append(MapPointItem(
                        title: "Latest Pilot",
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        systemImageName: "person.fill",
                        tintColor: .blue
                    ))
                    seenCoordinates.insert(coordKey)
                }
            }
            
            if let pilotHistory = encounter.metadata["pilotHistory"] {
                let entries = pilotHistory.components(separatedBy: ";")
                var historicalLocations: [(timestamp: TimeInterval, coordinate: CLLocationCoordinate2D)] = []
                
                for entry in entries {
                    let parts = entry.components(separatedBy: ":")
                    guard parts.count == 2 else { continue }
                    let coords = parts[1].components(separatedBy: ",")
                    guard coords.count >= 2,
                          let timestamp = Double(parts[0]),
                          let lat = Double(coords[0]),
                          let lon = Double(coords[1]),
                          lat != 0 || lon != 0 else { continue }
                    
                    let coordKey = "\(lat),\(lon)"
                    if !seenCoordinates.contains(coordKey) {
                        historicalLocations.append((timestamp, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                        seenCoordinates.insert(coordKey)
                    }
                }
                
                historicalLocations.sort { $0.timestamp < $1.timestamp }
                
                for (idx, location) in historicalLocations.enumerated() {
                    items.append(MapPointItem(
                        title: "Pilot \(idx + 1)",
                        coordinate: location.coordinate,
                        systemImageName: "person.circle",
                        tintColor: Color.orange.opacity(0.7)
                    ))
                }
            }
            
            return items
        }

        
        private func buildHomeItems() -> [MapPointItem] {
            var items: [MapPointItem] = []
            var seenCoordinates = Set<String>()
            
            if let latStr = encounter.metadata["homeLat"],
               let lonStr = encounter.metadata["homeLon"],
               let lat = Double(latStr), let lon = Double(lonStr),
               lat != 0 || lon != 0 {
                let coordKey = "\(lat),\(lon)"
                if !seenCoordinates.contains(coordKey) {
                    items.append(MapPointItem(
                        title: "Latest Home",
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        systemImageName: "house.fill",
                        tintColor: .green
                    ))
                    seenCoordinates.insert(coordKey)
                }
            }
            
            if let homeHistory = encounter.metadata["homeHistory"] {
                let entries = homeHistory.components(separatedBy: ";")
                var historicalLocations: [(timestamp: TimeInterval, coordinate: CLLocationCoordinate2D)] = []
                
                for entry in entries {
                    let parts = entry.components(separatedBy: ":")
                    guard parts.count == 2 else { continue }
                    let coords = parts[1].components(separatedBy: ",")
                    guard coords.count >= 2,
                          let timestamp = Double(parts[0]),
                          let lat = Double(coords[0]),
                          let lon = Double(coords[1]),
                          lat != 0 || lon != 0 else { continue }
                    
                    let coordKey = "\(lat),\(lon)"
                    if !seenCoordinates.contains(coordKey) {
                        historicalLocations.append((timestamp, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                        seenCoordinates.insert(coordKey)
                    }
                }
                
                historicalLocations.sort { $0.timestamp < $1.timestamp }
                
                for (idx, location) in historicalLocations.enumerated() {
                    items.append(MapPointItem(
                        title: "Home \(idx + 1)",
                        coordinate: location.coordinate,
                        systemImageName: "house.circle",
                        tintColor: Color.yellow.opacity(0.7)
                    ))
                }
            }
            
            return items
        }
        
        @MapContentBuilder
        private func drawTimeBasedSegments(_ points: [FlightPathPoint]) -> some MapContent {
            if points.count > 4 {
                let segmentSize = max(1, points.count / 4)
                
                let recentPoints = Array(points.suffix(segmentSize))
                if recentPoints.count > 1 {
                    // Smooth recent path segment
                    let smoothedRecent = FlightPathSmoother.smoothPath(recentPoints.map { $0.coordinate }, smoothness: 4)
                    MapPolyline(coordinates: smoothedRecent)
                        .stroke(.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                
                if points.count > segmentSize * 2 {
                    let startIndex = max(0, points.count - segmentSize * 2)
                    let endIndex = points.count - segmentSize
                    let middlePoints = Array(points[startIndex..<endIndex])
                    if middlePoints.count > 1 {
                        // Smooth middle path segment
                        let smoothedMiddle = FlightPathSmoother.smoothPath(middlePoints.map { $0.coordinate }, smoothness: 4)
                        MapPolyline(coordinates: smoothedMiddle)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        
        // MARK: Pilot annotations
        @MapContentBuilder
        private func pilotLocationAnnotations() -> some MapContent {
            let items = buildPilotItems()
            
            Group {
                ForEach(items) { item in
                    Annotation(item.title,
                               coordinate: item.coordinate) {
                        Image(systemName: item.systemImageName)
                            .foregroundStyle(item.tintColor)
                            .background(Circle().fill(.white))
                    }
                }
            }
        }
        
        // MARK: Home annotations
        @MapContentBuilder
        private func homeLocationAnnotations() -> some MapContent {
            let items = buildHomeItems()
            
            Group {
                ForEach(items) { item in
                    Annotation(item.title,
                               coordinate: item.coordinate) {
                        Image(systemName: item.systemImageName)
                            .foregroundStyle(item.tintColor)
                            .background(Circle().fill(.white))
                    }
                }
            }
        }
        
        
        private var rawMessagesSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("RAW MESSAGES")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                if let latestMessage = cotViewModel.parsedMessages.first(where: { $0.uid == encounter.id }),
                   let originalRaw = latestMessage.originalRawString {
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(originalRaw)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                    
                } else {
                    Text("No raw message data available")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.tertiarySystemBackground))
                        )
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }

        private func loadRelationshipData() {
            flightPoints = encounter.flightPoints
            signatures = encounter.signatures
            isFPVDetection = encounter.id.hasPrefix("fpv-") || encounter.metadata["isFPVDetection"] == "true"
            isDataLoaded = true
        }
        
        private func setupInitialMapPosition() {
            var allCoordinates: [CLLocationCoordinate2D] = []
            
            // Use loaded state data instead of direct relationship access
            let regularFlightPoints = flightPoints.filter { point in
                (point.latitude != 0 || point.longitude != 0) && !point.isProximityPoint
            }
            allCoordinates.append(contentsOf: regularFlightPoints.map { $0.coordinate })
            
            if let homeLatStr = encounter.metadata["homeLat"],
               let homeLonStr = encounter.metadata["homeLon"],
               let homeLat = Double(homeLatStr),
               let homeLon = Double(homeLonStr),
               homeLat != 0 || homeLon != 0 {
                allCoordinates.append(CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon))
            }
            
            if let pilotLatStr = encounter.metadata["pilotLat"],
               let pilotLonStr = encounter.metadata["pilotLon"],
               let pilotLat = Double(pilotLatStr),
               let pilotLon = Double(pilotLonStr),
               pilotLat != 0 || pilotLon != 0 {
                allCoordinates.append(CLLocationCoordinate2D(latitude: pilotLat, longitude: pilotLon))
            }
            
            if allCoordinates.count > 1 {
                let latitudes = allCoordinates.map { $0.latitude }
                let longitudes = allCoordinates.map { $0.longitude }
                
                let minLat = latitudes.min()!
                let maxLat = latitudes.max()!
                let minLon = longitudes.min()!
                let maxLon = longitudes.max()!
                
                let center = CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                )
                
                let latDelta = max((maxLat - minLat) * 1.2, 0.01)
                let lonDelta = max((maxLon - minLon) * 1.2, 0.01)
                
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                ))
            } else if let singleCoord = allCoordinates.first {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: singleCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            } else if let ring = cotViewModel.alertRings.first(where: { $0.droneId == encounter.id }) {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: ring.centerCoordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: max(ring.radius / 111000 * 1.5, 0.01),
                        longitudeDelta: max(ring.radius / 111000 * 1.5, 0.01)
                    )
                ))
            }
        }

        
        private func mapStyleForSelectedType() -> MapKit.MapStyle {
            switch selectedMapType {
            case .standard:
                return .standard
            case .satellite:
                return .imagery
            case .hybrid:
                return .hybrid
            }
        }
        
        private var encounterStats: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("ENCOUNTER STATS")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                StatsGrid {
                    StatItem(title: "Duration", value: formatDuration(encounter.totalFlightTime))
                    StatItem(title: "Max Alt", value: String(format: "%.1fm", encounter.cachedMaxAltitude))
                    StatItem(title: "Max Speed", value: String(format: "%.1fm/s", encounter.cachedMaxSpeed))
                    StatItem(title: "Avg RSSI", value: String(format: "%.1fdBm", encounter.cachedAverageRSSI))
                    StatItem(title: "Signatures", value: "\(encounter.cachedSignatureCount)")
                    
                    if encounter.id.hasPrefix("fpv-") || encounter.metadata["isFPVDetection"] == "true" {
                        let totalDetections = Int(encounter.metadata["totalDetections"] ?? "0") ?? 0
                        let proximityCount = totalDetections > 0 ? totalDetections : encounter.cachedFlightPointCount
                        StatItem(title: "Points", value: "\(proximityCount)")
                    } else {
                        StatItem(title: "Points", value: "\(encounter.cachedFlightPointCount)")
                    }
                    
                }
                Text("ENCOUNTER TIMELINE")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Detected")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text(formatDateTime(encounter.firstSeen))
                            .font(.appHeadline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Contact")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text(formatDateTime(encounter.lastSeen))
                            .font(.appHeadline)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
        }
        
        private func formatDateTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
        
        private var macSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                macSectionTitle
                macSectionContent
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
        
        private var macSectionTitle: some View {
            Text("MAC RANDOMIZATION")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        
        private var macSectionContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                macSectionHeader
                macAddressScrollView
            }
        }
        
        private var macSectionHeader: some View {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Device using MAC randomization")
                    .font(.appSubheadline)
                Spacer()
                Text("\(encounter.macAddresses.count) addresses")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
        }
        
        private var macAddressScrollView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(encounter.macAddresses).sorted(), id: \.self) { mac in
                        macAddressRow(mac)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        
        private func macAddressRow(_ mac: String) -> some View {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.yellow)
                Text(mac)
                    .font(.appCaption)
                
                // Don't access signatures relationship here - too slow
                // Just show the MAC without timestamp
                Spacer()
            }
        }
        
        
        
        private var flightDataSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("FLIGHT DATA")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // Only show charts if we have data cached
                if encounter.cachedFlightPointCount > 0 || encounter.cachedSignatureCount > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            Spacer()
                            
                            // Only show altitude chart if we have flight points
                            if encounter.cachedFlightPointCount > 0 {
                                FlightDataChart(
                                    title: "Altitude", 
                                    data: flightPoints.lazy.map { $0.altitude }.filter { $0 != 0 }
                                )
                            }
                            
                            // Only show speed/RSSI if we have signatures
                            if encounter.cachedSignatureCount > 0 {
                                FlightDataChart(
                                    title: "Speed", 
                                    data: signatures.lazy.map { $0.speed }.filter { $0 != 0 }
                                )
                                FlightDataChart(
                                    title: "RSSI", 
                                    data: signatures.lazy.map { $0.rssi }.filter { $0 != 0 }
                                )
                            }
                            
                            Spacer()
                        }
                    }
                } else {
                    Text("No flight data available for charts")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        
    }
    
    struct StatsGrid<Content: View>: View {
        let content: Content
        
        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        var body: some View {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                content
            }
        }
    }
    
    struct StatItem: View {
        let title: String
        let value: String
        
        var body: some View {
            VStack(spacing: 4) {
                Text(title)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.appHeadline)
            }
        }
    }
    
    struct FlightDataChart: View {
        let title: String
        let data: [Double]
        
        // Accept lazy sequences
        init<S: Sequence>(title: String, data: S) where S.Element == Double {
            self.title = title
            self.data = Array(data)
        }
        
        var body: some View {
            VStack {
                Text(title)
                    .font(.appCaption)
                
                if let dataMin = data.min(), let dataMax = data.max(), data.count > 1 {
                    VStack(spacing: 4) {
                        // Use fixed range for RSSI to show better differentiation
                        let (minValue, maxValue): (Double, Double) = {
                            if title == "RSSI" {
                                // Fixed range for RSSI: -100 dBm (weak) to -30 dBm (strong)
                                return (-100.0, -30.0)
                            } else {
                                // Auto-scale for other metrics
                                return (dataMin, dataMax)
                            }
                        }()
                        
                        HStack {
                            Text("Max: \(String(format: "%.1f", dataMax))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        GeometryReader { geometry in
                            Path { path in
                                let step = geometry.size.width / CGFloat(data.count - 1)
                                let difference = maxValue - minValue
                                let scale = difference != 0 ? geometry.size.height / CGFloat(difference) : 0
                                
                                // Clamp values to the visible range for RSSI
                                let clampedFirstValue = max(minValue, min(maxValue, data[0]))
                                path.move(to: CGPoint(
                                    x: 0,
                                    y: geometry.size.height - (clampedFirstValue - minValue) * scale
                                ))
                                
                                for i in 1..<data.count {
                                    let clampedValue = max(minValue, min(maxValue, data[i]))
                                    path.addLine(to: CGPoint(
                                        x: CGFloat(i) * step,
                                        y: geometry.size.height - (clampedValue - minValue) * scale
                                    ))
                                }
                            }
                            .stroke(.blue, lineWidth: 2)
                        }
                        
                        HStack {
                            Text("Min: \(String(format: "%.1f", dataMin))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                } else {
                    Text("Insufficient data")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 200, height: 120)
        }
    }
}

private func formatDuration(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = Int(time) % 3600 / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

extension StoredEncountersView.EncounterDetailView {
    private func generateKML(for encounter: StoredDroneEncounter) -> String {
        // Use loaded state data instead of direct relationship access
        let regularPoints = flightPoints.filter { !$0.isProximityPoint }
        
        var kmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <n>\(encounter.id) Flight Path</n>
            <Style id="flightPath">
              <LineStyle>
                <color>ff0000ff</color>
                <width>4</width>
              </LineStyle>
            </Style>
            <Style id="pilotLocation">
              <IconStyle>
                <color>ff00aaff</color>
                <scale>1.0</scale>
                <Icon>
                  <href>http://maps.google.com/mapfiles/kml/shapes/man.png</href>
                </Icon>
              </IconStyle>
            </Style>
            <Style id="takeoffLocation">
              <IconStyle>
                <color>ff00ff00</color>
                <scale>1.0</scale>
                <Icon>
                  <href>http://maps.google.com/mapfiles/kml/shapes/airports.png</href>
                </Icon>
              </IconStyle>
            </Style>
            <Placemark>
              <n>\(encounter.id) Track</n>
              <styleUrl>#flightPath</styleUrl>
              <LineString>
                <altitudeMode>absolute</altitudeMode>
                <coordinates>
                    \(regularPoints.map { point in
                        "\(point.longitude),\(point.latitude),\(point.altitude)"
                    }.joined(separator: "\n                "))
                </coordinates>
              </LineString>
            </Placemark>
        """
        
        // Add pilot location if available
        if let pilotLatStr = encounter.metadata["pilotLat"],
           let pilotLonStr = encounter.metadata["pilotLon"],
           let pilotLat = Double(pilotLatStr),
           let pilotLon = Double(pilotLonStr),
           pilotLat != 0 || pilotLon != 0 {
            kmlContent += """
            
            <Placemark>
              <name>Pilot Location</name>
              <styleUrl>#pilotLocation</styleUrl>
              <Point>
                <coordinates>\(pilotLon),\(pilotLat),0</coordinates>
              </Point>
            </Placemark>
            """
        }
        
        // Add takeoff location if available
        if let takeoffLatStr = encounter.metadata["homeLat"],
           let takeoffLonStr = encounter.metadata["homeLon"],
           let takeoffLat = Double(takeoffLatStr),
           let takeoffLon = Double(takeoffLonStr),
           takeoffLat != 0 || takeoffLon != 0 {
            kmlContent += """
            
            <Placemark>
              <name>Takeoff Location</name>
              <styleUrl>#takeoffLocation</styleUrl>
              <Point>
                <coordinates>\(takeoffLon),\(takeoffLat),0</coordinates>
              </Point>
            </Placemark>
            """
        }
        
        kmlContent += """
          </Document>
        </kml>
        """
        
        return kmlContent
    }
    
    func exportKML(from viewController: UIViewController? = nil) {
        // Generate KML content
        let kmlContent = generateKML(for: encounter)
        
        // Ensure KML stuff is valid
        guard let kmlData = kmlContent.data(using: .utf8) else {
            print("Failed to convert KML content to NSData.")
            return
        }
        
        // Stamp the filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "_")
        let filename = "\(encounter.id)_flightpath_\(timestamp).kml"
        
        // Create a temporary file URL to share it
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        // Write KML data to the file
        do {
            try kmlData.write(to: fileURL)
        } catch {
            print("Failed to write KML data to file: \(error)")
            return
        }
        
        // Create the activity item source for sharing
        let kmlDataItem = KMLDataItem(fileURL: fileURL, filename: filename)
        
        let activityVC = UIActivityViewController(
            activityItems: [kmlDataItem],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = window
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: window.bounds.midX,
                    y: window.bounds.midY,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }
            
            DispatchQueue.main.async {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
    
    // Workaround to prevent writing where we don't want to
    class KMLDataItem: NSObject, UIActivityItemSource {
        private let fileURL: URL
        private let filename: String
        
        init(fileURL: URL, filename: String) {
            self.fileURL = fileURL
            self.filename = filename
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return fileURL
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            return fileURL
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
            return "application/vnd.google-earth.kml+xml"
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            return filename
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, filenameForActivityType activityType: UIActivity.ActivityType?) -> String {
            return filename
        }
    }
    
}
