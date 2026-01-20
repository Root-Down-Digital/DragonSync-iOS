//
//  DronesStatusTab.swift
//  WarDragon
//
//  Created on 1/19/26.
//

import SwiftUI
import Charts

struct DronesStatusTab: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var sortBy: SortOption = .lastSeen
    @State private var showFilters = false
    @State private var filterOptions = FilterOptions()
    
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
                    // Active drones list - no redundant header, just the list
                    Section(header: sectionHeader) {
                        ForEach(filteredAndSortedDrones) { drone in
                            DroneStatusRow(drone: drone, cotViewModel: cotViewModel)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    // Refresh is automatic via CoT updates
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
    }
    
    // MARK: - Subviews
    
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
    
    private func clearAllDrones() {
        cotViewModel.parsedMessages.removeAll()
        cotViewModel.droneSignatures.removeAll()
        cotViewModel.macIdHistory.removeAll()
        cotViewModel.macProcessing.removeAll()
        cotViewModel.alertRings.removeAll()
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
