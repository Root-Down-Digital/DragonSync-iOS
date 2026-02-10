//
//  ContentView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//                                                                                                                                                                                                                                                    
import SwiftUI
import SwiftData
import Network
import UserNotifications
import CoreLocation
import MapKit
import Charts

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var statusViewModel: StatusViewModel
    @EnvironmentObject private var spectrumViewModel: SpectrumData.SpectrumViewModel
    @EnvironmentObject private var cotViewModel: CoTViewModel
    @StateObject private var droneStorage = DroneStorageManager.shared
    @StateObject private var settings = Settings.shared
    @State private var showAlert = false
    @State private var latestMessage: CoTViewModel.CoTMessage?
    @State private var selectedTab: Int
    @State private var showDeleteAllConfirmation = false
    @State private var detectionMode: DetectionMode = .drones
    @State private var showUnifiedMap = false
    @State private var showAdsbAutoDisabledAlert = false
    @State private var adsbDisabledReason = ""
    @State private var unreadDetectionCount = 0
    @State private var lastViewedDroneCount = 0
    @State private var lastViewedAircraftCount = 0
    
    @State private var dashboardPath = NavigationPath()
    @State private var detectionsPath = NavigationPath()
    @State private var statusPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    
    enum DetectionMode {
        case drones
        case aircraft
        case both
    }
    
    init() {
        self._selectedTab = State(initialValue: Settings.shared.isListening ? 0 : 3)
    }
    

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
            detectionsTab
            statusTab
            settingsTab
            historyTab
        }
        .onChange(of: settings.isListening) { oldValue, newValue in
            guard oldValue != newValue else { return }
            handleListeningChange()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            handleTabChange(from: oldValue, to: newValue)
            
            if oldValue == newValue {
                popToRoot(for: newValue)
            }
            
            // Clear unread count when detections tab is selected
            if newValue == 1 {
                clearUnreadDetections()
            }
        }
        .onChange(of: settings.connectionMode) {
            handleConnectionModeChange()
        }
        .onChange(of: cotViewModel.parsedMessages) { oldMessages, newMessages in
            updateDetectionMode()
            updateUnreadCount(oldDroneCount: oldMessages.count, newDroneCount: newMessages.count)
        }
        .onChange(of: cotViewModel.aircraftTracks) { oldTracks, newTracks in
            updateDetectionMode()
            updateUnreadCount(oldAircraftCount: oldTracks.count, newAircraftCount: newTracks.count)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ADSBAutoDisabled"))) { notification in
            if let reason = notification.userInfo?["reason"] as? String {
                adsbDisabledReason = reason
            } else {
                adsbDisabledReason = "Connection failed after multiple attempts"
            }
            showAdsbAutoDisabledAlert = true
        }
        .alert("ADS-B Automatically Disabled", isPresented: $showAdsbAutoDisabledAlert) {
            Button("Dismiss") {
                showAdsbAutoDisabledAlert = false
            }
            Button("Open ADS-B Settings") {
                showAdsbAutoDisabledAlert = false
                // Switch to settings tab and navigate to ADS-B settings
                selectedTab = 3
            }
        } message: {
            Text("ADS-B tracking has been automatically disabled because the connection to readsb failed repeatedly.\n\nPlease check that your readsb/dump1090 server is running and accessible, then re-enable ADS-B tracking in Settings.")
        }
        .onAppear {
            SwiftDataStorageManager.shared.modelContext = modelContext
            statusViewModel.modelContext = modelContext
            
            OpenSkyService.shared.configure(with: modelContext)
            
            SwiftDataStorageManager.shared.repairCachedStats()
            SwiftDataStorageManager.shared.backfillActivityLogsForAllEncounters()
            SwiftDataStorageManager.shared.cleanupInvalidFlightPoints()
            droneStorage.loadFromStorage()
            droneStorage.updateProximityPointsWithCorrectRadius()
            
            statusViewModel.loadADSBEncounters()
            
            updateDetectionMode()
            
            // Setup notification observers for background connection management
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("LightweightConnectionCheck"),
                object: nil,
                queue: .main
            ) { [weak cotViewModel] _ in
                guard let cotViewModel = cotViewModel else { return }
                MainActor.assumeIsolated {
                    cotViewModel.checkConnectionStatus()
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("BackgroundTaskExpiring"),
                object: nil,
                queue: .main
            ) { [weak cotViewModel] _ in
                guard let cotViewModel = cotViewModel else { return }
                MainActor.assumeIsolated {
                    cotViewModel.prepareForBackgroundExpiry()
                }
            }
        }
    }
    
    // MARK: - Tab Views
    
    private var dashboardTab: some View {
        NavigationStack(path: $dashboardPath) {
            DashboardView(
                statusViewModel: statusViewModel,
                cotViewModel: cotViewModel,
                spectrumViewModel: spectrumViewModel
            )
            .navigationTitle("Dashboard")
        }
        .tabItem {
            Label("Dashboard", systemImage: "gauge")
        }
        .tag(0)
    }
    
    private var detectionsTab: some View {
        NavigationStack(path: $detectionsPath) {
            VStack(spacing: 0) {
                // Main content area
                detectionContent
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(hasDrones && hasAircraft ? .inline : .large)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Detection mode picker - floating at top when both types present
                if hasDrones && hasAircraft {
                    detectionModePicker
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    mapButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    detectionsMenu
                }
            }
            .alert("New Message", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                newMessageAlertContent
            }
            .alert("Delete All History", isPresented: $showDeleteAllConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteAllHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all stored drone encounters and detection history. This action cannot be undone.")
            }
            .navigationDestination(isPresented: $showUnifiedMap) {
                unifiedMapDestination
            }
        }
        .tabItem {
            Label(tabLabel, systemImage: tabIcon)
        }
        .badge(unreadDetectionCount > 0 ? unreadDetectionCount : 0)
        .tag(1)
    }
    
    private var statusTab: some View {
        NavigationStack(path: $statusPath) {
            StatusListView(
                statusViewModel: statusViewModel,
                cotViewModel: cotViewModel
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { statusViewModel.statusMessages.removeAll() }) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .tabItem {
            Label("Status", systemImage: "server.rack")
        }
        .tag(2)
    }
    
    private var settingsTab: some View {
        NavigationStack(path: $settingsPath) {
            SettingsView(cotHandler: cotViewModel)
        }
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
        .tag(3)
    }
    
    private var historyTab: some View {
        NavigationStack(path: $historyPath) {
            StoredEncountersView(cotViewModel: cotViewModel)
        }
        .tabItem {
            Label("History", systemImage: "clock.arrow.circlepath")
        }
        .tag(4)
    }
    
    // MARK: - Detections Tab Components
    
    @ViewBuilder
    private var detectionModePicker: some View {
        Picker("Detection Type", selection: $detectionMode) {
            Text("Drones").tag(DetectionMode.drones)
            Text("Aircraft").tag(DetectionMode.aircraft)
            Text("Both").tag(DetectionMode.both)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }
    
    @ViewBuilder
    private var detectionContent: some View {
        switch detectionMode {
        case .drones:
            VStack(spacing: 0) {
                // Stats overview - NO SCROLLING NEEDED!
                if !cotViewModel.parsedMessages.isEmpty {
                    DetectionsStatsView(
                        cotViewModel: cotViewModel,
                        detectionMode: detectionMode
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    
                    Divider()
                }
                
                droneListContent
            }
        case .aircraft:
            VStack(spacing: 0) {
                // Stats overview - NO SCROLLING NEEDED!
                if !cotViewModel.aircraftTracks.isEmpty {
                    DetectionsStatsView(
                        cotViewModel: cotViewModel,
                        detectionMode: detectionMode
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    
                    Divider()
                }
                
                AircraftListView(cotViewModel: cotViewModel)
            }
        case .both:
            VStack(spacing: 0) {
                // Stats overview - NO SCROLLING NEEDED!
                if hasDrones || hasAircraft {
                    DetectionsStatsView(
                        cotViewModel: cotViewModel,
                        detectionMode: detectionMode
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    
                    Divider()
                }
                
                bothDetectionsList
            }
        }
    }
    
    private var bothDetectionsList: some View {
        List {
            if (hasDrones && cotViewModel.parsedMessages.count >= 2) || (hasAircraft && cotViewModel.aircraftTracks.count >= 2) || (hasDrones && hasAircraft) {
                Section {
                    unifiedMapView(showAircraft: true)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            
            if hasDrones {
                Section("Drones (\(cotViewModel.parsedMessages.count))") {
                    ForEach(cotViewModel.parsedMessages) { item in
                        NavigationLink {
                            DroneDetailView(
                                message: item,
                                flightPath: getValidFlightPath(for: item.uid),
                                cotViewModel: cotViewModel
                            )
                        } label: {
                            MessageRow(
                                message: item,
                                cotViewModel: cotViewModel,
                                isCompact: cotViewModel.parsedMessages.count >= 2 || hasAircraft
                            )
                            .id(item.uid) // Preserve view identity to prevent sheet dismissal on updates
                        }
                    }
                }
            }
            
            if hasAircraft {
                Section("Aircraft (\(cotViewModel.aircraftTracks.count))") {
                    ForEach(cotViewModel.aircraftTracks) { aircraft in
                        AircraftRow(aircraft: aircraft)
                    }
                }
            }
        }
    }
    
    private func getValidFlightPath(for uid: String) -> [CLLocationCoordinate2D] {
        // Check if this is an FPV detection - FPV should never have flight paths
        if let message = cotViewModel.parsedMessages.first(where: { $0.uid == uid }),
           message.isFPVDetection {
            return []
        }
        
        guard let encounter = DroneStorageManager.shared.encounters[uid] else {
            return []
        }
        return encounter.flightPath.map { point in
            CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
    }
    
    @ViewBuilder
    private var mapButton: some View {
        if hasDrones || hasAircraft {
            Button(action: {
                showUnifiedMap = true
            }) {
                Label("Map View", systemImage: "map")
            }
        }
    }
    
    private var detectionsMenu: some View {
        Menu {
            if detectionMode == .drones || detectionMode == .both {
                droneMenuItems
            }
            
            if detectionMode == .aircraft || detectionMode == .both {
                aircraftMenuItems
            }
            
            if detectionMode == .drones || detectionMode == .both {
                Divider()
                deleteHistoryButton
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    @ViewBuilder
    private var droneMenuItems: some View {
        Button(action: {
            clearDrones()
        }) {
            Label("Clear Drones", systemImage: "trash")
        }
        
        Button(action: {
            stopDroneTracking()
        }) {
            Label("Stop Drone Tracking", systemImage: "eye.slash")
        }
    }
    
    @ViewBuilder
    private var aircraftMenuItems: some View {
        Button(action: {
            cotViewModel.aircraftTracks.removeAll()
            
            // Update unread tracking
            lastViewedAircraftCount = 0
            if selectedTab == 1 {
                clearUnreadDetections()
            }
        }) {
            Label("Clear Aircraft", systemImage: "airplane")
        }
    }
    
    @ViewBuilder
    private var deleteHistoryButton: some View {
        Button(role: .destructive, action: {
            showDeleteAllConfirmation = true
        }) {
            Label("Delete All History", systemImage: "trash.fill")
        }
    }
    
    @ViewBuilder
    private var newMessageAlertContent: some View {
        if let message = latestMessage {
            Text("From: \(message.uid)\nType: \(message.type)\nLocation: \(message.lat), \(message.lon)")
        }
    }
    
    private var unifiedMapDestination: some View {
        LiveMapView(
            cotViewModel: cotViewModel,
            initialMessage: getInitialMessageForMap(),
            filterMode: convertToFilterMode(detectionMode)
        )
        .navigationTitle(mapNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func convertToFilterMode(_ mode: DetectionMode) -> LiveMapView.FilterMode {
        switch mode {
        case .drones:
            return .drones
        case .aircraft:
            return .aircraft
        case .both:
            return .both
        }
    }
    
    private var mapNavigationTitle: String {
        switch detectionMode {
        case .drones:
            return "Drones Map"
        case .aircraft:
            return "Aircraft Map"
        case .both:
            return "Unified Map"
        }
    }
    
    private func getInitialMessageForMap() -> CoTViewModel.CoTMessage {
        // Try to use the first drone if available
        if let firstDrone = cotViewModel.parsedMessages.first {
            return firstDrone
        }
        
        // Otherwise try to use the first aircraft's position
        if let firstAircraft = cotViewModel.aircraftTracks.first,
           let coord = firstAircraft.coordinate {
            return CoTViewModel.CoTMessage(
                uid: "aircraft-init",
                type: "a-f-A",
                lat: String(coord.latitude),
                lon: String(coord.longitude),
                homeLat: "0.0",
                homeLon: "0.0",
                speed: "0.0",
                vspeed: "0.0",
                alt: String(firstAircraft.altitude ?? 0),
                pilotLat: "0.0",
                pilotLon: "0.0",
                description: "Aircraft",
                selfIDText: "",
                uaType: .aeroplane,
                idType: "system",
                rawMessage: [:]
            )
        }
        
        // Fall back to dummy message
        return createDummyMessage()
    }
    
    // MARK: - Helper Properties
    
    private var hasDrones: Bool {
        !cotViewModel.parsedMessages.isEmpty
    }
    
    private var hasAircraft: Bool {
        !cotViewModel.aircraftTracks.isEmpty
    }
    
    private var navigationTitle: String {
        switch detectionMode {
        case .drones:
            return "Drones"
        case .aircraft:
            return "Aircraft"
        case .both:
            return "Detections"
        }
    }
    
    private var tabLabel: String {
        if hasAircraft && !hasDrones {
            return "Aircraft"
        } else if hasDrones && !hasAircraft {
            return "Drones"
        } else if hasAircraft && hasDrones {
            return "Detections"
        } else {
            return "Detections"
        }
    }
    
    private var tabIcon: String {
        if hasAircraft && !hasDrones {
            return "airplane"
        } else if hasDrones && !hasAircraft {
            return "airplane.circle"
        } else if hasAircraft && hasDrones {
            return "scope"
        } else {
            return "airplane.circle"
        }
    }
    
    private var detectionBadgeCount: Int {
        let droneCount = cotViewModel.parsedMessages.count
        let aircraftCount = cotViewModel.aircraftTracks.count
        let total = droneCount + aircraftCount
        return total > 0 ? total : 0
    }
    
    // MARK: - Subviews
    
    private var droneListContent: some View {
        Group {
            if cotViewModel.parsedMessages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
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
            } else {
                ScrollViewReader { proxy in
                    List {
                        if cotViewModel.parsedMessages.count >= 2 {
                            Section {
                                unifiedMapView(showAircraft: false)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            }
                        }
                        
                        Section {
                            ForEach(cotViewModel.parsedMessages) { item in
                                NavigationLink {
                                    DroneDetailView(
                                        message: item,
                                        flightPath: getValidFlightPath(for: item.uid),
                                        cotViewModel: cotViewModel
                                    )
                                } label: {
                                    MessageRow(
                                        message: item,
                                        cotViewModel: cotViewModel,
                                        isCompact: cotViewModel.parsedMessages.count >= 2
                                    )
                                    .id(item.uid) // Preserve view identity to prevent sheet dismissal on updates
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .onChange(of: cotViewModel.parsedMessages) { oldMessages, newMessages in
                        if oldMessages.count < newMessages.count {
                            if let latest = newMessages.last {
                                if !oldMessages.contains(where: { $0.id == latest.id }) {
                                    latestMessage = latest
                                    showAlert = false
                                    withAnimation {
                                        proxy.scrollTo(latest.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func unifiedMapView(showAircraft: Bool = true) -> some View {
        Button(action: {
            showUnifiedMap = true
        }) {
            LiveMapPreview(cotViewModel: cotViewModel, droneCount: cotViewModel.parsedMessages.count, showAircraft: showAircraft)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Methods
    
    /// Pop navigation stack to root when tab is tapped while already selected
    private func popToRoot(for tab: Int) {
        switch tab {
        case 0:
            dashboardPath = NavigationPath()
        case 1:
            detectionsPath = NavigationPath()
        case 2:
            statusPath = NavigationPath()
        case 3:
            settingsPath = NavigationPath()
        case 4:
            historyPath = NavigationPath()
        default:
            break
        }
    }
    
    private func handleListeningChange() {
        if settings.isListening {
            cotViewModel.startListening()
        } else {
            cotViewModel.stopListening()
        }
    }
    
    private func handleTabChange(from oldValue: Int, to newValue: Int) {
        if newValue != 3 { // Spectrum tab
            // Spectrum not implemented this branch
        } else if settings.isListening {
            // Spectrum not implemented this branch
        }
    }
    
    private func handleConnectionModeChange() {
        if settings.isListening {
            // Handle switch when enabled, for now just do not allow
        }
    }
    
    private func updateDetectionMode() {
        // Only update if mode actually needs to change
        let newMode: DetectionMode
        
        // Log current state for debugging
        let droneCount = cotViewModel.parsedMessages.count
        let aircraftCount = cotViewModel.aircraftTracks.count
        
        if hasAircraft && !hasDrones {
            newMode = .aircraft
            print("DEBUG: Switching to aircraft-only mode (\(aircraftCount) aircraft, \(droneCount) drones)")
        } else if hasDrones && !hasAircraft {
            newMode = .drones
            print("DEBUG: Switching to drones-only mode (\(droneCount) drones, \(aircraftCount) aircraft)")
        } else if hasAircraft && hasDrones {
            // Keep current mode if already set to a valid option
            if detectionMode == .both || detectionMode == .drones || detectionMode == .aircraft {
                return  // No change needed
            }
            newMode = .both
            print("DEBUG: Switching to both mode (\(droneCount) drones, \(aircraftCount) aircraft)")
        } else {
            print("DEBUG: No detections to track (\(droneCount) drones, \(aircraftCount) aircraft)")
            return  // Nothing to track, no change needed
        }
        
        // Only update if different
        if detectionMode != newMode {
            detectionMode = newMode
            print("DEBUG: Detection mode updated to \(newMode)")
        }
    }
    
    private func updateUnreadCount(oldDroneCount: Int? = nil, newDroneCount: Int? = nil, 
                                   oldAircraftCount: Int? = nil, newAircraftCount: Int? = nil) {
        // Only update if we're not currently viewing the detections tab
        guard selectedTab != 1 else { return }
        
        let currentDroneCount = newDroneCount ?? cotViewModel.parsedMessages.count
        let currentAircraftCount = newAircraftCount ?? cotViewModel.aircraftTracks.count
        
        // Calculate new detections since last view
        let newDrones = max(0, currentDroneCount - lastViewedDroneCount)
        let newAircraft = max(0, currentAircraftCount - lastViewedAircraftCount)
        
        unreadDetectionCount = newDrones + newAircraft
    }
    
    private func clearUnreadDetections() {
        unreadDetectionCount = 0
        lastViewedDroneCount = cotViewModel.parsedMessages.count
        lastViewedAircraftCount = cotViewModel.aircraftTracks.count
    }
    
    private func clearDrones() {
        cotViewModel.parsedMessages.removeAll()
        cotViewModel.droneSignatures.removeAll()
        cotViewModel.macIdHistory.removeAll()
        cotViewModel.macProcessing.removeAll()
        cotViewModel.alertRings.removeAll()
        
        // Update unread tracking
        lastViewedDroneCount = 0
        if selectedTab == 1 {
            clearUnreadDetections()
        }
    }
    
    private func stopDroneTracking() {
        cotViewModel.parsedMessages.removeAll()
        cotViewModel.droneSignatures.removeAll()
        cotViewModel.alertRings.removeAll()
        
        // Update unread tracking
        lastViewedDroneCount = 0
        if selectedTab == 1 {
            clearUnreadDetections()
        }
    }
    
    private func deleteAllHistory() {
        droneStorage.deleteAllEncounters()
        cotViewModel.parsedMessages.removeAll()
        cotViewModel.droneSignatures.removeAll()
        cotViewModel.macIdHistory.removeAll()
        cotViewModel.macProcessing.removeAll()
        cotViewModel.alertRings.removeAll()
        
        // Update unread tracking
        lastViewedDroneCount = 0
        if selectedTab == 1 {
            clearUnreadDetections()
        }
    }
    
    private func createDummyMessage() -> CoTViewModel.CoTMessage {
        CoTViewModel.CoTMessage(
            uid: "map-init",
            type: "a-f-A",
            lat: "0.0",
            lon: "0.0",
            homeLat: "0.0",
            homeLon: "0.0",
            speed: "0.0",
            vspeed: "0.0",
            alt: "0.0",
            pilotLat: "0.0",
            pilotLon: "0.0",
            description: "Map",
            selfIDText: "",
            uaType: .helicopter,
            idType: "system",
            rawMessage: [:]
        )
    }
    
    // MARK: - Stats Headers
    
    private var droneStatsHeader: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "airplane.circle",
                value: "\(cotViewModel.parsedMessages.count)",
                label: "Drones"
            )
            
            StatBadge(
                icon: "antenna.radiowaves.left.and.right",
                value: "\(activeDroneCount)",
                label: "Active"
            )
            
            if let maxAlt = highestDrone {
                StatBadge(
                    icon: "arrow.up.circle.fill",
                    value: "\(maxAlt)",
                    label: "Max Alt (m)"
                )
            }
            
            if let maxSpeed = fastestDrone {
                StatBadge(
                    icon: "speedometer",
                    value: String(format: "%.1f", maxSpeed),
                    label: "Max Speed (m/s)"
                )
            }
        }
    }
    
    private var combinedStatsHeader: some View {
        HStack(spacing: 12) {
            if hasDrones {
                StatBadge(
                    icon: "airplane.circle",
                    value: "\(cotViewModel.parsedMessages.count)",
                    label: "Drones"
                )
            }
            
            if hasAircraft {
                StatBadge(
                    icon: "airplane",
                    value: "\(cotViewModel.aircraftTracks.count)",
                    label: "Aircraft"
                )
            }
            
            if hasDrones {
                StatBadge(
                    icon: "antenna.radiowaves.left.and.right",
                    value: "\(activeDroneCount)",
                    label: "Active"
                )
            }
            
            if hasAircraft {
                StatBadge(
                    icon: "antenna.radiowaves.left.and.right",
                    value: "\(activeAircraftCount)",
                    label: "Active"
                )
            }
        }
    }
    
    // MARK: - Stats Computed Properties
    
    private var activeDroneCount: Int {
        // Count drones that have recent updates (not stale)
        // You can adjust this logic based on your DroneEncounter structure
        cotViewModel.parsedMessages.filter { message in
            guard let encounter = DroneStorageManager.shared.encounters[message.uid] else {
                return true // If no encounter, assume active (just detected)
            }
            // Consider active if last seen within 30 seconds
            return Date().timeIntervalSince(encounter.lastSeen) < 30
        }.count
    }
    
    private var activeAircraftCount: Int {
        cotViewModel.aircraftTracks.filter { !$0.isStale }.count
    }
    
    private var highestDrone: Int? {
        cotViewModel.parsedMessages.compactMap { message in
            if let alt = Double(message.alt) {
                return Int(alt)
            }
            return nil
        }.max()
    }
    
    private var fastestDrone: Double? {
        cotViewModel.parsedMessages.compactMap { message in
            Double(message.speed)
        }.max()
    }
    
}

private struct LiveMapPreview: View {
    @ObservedObject var cotViewModel: CoTViewModel
    let droneCount: Int
    let showAircraft: Bool // New parameter to control whether to show aircraft
    
    init(cotViewModel: CoTViewModel, droneCount: Int, showAircraft: Bool = true) {
        self.cotViewModel = cotViewModel
        self.droneCount = droneCount
        self.showAircraft = showAircraft
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Map(bounds: MapCameraBounds(centerCoordinateBounds: mapRegion)) {
                // Drone flight paths
                ForEach(cotViewModel.parsedMessages) { message in
                    if !message.isFPVDetection {
                        let flightPath = getDroneFlightPath(for: message.uid)
                        if flightPath.count > 1 {
                            MapPolyline(coordinates: flightPath)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                
                // Aircraft flight paths - only if showAircraft is true
                if showAircraft {
                    ForEach(cotViewModel.aircraftTracks) { aircraft in
                        let flightPath = getAircraftFlightPath(for: aircraft)
                        if flightPath.count > 1 {
                            MapPolyline(coordinates: flightPath)
                                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                
                // FPV Alert Rings
                ForEach(cotViewModel.alertRings) { ring in
                    if !(ring.centerCoordinate.latitude == 0 && ring.centerCoordinate.longitude == 0) {
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .foregroundStyle(.orange.opacity(0.1))
                            .stroke(.orange, lineWidth: 2)
                        
                        Annotation("Monitor", coordinate: ring.centerCoordinate) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(.orange)
                                .font(.title2)
                                .background(Circle().fill(.white).frame(width: 24, height: 24))
                        }
                    }
                }
                
                // Drone markers
                ForEach(cotViewModel.parsedMessages) { message in
                    if let coordinate = message.coordinate,
                       !message.isFPVDetection,
                       !(coordinate.latitude == 0 && coordinate.longitude == 0) {
                        Annotation(message.id, coordinate: coordinate) {
                            droneAnnotationIcon(for: message)
                        }
                    }
                }
                
                // Aircraft markers - only if showAircraft is true
                if showAircraft {
                    ForEach(cotViewModel.aircraftTracks) { aircraft in
                        if let coordinate = aircraft.coordinate {
                            Annotation(aircraft.callsign, coordinate: coordinate) {
                                aircraftAnnotationIcon(for: aircraft)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text("\(cotViewModel.parsedMessages.count)")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    
                    if showAircraft && cotViewModel.aircraftTracks.count > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "airplane")
                                .foregroundStyle(.cyan)
                                .font(.caption)
                            Text("\(cotViewModel.aircraftTracks.count)")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Image(systemName: "map")
                        .font(.caption)
                    Text("Tap to view full map")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
    }
    
    private func getDroneFlightPath(for uid: String) -> [CLLocationCoordinate2D] {
        // Check if this is an FPV detection - FPV should never have flight paths
        if let currentMessage = cotViewModel.parsedMessages.first(where: { $0.uid == uid }),
           currentMessage.isFPVDetection {
            return []
        }
        
        // Get flight path from DroneStorageManager
        guard let encounter = DroneStorageManager.shared.encounters[uid] else {
            return []
        }
        
        var coordinates = encounter.flightPath.map { $0.coordinate }
        
        // Ensure path ends at current position if we have one
        if let currentMessage = cotViewModel.parsedMessages.first(where: { $0.uid == uid }),
           let currentCoord = currentMessage.coordinate,
           currentCoord.latitude != 0 && currentCoord.longitude != 0 {
            
            if coordinates.isEmpty {
                coordinates = [currentCoord]
            } else {
                // Replace last coordinate with current for seamless alignment
                coordinates[coordinates.count - 1] = currentCoord
            }
        }
        
        return coordinates
    }
    
    private func getAircraftFlightPath(for aircraft: Aircraft) -> [CLLocationCoordinate2D] {
        var coordinates = aircraft.positionHistory.map { $0.coordinate }
        
        // Ensure path ends at current position for seamless alignment
        if let currentCoord = aircraft.coordinate {
            if coordinates.isEmpty {
                coordinates = [currentCoord]
            } else {
                // Replace last coordinate with current to ensure perfect alignment
                coordinates[coordinates.count - 1] = currentCoord
            }
        }
        
        return coordinates
    }
    
    private func droneAnnotationIcon(for message: CoTViewModel.CoTMessage) -> some View {
        let rotation = message.headingDeg - 90
        
        return Image(systemName: "airplane.circle.fill")
            .foregroundStyle(.blue)
            .font(.title3)
            .rotationEffect(.degrees(rotation))
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
            )
    }
    
    private func aircraftAnnotationIcon(for aircraft: Aircraft) -> some View {
        let rotation = Double(aircraft.track ?? 0) - 90
        
        return Image(systemName: "airplane")
            .foregroundStyle(.cyan)
            .font(.title3)
            .rotationEffect(.degrees(rotation))
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
            )
    }
    
    private var mapRegion: MKCoordinateRegion {
        var allCoords: [CLLocationCoordinate2D] = []
        
        // Always add drone coordinates (excluding FPV and 0/0)
        allCoords += cotViewModel.parsedMessages.compactMap { message -> CLLocationCoordinate2D? in
            // For FPV detections, try to use alert ring center instead of drone coordinate
            if message.isFPVDetection {
                if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }),
                   !(ring.centerCoordinate.latitude == 0 && ring.centerCoordinate.longitude == 0) {
                    return ring.centerCoordinate
                }
                return nil
            }
            
            guard let coord = message.coordinate else { return nil }
            
            if coord.latitude == 0 && coord.longitude == 0 {
                return nil
            }
            return coord
        }
        
        // Only add aircraft coordinates if showAircraft is true
        if showAircraft {
            allCoords += cotViewModel.aircraftTracks.compactMap { $0.coordinate }
        }
        
        guard !allCoords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
        if allCoords.count == 1 {
            return MKCoordinateRegion(
                center: allCoords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
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
        
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(value)
                    .font(.headline)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

