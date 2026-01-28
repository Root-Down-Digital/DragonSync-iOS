//
//  AircraftStatusTab.swift
//  WarDragon
//
//  Created on 1/19/26.
//

import SwiftUI
import Charts
import CoreLocation

struct AircraftStatusTab: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var sortBy: SortOption = .altitude
    @State private var showFilters = false
    @State private var filterOptions = FilterOptions()
    
    enum SortOption: String, CaseIterable {
        case altitude = "Altitude"
        case speed = "Speed"
        case distance = "Distance"
        case callsign = "Callsign"
    }
    
    struct FilterOptions {
        var showEmergency = true
        var showNormal = true
        var minimumAltitude: Int = 0
        var maximumAltitude: Int = 50000
    }
    
    private var filteredAndSortedAircraft: [Aircraft] {
        var aircraft = cotViewModel.aircraftTracks
        
        // Apply filters
        aircraft = aircraft.filter { ac in
            // Filter by emergency status
            if ac.isEmergency && !filterOptions.showEmergency { return false }
            if !ac.isEmergency && !filterOptions.showNormal { return false }
            
            // Filter by altitude
            if let alt = ac.altitudeFeet {
                if alt < filterOptions.minimumAltitude || alt > filterOptions.maximumAltitude {
                    return false
                }
            }
            
            return true
        }
        
        // Sort
        switch sortBy {
        case .altitude:
            return aircraft.sorted { ($0.altitudeFeet ?? 0) > ($1.altitudeFeet ?? 0) }
        case .speed:
            return aircraft.sorted { ($0.speedKnots ?? 0) > ($1.speedKnots ?? 0) }
        case .distance:
            // Would need user location for true distance sorting
            return aircraft.sorted { ($0.seen ?? 999) < ($1.seen ?? 999) }
        case .callsign:
            return aircraft.sorted { $0.displayName < $1.displayName }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main list
            if cotViewModel.aircraftTracks.isEmpty {
                emptyStateView
            } else {
                List {
                    // Stats header at the top of list
                    Section {
                        aircraftStatsHeader
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    
                    // Altitude distribution chart
                    if let altitudeData = altitudeDistributionData, !altitudeData.isEmpty {
                        Section {
                            altitudeDistributionChart(data: altitudeData)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    
                    // Active aircraft list
                    Section(header: Text("TRACKED AIRCRAFT (\(filteredAndSortedAircraft.count))")) {
                        ForEach(filteredAndSortedAircraft) { aircraft in
                            AircraftStatusRow(aircraft: aircraft)
                        }
                    }
                    
                    // Additional stats section
                    Section(header: Text("STATISTICS")) {
                        aircraftStatisticsList
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    // Refresh is automatic via ADS-B/OpenSky polling
                }
            }
        }
        .navigationTitle("Aircraft Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Filter button
                Button {
                    showFilters.toggle()
                } label: {
                    Label("Filter", systemImage: filterOptions.showAll ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .help("Filter aircraft")
                
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
                .help("Sort aircraft")
                
                // Clear button
                Button {
                    cotViewModel.clearAircraftTracks()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Clear all aircraft")
                .disabled(cotViewModel.aircraftTracks.isEmpty)
            }
        }
        .sheet(isPresented: $showFilters) {
            filterSheet
        }
    }
    
    // MARK: - Subviews
    
    private var aircraftStatsHeader: some View {
        VStack(spacing: 8) {
            // Primary stats row
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatBadge(
                    icon: "airplane.departure",
                    value: "\(cotViewModel.aircraftTracks.count)",
                    label: "Aircraft"
                )
                
                StatBadge(
                    icon: "antenna.radiowaves.left.and.right",
                    value: "\(activeAircraftCount)",
                    label: "Active"
                )
                
                if emergencyCount > 0 {
                    StatBadge(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(emergencyCount)",
                        label: "Emergency"
                    )
                }
                
                if let highest = highestAltitude {
                    StatBadge(
                        icon: "arrow.up.circle.fill",
                        value: "\(highest/1000)k ft",
                        label: "Max Alt"
                    )
                }
            }
            
            // Secondary stats row
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if let avgAlt = averageAltitude {
                    StatBadge(
                        icon: "arrow.up.right",
                        value: "\(avgAlt) ft",
                        label: "Avg Alt"
                    )
                }
                
                if let fastestSpeed = fastestSpeed {
                    StatBadge(
                        icon: "speedometer",
                        value: "\(fastestSpeed) kts",
                        label: "Fastest"
                    )
                }
                
                if nearbyCount > 0 {
                    StatBadge(
                        icon: "location.fill",
                        value: "\(nearbyCount)",
                        label: "Nearby"
                    )
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Aircraft Tracked")
                .font(.headline)
            
            Text("Enable ADS-B or OpenSky in Settings to track aircraft")
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
                Section(header: Text("Aircraft Types")) {
                    Toggle("Show Normal Aircraft", isOn: $filterOptions.showNormal)
                    Toggle("Show Emergency Aircraft", isOn: $filterOptions.showEmergency)
                }
                
                Section(header: Text("Altitude Range")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum: \(filterOptions.minimumAltitude) ft")
                            .font(.caption)
                        
                        Slider(value: Binding(
                            get: { Double(filterOptions.minimumAltitude) },
                            set: { filterOptions.minimumAltitude = Int($0) }
                        ), in: 0...50000, step: 1000)
                        
                        Text("Maximum: \(filterOptions.maximumAltitude) ft")
                            .font(.caption)
                            .padding(.top, 8)
                        
                        Slider(value: Binding(
                            get: { Double(filterOptions.maximumAltitude) },
                            set: { filterOptions.maximumAltitude = Int($0) }
                        ), in: 0...50000, step: 1000)
                    }
                }
                
                Section {
                    Button("Reset Filters") {
                        filterOptions = FilterOptions()
                    }
                }
            }
            .navigationTitle("Filter Aircraft")
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
    private func altitudeDistributionChart(data: [AltitudeDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALTITUDE DISTRIBUTION")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
            
            Chart(data) { point in
                BarMark(
                    x: .value("Range", point.range),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(.cyan.gradient)
                .annotation(position: .top) {
                    Text("\(point.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 120)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let range = value.as(String.self) {
                            Text(range)
                                .font(.system(size: 9))
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
    
    private var aircraftStatisticsList: some View {
        Group {
            HStack {
                Text("Total Tracked")
                Spacer()
                Text("\(cotViewModel.aircraftTracks.count)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Currently Active")
                Spacer()
                Text("\(activeAircraftCount)")
                    .foregroundColor(.secondary)
            }
            
            if let avgAlt = averageAltitude {
                HStack {
                    Text("Average Altitude")
                    Spacer()
                    Text("\(avgAlt) ft")
                        .foregroundColor(.secondary)
                }
            }
            
            if let avgSpeed = averageSpeed {
                HStack {
                    Text("Average Speed")
                    Spacer()
                    Text("\(avgSpeed) kts")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("Aircraft with Position")
                Spacer()
                Text("\(aircraftWithPosition)")
                    .foregroundColor(.secondary)
            }
            
            if hasOpenSkyAircraft && hasADSBAircraft {
                Divider()
                
                HStack {
                    Text("OpenSky Network")
                    Spacer()
                    Text("\(openSkyCount)")
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("ADS-B Direct")
                    Spacer()
                    Text("\(adsbCount)")
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var activeAircraftCount: Int {
        cotViewModel.aircraftTracks.filter { !$0.isStale }.count
    }
    
    private var emergencyCount: Int {
        cotViewModel.aircraftTracks.filter { $0.isEmergency }.count
    }
    
    private var highestAltitude: Int? {
        cotViewModel.aircraftTracks.compactMap { $0.altitudeFeet }.max()
    }
    
    private var averageAltitude: Int? {
        let altitudes = cotViewModel.aircraftTracks.compactMap { $0.altitudeFeet }
        guard !altitudes.isEmpty else { return nil }
        return altitudes.reduce(0, +) / altitudes.count
    }
    
    private var fastestSpeed: Int? {
        cotViewModel.aircraftTracks.compactMap { $0.speedKnots }.max()
    }
    
    private var averageSpeed: Int? {
        let speeds = cotViewModel.aircraftTracks.compactMap { $0.speedKnots }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / speeds.count
    }
    
    private var nearbyCount: Int {
        guard let userLocation = LocationManager.shared.userLocation else { return 0 }
        
        return cotViewModel.aircraftTracks.filter { aircraft in
            guard let coord = aircraft.coordinate else { return false }
            let aircraftLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = userLocation.distance(from: aircraftLocation)
            return distance <= 10000 // Within 10km
        }.count
    }
    
    private var aircraftWithPosition: Int {
        cotViewModel.aircraftTracks.filter { $0.coordinate != nil }.count
    }
    
    private var openSkyCount: Int {
        cotViewModel.aircraftTracks.filter { $0.hex.count == 6 }.count
    }
    
    private var adsbCount: Int {
        cotViewModel.aircraftTracks.filter { $0.hex.count != 6 }.count
    }
    
    private var hasOpenSkyAircraft: Bool {
        openSkyCount > 0
    }
    
    private var hasADSBAircraft: Bool {
        adsbCount > 0
    }
    
    private var altitudeDistributionData: [AltitudeDataPoint]? {
        let altitudes = cotViewModel.aircraftTracks.compactMap { $0.altitudeFeet }
        guard !altitudes.isEmpty else { return nil }
        
        let ranges = [
            ("0-2k", altitudes.filter { $0 < 2000 }.count),
            ("2k-5k", altitudes.filter { $0 >= 2000 && $0 < 5000 }.count),
            ("5k-10k", altitudes.filter { $0 >= 5000 && $0 < 10000 }.count),
            ("10k-20k", altitudes.filter { $0 >= 10000 && $0 < 20000 }.count),
            ("20k+", altitudes.filter { $0 >= 20000 }.count)
        ]
        
        return ranges.enumerated().compactMap { index, item in
            item.1 > 0 ? AltitudeDataPoint(id: index, range: item.0, count: item.1) : nil
        }
    }
}

// MARK: - Supporting Views

private struct AircraftStatusRow: View {
    let aircraft: Aircraft
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                // Callsign/Hex
                Text(aircraft.displayName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                Spacer()
                
                // Emergency indicator
                if aircraft.isEmergency {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                
                // Time since last seen
                if let seen = aircraft.seen {
                    Text("\(seen)s ago")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Details row
            HStack(spacing: 16) {
                // Altitude
                if let alt = aircraft.altitudeFeet {
                    DetailItem(
                        icon: "arrow.up.right",
                        label: "\(alt) ft",
                        color: .cyan
                    )
                }
                
                // Speed
                if let speed = aircraft.speedKnots {
                    DetailItem(
                        icon: "speedometer",
                        label: "\(speed) kts",
                        color: .green
                    )
                }
                
                // Track (heading over ground)
                if let track = aircraft.track {
                    DetailItem(
                        icon: "location.north.fill",
                        label: "\(Int(track))°",
                        color: .purple
                    )
                }
            }
            
            // Badges row
            HStack(spacing: 8) {
                Badge(text: aircraft.hex, color: .blue)
                
                if aircraft.hex.count == 6 {
                    Badge(text: "OPENSKY", color: .blue)
                } else {
                    Badge(text: "ADS-B", color: .green)
                }
                
                if aircraft.isEmergency {
                    Badge(text: "EMERGENCY", color: .red)
                }
                
                Badge(text: signalQualityText, color: signalQualityColor)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        if aircraft.isEmergency {
            return .red
        }
        return aircraft.isStale ? .gray : .green
    }
    
    private var signalQualityText: String {
        switch aircraft.signalQuality {
        case .excellent: return "EXCELLENT"
        case .good: return "GOOD"
        case .fair: return "FAIR"
        case .poor: return "POOR"
        case .unknown: return "UNKNOWN"
        }
    }
    
    private var signalQualityColor: Color {
        switch aircraft.signalQuality {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        case .unknown: return .gray
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
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cyan)
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

private struct AltitudeDataPoint: Identifiable {
    let id: Int
    let range: String
    let count: Int
}

// MARK: - Extensions

private extension AircraftStatusTab.FilterOptions {
    var showAll: Bool {
        showNormal && showEmergency && minimumAltitude == 0 && maximumAltitude == 50000
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AircraftStatusTab(cotViewModel: CoTViewModel(statusViewModel: StatusViewModel()))
    }
}
