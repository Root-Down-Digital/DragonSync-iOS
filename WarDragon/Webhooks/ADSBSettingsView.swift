//
//  ADSBSettingsView.swift
//  WarDragon
//
//  ADS-B/readsb configuration UI
//

import SwiftUI

struct ADSBSettingsView: View {
    @StateObject private var settings = Settings.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var aircraftCount: Int = 0
    @State private var showAutoDisabledAlert = false
    @State private var autoDisabledReason = ""
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable ADS-B Tracking", isOn: $settings.adsbEnabled)
            } header: {
                Label("ADS-B Aircraft Tracking", systemImage: "airplane")
            } footer: {
                Text("Track aircraft via ADS-B using readsb HTTP API")
            }
            
            if settings.adsbEnabled {
                Section("Readsb Configuration") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Base URL", text: $settings.adsbReadsbURL, prompt: Text("192.168.1.100:8080"))
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        
                        Text("Server address without path (http:// optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Data Path", text: $settings.adsbDataPath, prompt: Text("/data/aircraft.json"))
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        
                        if !settings.adsbDataPath.hasSuffix(".json") {
                            Text("⚠️ Path must end with .json")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Endpoint path (must end with .json)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Poll Interval")
                            Spacer()
                            Text("\(settings.adsbPollInterval, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.adsbPollInterval, in: 0.5...10, step: 0.5)
                    }
                    
                    if let fullURL = settings.adsbConfiguration.aircraftDataURL {
                        Text("Full URL: \(fullURL.absoluteString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Invalid URL configuration")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Section("Filters") {
                    Toggle("Filter by Distance", isOn: .init(
                        get: { settings.adsbMaxDistance > 0 },
                        set: { enabled in
                            settings.adsbMaxDistance = enabled ? 50 : 0
                            if enabled {
                                requestLocationIfNeeded()
                            }
                        }
                    ))
                    
                    if settings.adsbMaxDistance > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: locationStatusIcon)
                                    .foregroundColor(locationStatusColor)
                                Text(locationStatusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if locationManager.locationPermissionStatus == .notDetermined {
                                    Spacer()
                                    Button("Enable Location") {
                                        requestLocationIfNeeded()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Distance")
                                Spacer()
                                Text("\(Int(settings.adsbMaxDistance)) km")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.adsbMaxDistance, in: 10...500, step: 10)
                        }
                        
                        if locationManager.userLocation != nil {
                            Text("Distance filtering active")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if locationManager.locationPermissionStatus == .authorizedWhenInUse || locationManager.locationPermissionStatus == .authorizedAlways {
                            Text("Waiting for location...")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Aircraft to Display")
                            Spacer()
                            Text("\(settings.adsbMaxAircraftCount)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: .init(
                            get: { Double(settings.adsbMaxAircraftCount) },
                            set: { settings.adsbMaxAircraftCount = Int($0) }
                        ), in: 10...200, step: 5)
                        
                        Text("Shows the \(settings.adsbMaxAircraftCount) closest aircraft")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Filter by Altitude", isOn: .init(
                        get: { settings.adsbMinAltitude > 0 || settings.adsbMaxAltitude < 50000 },
                        set: { enabled in
                            if enabled {
                                settings.adsbMinAltitude = 1000
                                settings.adsbMaxAltitude = 40000
                            } else {
                                settings.adsbMinAltitude = 0
                                settings.adsbMaxAltitude = 50000
                            }
                        }
                    ))
                    
                    if settings.adsbMinAltitude > 0 || settings.adsbMaxAltitude < 50000 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Min Altitude")
                                Spacer()
                                Text("\(Int(settings.adsbMinAltitude)) ft")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.adsbMinAltitude, in: 0...10000, step: 500)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Altitude")
                                Spacer()
                                Text("\(Int(settings.adsbMaxAltitude)) ft")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.adsbMaxAltitude, in: 10000...50000, step: 1000)
                        }
                    }
                }
                
                Section("Connection Test") {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "airplane.circle")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(!settings.adsbConfiguration.isValid || isTesting)
                    
                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                            
                            if aircraftCount > 0 {
                                Text("Found \(aircraftCount) aircraft with position data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Common Endpoints", systemImage: "list.bullet")
                            .font(.headline)
                        
                        Group {
                            Text("Standard readsb/dump1090:")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("  /data/aircraft.json")
                                .font(.caption)
                                .fontDesign(.monospaced)
                            
                            Text("Tar1090:")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("  /data/aircraft.json")
                                .font(.caption)
                                .fontDesign(.monospaced)
                            
                            Text("Custom JSON endpoints:")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("  /api/v1/aircraft.json")
                                .font(.caption)
                                .fontDesign(.monospaced)
                            Text("  /adsb/live.json")
                                .font(.caption)
                                .fontDesign(.monospaced)
                            Text("  /custom/path/data.json")
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Endpoint Examples")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quick Setup", systemImage: "lightbulb")
                            .font(.headline)
                        
                        Text("1. Install readsb on your Raspberry Pi or server:")
                            .font(.caption)
                        Text("   sudo apt install readsb")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("2. Configure readsb to listen on network:")
                            .font(.caption)
                        Text("   Edit /etc/default/readsb")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("3. Enter base URL and data path above:")
                            .font(.caption)
                        Text("   Base: your-pi-ip:8080")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        Text("   Path: /data/aircraft.json")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("4. Test connection and adjust poll interval")
                            .font(.caption)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Compatible with:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("• readsb - /data/aircraft.json")
                            .font(.caption)
                        Text("• dump1090 - /data/aircraft.json")
                            .font(.caption)
                        Text("• tar1090 - /data/aircraft.json")
                            .font(.caption)
                        Text("• Custom endpoints (must end with .json)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Setup Guide")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aircraft data from readsb will:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("• Appear on the map alongside drones")
                            .font(.caption)
                        Text("• Be published to MQTT if enabled")
                            .font(.caption)
                        Text("• Be sent to TAK server if enabled")
                            .font(.caption)
                        Text("• Use distinct aircraft icon")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Integration")
                }
            }
        }
        .navigationTitle("ADS-B Tracking")
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ADSBAutoDisabled"))) { notification in
            if let reason = notification.userInfo?["reason"] as? String {
                autoDisabledReason = reason
            } else {
                autoDisabledReason = "Connection failed after multiple attempts"
            }
            showAutoDisabledAlert = true
        }
        .alert("ADS-B Automatically Disabled", isPresented: $showAutoDisabledAlert) {
            Button("OK") {
                showAutoDisabledAlert = false
            }
            Button("Open Settings") {
                showAutoDisabledAlert = false
                // Settings is already open, just acknowledge
            }
        } message: {
            Text("ADS-B tracking has been disabled because the connection to readsb failed after multiple attempts.\n\nReason: \(autoDisabledReason)\n\nPlease check that your readsb server is running and accessible, then re-enable ADS-B tracking.")
        }
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        aircraftCount = 0
        
        Task {
            let config = settings.adsbConfiguration
            let client = ADSBClient(configuration: config)
            
            await client.poll()
            
            let state = client.state
            let count = client.aircraft.count
            
            await MainActor.run {
                switch state {
                case .connected:
                    testResult = "✓ Test completed"
                    aircraftCount = count
                case .connecting:
                    testResult = "⏳ Connecting..."
                case .failed(let error):
                    testResult = "✗ Connection failed: \(error.localizedDescription)"
                case .disconnected:
                    testResult = "✗ Disconnected"
                }
                isTesting = false
            }
        }
    }
    
    // MARK: - Location Helpers
    
    private func requestLocationIfNeeded() {
        switch locationManager.locationPermissionStatus {
        case .notDetermined:
            locationManager.requestLocationPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startLocationUpdates()
        default:
            break
        }
    }
    
    private var locationStatusIcon: String {
        switch locationManager.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.userLocation != nil ? "location.fill" : "location"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location"
        @unknown default:
            return "location"
        }
    }
    
    private var locationStatusColor: Color {
        switch locationManager.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.userLocation != nil ? .green : .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .gray
        @unknown default:
            return .gray
        }
    }
    
    private var locationStatusText: String {
        switch locationManager.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let location = locationManager.userLocation {
                return "Location active (\(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude)))"
            }
            return "Location authorized, waiting for fix..."
        case .denied:
            return "Location access denied - go to Settings to enable"
        case .restricted:
            return "Location access restricted"
        case .notDetermined:
            return "Location permission required for distance filtering"
        @unknown default:
            return "Location status unknown"
        }
    }
}

#Preview {
    NavigationView {
        ADSBSettingsView()
    }
}
