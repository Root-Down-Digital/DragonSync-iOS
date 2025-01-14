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
    @StateObject private var cotViewModel: CoTViewModel
    @StateObject private var settings = Settings.shared
    @State private var showAlert = false
    @State private var latestMessage: CoTViewModel.CoTMessage?
    @State private var selectedTab: Int
    
    
    init() {
        let statusVM = StatusViewModel()
        _statusViewModel = StateObject(wrappedValue: statusVM)
        _cotViewModel = StateObject(wrappedValue: CoTViewModel(statusViewModel: statusVM))
        _selectedTab = State(initialValue: Settings.shared.isListening ? 0 : 2)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VStack {
                    ScrollViewReader { proxy in
                        List(cotViewModel.parsedMessages) { item in
                            MessageRow(message: item, cotViewModel: cotViewModel)
                        }
                        .listStyle(.inset)
                        .onChange(of: cotViewModel.parsedMessages) { oldMessages, newMessages in
                            // Find the last message
                            if let changedMessage = newMessages.last(where: { newMsg in
                                oldMessages.first(where: { $0.id == newMsg.id && $0 != newMsg }) != nil
                            }) {
                                latestMessage = changedMessage
                                showAlert = false
                                withAnimation {
                                    proxy.scrollTo(changedMessage.id, anchor: .bottom)
                                }
                            }
                            // Scroll to new one
                            else if let latest = newMessages.last, oldMessages.count != newMessages.count {
                                latestMessage = latest
                                showAlert = false
                                withAnimation {
                                    proxy.scrollTo(latest.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("DragonSync")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            cotViewModel.parsedMessages.removeAll()  // Remove UI messages
                            cotViewModel.droneSignatures.removeAll() // Ditch old signatures BUGFIX #112
                        }) {
                            Image(systemName: "trash")
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
            }
            
            .tabItem {
                Label("Drones", systemImage: "airplane.circle")
            }
            .tag(0)
            
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
            .tag(1)
            
            NavigationStack {
                SettingsView(cotHandler: cotViewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
            
//            NavigationStack {
//                SpectrumView(viewModel: spectrumViewModel)
//                    .navigationTitle("Spectrum")
//            }
//            .tabItem {
//                Label("Spectrum", systemImage: "waveform")
//            }
//            .tag(3)
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
                spectrumViewModel.stopListening()
            } else if settings.isListening {
                let port = UInt16(UserDefaults.standard.integer(forKey: "spectrumPort"))
                spectrumViewModel.startListening(port: port)
            }
        }
        .onChange(of: settings.connectionMode) {
            if settings.isListening {
                // Handle switch when enabled, for now just do not allow
            }
        }
    }
}
