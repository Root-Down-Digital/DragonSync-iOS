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
                    ScrollViewReader { proxy in
                        List(cotViewModel.parsedMessages) { item in
                            MessageRow(message: item, cotViewModel: cotViewModel)
                        }
                        .listStyle(.inset)
                        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                            if !cotViewModel.parsedMessages.isEmpty {
                                // DEBUG CODE
//                                if let firstMessage = cotViewModel.parsedMessages.first {
//                                    let timeSince = Date().timeIntervalSince(firstMessage.lastUpdated)
//                                    //print("DEBUG: Message \(firstMessage.uid) - Last updated: \(timeSince)s ago - Active: \(firstMessage.isActive) - Color: \(firstMessage.statusColor)")
//                                }
                                cotViewModel.objectWillChange.send()
                            }
                        }
                        .onChange(of: cotViewModel.parsedMessages) { oldMessages, newMessages in
                            if oldMessages.count < newMessages.count {
                                // Get the newest message
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
                .navigationTitle("Detections")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: {
                                cotViewModel.parsedMessages.removeAll()
                                cotViewModel.droneSignatures.removeAll()
                                cotViewModel.macIdHistory.removeAll()
                                cotViewModel.macProcessing.removeAll()
                                cotViewModel.alertRings.removeAll()
                            }) {
                                Label("Clear All", systemImage: "trash")
                            }
                            
                            // Add option to clear just active tracking but keep history
                            Button(action: {
                                cotViewModel.parsedMessages.removeAll()
                                cotViewModel.droneSignatures.removeAll()
                                cotViewModel.alertRings.removeAll()
                            }) {
                                Label("Stop All Tracking", systemImage: "eye.slash")
                            }
                            
                            // Modified button - now shows confirmation
                            Button(role: .destructive, action: {
                                showDeleteAllConfirmation = true
                            }) {
                                Label("Delete All History", systemImage: "trash.fill")
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
                // Add the confirmation alert
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
                Label("Drones", systemImage: "airplane.circle")
            }
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
    }
    
    
}
