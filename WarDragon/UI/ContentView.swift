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

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var statusViewModel = StatusViewModel()
    @StateObject private var spectrumViewModel = SpectrumData.SpectrumViewModel()
    @StateObject private var droneStorage = DroneStorageManager.shared
    @StateObject private var cotViewModel: CoTViewModel
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
    
    enum DetectionMode {
        case drones
        case aircraft
        case both
    }
    
    init() {
        // Create temporary non-StateObject instances for initialization
        let statusVM = StatusViewModel()
        let cotVM = CoTViewModel(statusViewModel: statusVM)
        
        // Initialize the StateObject properties
        self._statusViewModel = StateObject(wrappedValue: statusVM)
        self._cotViewModel = StateObject(wrappedValue: cotVM)
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
        .onChange(of: settings.isListening) {
            handleListeningChange()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            handleTabChange(from: oldValue, to: newValue)
            
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
            // Inject ModelContext into storage managers
            SwiftDataStorageManager.shared.modelContext = modelContext
            statusViewModel.modelContext = modelContext
            
            // Reload encounters from SwiftData now that ModelContext is set
            // This is important because DroneStorageManager.init() runs before
            // ModelContext is available, so we load here instead
            droneStorage.loadFromStorage()
            droneStorage.updateProximityPointsWithCorrectRadius()
            
            // Load data from SwiftData
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
        NavigationStack {
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
        NavigationStack {
            VStack {
                detectionModePicker
                detectionContent
            }
            .navigationTitle(navigationTitle)
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
            .sheet(isPresented: $showUnifiedMap) {
                unifiedMapSheet
            }
        }
        .tabItem {
            Label(tabLabel, systemImage: tabIcon)
        }
        .badge(unreadDetectionCount > 0 ? unreadDetectionCount : 0)
        .tag(1)
    }
    
    private var statusTab: some View {
        NavigationStack {
            StatusListView(statusViewModel: statusViewModel)
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
        NavigationStack {
            SettingsView(cotHandler: cotViewModel)
        }
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
        .tag(3)
    }
    
    private var historyTab: some View {
        NavigationStack {
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
        if hasDrones && hasAircraft {
            Picker("Detection Type", selection: $detectionMode) {
                Text("Drones").tag(DetectionMode.drones)
                Text("Aircraft").tag(DetectionMode.aircraft)
                Text("Both").tag(DetectionMode.both)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var detectionContent: some View {
        switch detectionMode {
        case .drones:
            droneListContent
        case .aircraft:
            AircraftListView(cotViewModel: cotViewModel)
        case .both:
            bothDetectionsList
        }
    }
    
    private var bothDetectionsList: some View {
        List {
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
                            MessageRow(message: item, cotViewModel: cotViewModel)
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
    
    private var unifiedMapSheet: some View {
        NavigationStack {
            LiveMapView(
                cotViewModel: cotViewModel,
                initialMessage: getInitialMessageForMap(),
                filterMode: convertToFilterMode(detectionMode)
            )
            .navigationTitle(mapNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showUnifiedMap = false
                    }
                }
            }
        }
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
        ScrollViewReader { proxy in
            List(cotViewModel.parsedMessages) { item in
                NavigationLink {
                    DroneDetailView(
                        message: item,
                        flightPath: getValidFlightPath(for: item.uid),
                        cotViewModel: cotViewModel
                    )
                } label: {
                    MessageRow(message: item, cotViewModel: cotViewModel)
                }
            }
            .listStyle(.inset)
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                if !cotViewModel.parsedMessages.isEmpty {
                    cotViewModel.objectWillChange.send()
                }
            }
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
    
    // MARK: - Helper Methods
    
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
        // Auto-switch mode based on what's being tracked
        if hasAircraft && !hasDrones {
            detectionMode = .aircraft
        } else if hasDrones && !hasAircraft {
            detectionMode = .drones
        } else if hasAircraft && hasDrones {
            // Keep current mode, but default to both if not set
            if detectionMode != .both && detectionMode != .drones && detectionMode != .aircraft {
                detectionMode = .both
            }
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
    
    
}
