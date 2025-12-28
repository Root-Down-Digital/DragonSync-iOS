//
//  RateLimitSettingsView.swift
//  WarDragon
//
//  Rate limiting configuration UI
//

import SwiftUI

struct RateLimitSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var selectedPreset: RateLimitPreset?
    @State private var showingStatistics = false
    
    enum RateLimitPreset: String, CaseIterable {
        case conservative = "Conservative"
        case balanced = "Balanced"
        case aggressive = "Aggressive"
        case custom = "Custom"
        
        var config: RateLimitConfiguration? {
            switch self {
            case .conservative: return .conservative
            case .balanced: return .balanced
            case .aggressive: return .aggressive
            case .custom: return nil
            }
        }
        
        var description: String {
            switch self {
            case .conservative: return "Low bandwidth, conservative limits"
            case .balanced: return "Recommended for most users"
            case .aggressive: return "High frequency, more CPU usage"
            case .custom: return "Custom configuration"
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Rate Limiting", isOn: $settings.rateLimitEnabled)
            } header: {
                Label("Rate Limiting", systemImage: "speedometer")
            } footer: {
                Text("Throttle message publishing to reduce CPU usage and network bandwidth")
            }
            
            if settings.rateLimitEnabled {
                Section("Presets") {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(RateLimitPreset.allCases, id: \.self) { preset in
                            VStack(alignment: .leading) {
                                Text(preset.rawValue)
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(preset as RateLimitPreset?)
                        }
                    }
                    .onChange(of: selectedPreset) { oldValue, newValue in
                        applyPreset(newValue)
                    }
                    
                    Text("Select a preset or customize individual settings below")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Per-Drone Limits") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Publish Interval")
                            Spacer()
                            Text("\(settings.rateLimitDroneInterval, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.rateLimitDroneInterval, in: 0.5...10, step: 0.5)
                        Text("Minimum time between publishes for same drone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Stepper("Max Per Minute: \(settings.rateLimitDroneMaxPerMinute)", 
                            value: $settings.rateLimitDroneMaxPerMinute, 
                            in: 10...120, 
                            step: 5)
                }
                
                Section("MQTT Limits") {
                    Stepper("Max Per Second: \(settings.rateLimitMQTTMaxPerSecond)", 
                            value: $settings.rateLimitMQTTMaxPerSecond, 
                            in: 1...50)
                    
                    Stepper("Burst Count: \(settings.rateLimitMQTTBurstCount)", 
                            value: $settings.rateLimitMQTTBurstCount, 
                            in: 5...100, 
                            step: 5)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Burst Period")
                            Spacer()
                            Text("\(settings.rateLimitMQTTBurstPeriod, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.rateLimitMQTTBurstPeriod, in: 1...30, step: 1)
                        Text("Allow \(settings.rateLimitMQTTBurstCount) messages in \(Int(settings.rateLimitMQTTBurstPeriod))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("TAK Server Limits") {
                    Stepper("Max Per Second: \(settings.rateLimitTAKMaxPerSecond)", 
                            value: $settings.rateLimitTAKMaxPerSecond, 
                            in: 1...20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Publish Interval")
                            Spacer()
                            Text("\(settings.rateLimitTAKInterval, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.rateLimitTAKInterval, in: 0.1...5, step: 0.1)
                        Text("Minimum time between TAK messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Webhook Limits") {
                    Stepper("Max Per Minute: \(settings.rateLimitWebhookMaxPerMinute)", 
                            value: $settings.rateLimitWebhookMaxPerMinute, 
                            in: 5...100, 
                            step: 5)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Webhook Interval")
                            Spacer()
                            Text("\(settings.rateLimitWebhookInterval, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.rateLimitWebhookInterval, in: 0.5...10, step: 0.5)
                        Text("Minimum time between webhook calls")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Statistics") {
                    Button {
                        showingStatistics = true
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar")
                            Text("View Rate Statistics")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("What is Rate Limiting?", systemImage: "questionmark.circle")
                            .font(.headline)
                        
                        Text("Rate limiting prevents your app from sending too many messages too quickly, which can:")
                            .font(.caption)
                        
                        Text("• Reduce CPU usage")
                            .font(.caption)
                        Text("• Save network bandwidth")
                            .font(.caption)
                        Text("• Prevent server overload")
                            .font(.caption)
                        Text("• Improve battery life")
                            .font(.caption)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Recommended Settings:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("• Use 'Balanced' preset for most cases")
                            .font(.caption)
                        Text("• Use 'Conservative' on slow networks")
                            .font(.caption)
                        Text("• Use 'Aggressive' only when needed")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Help")
                }
            }
        }
        .navigationTitle("Rate Limiting")
        .sheet(isPresented: $showingStatistics) {
            RateLimitStatisticsView()
        }
        .onAppear {
            detectCurrentPreset()
        }
    }
    
    // MARK: - Preset Handling
    
    private func applyPreset(_ preset: RateLimitPreset?) {
        guard let preset = preset, let config = preset.config else { return }
        settings.updateRateLimitConfiguration(config)
        RateLimiterManager.shared.updateConfiguration(config)
    }
    
    private func detectCurrentPreset() {
        let current = settings.rateLimitConfiguration
        
        if current == .conservative {
            selectedPreset = .conservative
        } else if current == .balanced {
            selectedPreset = .balanced
        } else if current == .aggressive {
            selectedPreset = .aggressive
        } else {
            selectedPreset = .custom
        }
    }
}

// MARK: - Statistics View

struct RateLimitStatisticsView: View {
    @State private var stats: RateLimitStatistics?
    @State private var timer: Timer?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                if let stats = stats {
                    Section("Current Rates") {
                        HStack {
                            Text("MQTT")
                            Spacer()
                            Text("\(stats.mqttRate, specifier: "%.1f") msg/s")
                                .foregroundColor(rateColor(stats.mqttRate, max: 10))
                        }
                        
                        HStack {
                            Text("TAK Server")
                            Spacer()
                            Text("\(stats.takRate, specifier: "%.1f") msg/s")
                                .foregroundColor(rateColor(stats.takRate, max: 5))
                        }
                        
                        HStack {
                            Text("Webhooks")
                            Spacer()
                            Text("\(stats.webhookRate, specifier: "%.1f") msg/s")
                                .foregroundColor(rateColor(stats.webhookRate, max: 1))
                        }
                    }
                    
                    Section("Tracking") {
                        HStack {
                            Text("Drones Tracked")
                            Spacer()
                            Text("\(stats.trackedDrones)")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Loading statistics...")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Text("Statistics update every second")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Rate Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                updateStats()
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    updateStats()
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    private func updateStats() {
        stats = RateLimiterManager.shared.getStatistics()
    }
    
    private func rateColor(_ rate: Double, max: Double) -> Color {
        let percentage = rate / max
        switch percentage {
        case 0..<0.5: return .green
        case 0.5..<0.8: return .yellow
        default: return .red
        }
    }
}

#Preview {
    NavigationView {
        RateLimitSettingsView()
    }
}
