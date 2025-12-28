//
//  ContentView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import Network
import UserNotifications

struct ContentView: View {
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
        
        
        // Add lightweight connection check listener
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LightweightConnectionCheck"),
            object: nil,
            queue: .main
        ) { [weak cotVM] _ in
            cotVM?.checkConnectionStatus()
        }
        
        // Add notification for background task expiry
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BackgroundTaskExpiring"),
            object: nil,
            queue: .main
        ) { [weak cotVM] _ in
            // Perform urgent cleanup when background task is about to expire
            cotVM?.prepareForBackgroundExpiry()
        }
    }
    

    var body: some View {
        TabView(selection: $selectedTab) {
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
            
            NavigationStack {
                VStack {
                    // Mode picker when both drones and aircraft are available
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
                    
                    // Dynamic content based on mode
                    switch detectionMode {
                    case .drones:
                        droneListContent
                    case .aircraft:
                        AircraftListView(cotViewModel: cotViewModel)
                    case .both:
                        // Show both in sections or tabs
                        List {
                            if hasDrones {
                                Section("Drones (\(cotViewModel.parsedMessages.count))") {
                                    ForEach(cotViewModel.parsedMessages) { item in
                                        MessageRow(message: item, cotViewModel: cotViewModel)
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
                }
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if detectionMode == .drones || detectionMode == .both {
                                Button(action: {
                                    cotViewModel.parsedMessages.removeAll()
                                    cotViewModel.droneSignatures.removeAll()
                                    cotViewModel.macIdHistory.removeAll()
                                    cotViewModel.macProcessing.removeAll()
                                    cotViewModel.alertRings.removeAll()
                                }) {
                                    Label("Clear Drones", systemImage: "trash")
                                }
                                
                                Button(action: {
                                    cotViewModel.parsedMessages.removeAll()
                                    cotViewModel.droneSignatures.removeAll()
                                    cotViewModel.alertRings.removeAll()
                                }) {
                                    Label("Stop Drone Tracking", systemImage: "eye.slash")
                                }
                            }
                            
                            if detectionMode == .aircraft || detectionMode == .both {
                                Button(action: {
                                    cotViewModel.aircraftTracks.removeAll()
                                }) {
                                    Label("Clear Aircraft", systemImage: "airplane")
                                }
                            }
                            
                            if detectionMode == .drones || detectionMode == .both {
                                Divider()
                                
                                Button(role: .destructive, action: {
                                    showDeleteAllConfirmation = true
                                }) {
                                    Label("Delete All History", systemImage: "trash.fill")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .alert("New Message", isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let message = latestMessage {
                        Text("From: \(message.uid)\nType: \(message.type)\nLocation: \(message.lat), \(message.lon)")
                    }
                }
                .alert("Delete All History", isPresented: $showDeleteAllConfirmation) {
                    Button("Delete", role: .destructive) {
                        droneStorage.deleteAllEncounters()
                        cotViewModel.parsedMessages.removeAll()
                        cotViewModel.droneSignatures.removeAll()
                        cotViewModel.macIdHistory.removeAll()
                        cotViewModel.macProcessing.removeAll()
                        cotViewModel.alertRings.removeAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all stored drone encounters and detection history. This action cannot be undone.")
                }
            }
            .tabItem {
                Label(tabLabel, systemImage: tabIcon)
            }
            .badge(detectionBadgeCount)
            .tag(1)
            
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
            
            NavigationStack {
                SettingsView(cotHandler: cotViewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
            NavigationStack {
                StoredEncountersView(cotViewModel: cotViewModel)
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(4)
            // Spectrum not implemented this branch
//            NavigationStack {
//                SpectrumView(viewModel: spectrumViewModel)
//                    .navigationTitle("Spectrum")
//            }
//            .tabItem {
//                Label("Spectrum", systemImage: "waveform")
//            }
//            .tag(4)
        }
        
        .onChange(of: settings.isListening) {
            if settings.isListening {
                cotViewModel.startListening()
            } else {
                cotViewModel.stopListening()
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue != 3 { // Spectrum tab
                // Spectrum not implemented this branch
            } else if settings.isListening {
                // Spectrum not implemented this branch
            }
        }
        .onChange(of: settings.connectionMode) {
            if settings.isListening {
                // Handle switch when enabled, for now just do not allow
            }
        }
        .onChange(of: cotViewModel.parsedMessages) { oldMessages, newMessages in
            updateDetectionMode()
        }
        .onChange(of: cotViewModel.aircraftTracks) { oldTracks, newTracks in
            updateDetectionMode()
        }
        .onAppear {
            updateDetectionMode()
        }
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
                MessageRow(message: item, cotViewModel: cotViewModel)
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
    
    
}
