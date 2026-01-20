//
//  DetectionsStatsView.swift
//  WarDragon
//
//  Created on 1/19/26.
//

import SwiftUI
import Charts

struct DetectionsStatsView: View {
    @ObservedObject var cotViewModel: CoTViewModel
    let detectionMode: ContentView.DetectionMode
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header with summary stats
                statsHeader
                
                // Charts section
                if detectionMode == .drones || detectionMode == .both {
                    droneCharts
                }
                
                if detectionMode == .aircraft || detectionMode == .both {
                    aircraftCharts
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("DETECTION OVERVIEW")
                    .font(.appHeadline)
                Spacer()
            }
            
            // Quick stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if detectionMode == .drones || detectionMode == .both {
                    QuickStatCard(
                        title: "Active Drones",
                        value: "\(activeDroneCount)",
                        icon: "airplane.circle.fill",
                        color: .blue
                    )
                    
                    QuickStatCard(
                        title: "Unique MACs",
                        value: "\(uniqueMacCount)",
                        icon: "number.circle.fill",
                        color: .purple
                    )
                    
                    QuickStatCard(
                        title: "FPV Detected",
                        value: "\(fpvCount)",
                        icon: "antenna.radiowaves.left.and.right",
                        color: .orange
                    )
                }
                
                if detectionMode == .aircraft || detectionMode == .both {
                    QuickStatCard(
                        title: "Aircraft",
                        value: "\(cotViewModel.aircraftTracks.count)",
                        icon: "airplane.departure",
                        color: .cyan
                    )
                    
                    if let maxAlt = maxAircraftAltitude {
                        QuickStatCard(
                            title: "Max Alt",
                            value: "\(maxAlt)ft",
                            icon: "arrow.up.circle.fill",
                            color: .green
                        )
                    }
                    
                    QuickStatCard(
                        title: "Emergency",
                        value: "\(emergencyAircraftCount)",
                        icon: "exclamationmark.triangle.fill",
                        color: emergencyAircraftCount > 0 ? .red : .gray
                    )
                }
            }
        }
    }
    
    // MARK: - Drone Charts
    
    @ViewBuilder
    private var droneCharts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
            // Drone Type Distribution
            VStack(alignment: .leading, spacing: 8) {
                Text("DRONE TYPES")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Chart(droneTypeData) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Type", item.type)
                    )
                    .foregroundStyle(by: .value("Type", item.type))
                    .annotation(position: .trailing) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: CGFloat(droneTypeData.count * 30 + 20))
                .chartLegend(.hidden)
            }
            
            // Signal Strength Distribution
            if !droneSignalData.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SIGNAL STRENGTH")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Chart(droneSignalData) { item in
                        BarMark(
                            x: .value("Range", item.range),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(.blue.gradient)
                        .annotation(position: .top) {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 120)
                }
            }
            
            // ID Type Distribution (Pie/Donut Chart)
            if !idTypeData.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ID PROTOCOLS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Chart(idTypeData) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.5),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("Type", item.type))
                            .opacity(0.8)
                        }
                        .frame(height: 120)
                        
                        // Legend
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(idTypeData) { item in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(colorForIDType(item.type))
                                        .frame(width: 8, height: 8)
                                    Text(item.type)
                                        .font(.caption2)
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
    }
    
    // MARK: - Aircraft Charts
    
    @ViewBuilder
    private var aircraftCharts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
            // Altitude Distribution
            if !altitudeData.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALTITUDE DISTRIBUTION")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Chart(altitudeData) { item in
                        BarMark(
                            x: .value("Range", item.range),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(.cyan.gradient)
                        .annotation(position: .top) {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 120)
                }
            }
            
            // Speed Distribution
            if !speedData.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SPEED DISTRIBUTION")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Chart(speedData) { item in
                        BarMark(
                            x: .value("Range", item.range),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(.green.gradient)
                        .annotation(position: .top) {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }
    
    // MARK: - Computed Data
    
    private var activeDroneCount: Int {
        cotViewModel.parsedMessages.count
    }
    
    private var uniqueMacCount: Int {
        Set(cotViewModel.parsedMessages.compactMap { $0.mac }).count
    }
    
    private var fpvCount: Int {
        cotViewModel.parsedMessages.filter { $0.isFPVDetection }.count
    }
    
    private var maxAircraftAltitude: Int? {
        cotViewModel.aircraftTracks.compactMap { $0.altitudeFeet }.max()
    }
    
    private var emergencyAircraftCount: Int {
        cotViewModel.aircraftTracks.filter { $0.isEmergency }.count
    }
    
    // Drone type distribution
    private var droneTypeData: [ChartDataItem] {
        let types = Dictionary(grouping: cotViewModel.parsedMessages) { $0.uaType }
        return types.map { type, messages in
            ChartDataItem(
                id: type.rawValue,
                type: formatDroneType(type),
                count: messages.count
            )
        }.sorted { $0.count > $1.count }
    }
    
    // Signal strength distribution
    private var droneSignalData: [RangeDataItem] {
        let signals = cotViewModel.parsedMessages.compactMap { $0.rssi }
        guard !signals.isEmpty else { return [] }
        
        let ranges = [
            ("Excellent (>-60)", signals.filter { $0 > -60 }.count),
            ("Good (-60 to -70)", signals.filter { $0 <= -60 && $0 > -70 }.count),
            ("Fair (-70 to -80)", signals.filter { $0 <= -70 && $0 > -80 }.count),
            ("Poor (<-80)", signals.filter { $0 <= -80 }.count)
        ]
        
        return ranges.enumerated().map { index, item in
            RangeDataItem(id: index, range: item.0, count: item.1)
        }.filter { $0.count > 0 }
    }
    
    // ID type distribution
    private var idTypeData: [ChartDataItem] {
        let types = Dictionary(grouping: cotViewModel.parsedMessages) { $0.idType }
        return types.map { type, messages in
            ChartDataItem(
                id: type,
                type: type,
                count: messages.count
            )
        }.sorted { $0.count > $1.count }
    }
    
    // Altitude distribution for aircraft
    private var altitudeData: [RangeDataItem] {
        let altitudes = cotViewModel.aircraftTracks.compactMap { $0.altitudeFeet }
        guard !altitudes.isEmpty else { return [] }
        
        let ranges = [
            ("0-2k ft", altitudes.filter { $0 < 2000 }.count),
            ("2k-5k ft", altitudes.filter { $0 >= 2000 && $0 < 5000 }.count),
            ("5k-10k ft", altitudes.filter { $0 >= 5000 && $0 < 10000 }.count),
            ("10k-20k ft", altitudes.filter { $0 >= 10000 && $0 < 20000 }.count),
            (">20k ft", altitudes.filter { $0 >= 20000 }.count)
        ]
        
        return ranges.enumerated().map { index, item in
            RangeDataItem(id: index, range: item.0, count: item.1)
        }.filter { $0.count > 0 }
    }
    
    // Speed distribution for aircraft
    private var speedData: [RangeDataItem] {
        let speeds = cotViewModel.aircraftTracks.compactMap { $0.speedKnots }
        guard !speeds.isEmpty else { return [] }
        
        let ranges = [
            ("0-100 kts", speeds.filter { $0 < 100 }.count),
            ("100-200 kts", speeds.filter { $0 >= 100 && $0 < 200 }.count),
            ("200-300 kts", speeds.filter { $0 >= 200 && $0 < 300 }.count),
            ("300-400 kts", speeds.filter { $0 >= 300 && $0 < 400 }.count),
            (">400 kts", speeds.filter { $0 >= 400 }.count)
        ]
        
        return ranges.enumerated().map { index, item in
            RangeDataItem(id: index, range: item.0, count: item.1)
        }.filter { $0.count > 0 }
    }
    
    // MARK: - Helper Functions
    
    private func formatDroneType(_ type: DroneSignature.IdInfo.UAType) -> String {
        switch type {
        case .none: return "None"
        case .helicopter: return "Helicopter"
        case .aeroplane: return "Aeroplane"
        case .gyroplane: return "Gyroplane"
        case .hybridLift: return "Hybrid Lift"
        case .ornithopter: return "Ornithopter"
        case .glider: return "Glider"
        case .kite: return "Kite"
        case .freeballoon: return "Free Balloon"
        case .captive: return "Captive Balloon"
        case .airship: return "Airship"
        case .freeFall: return "Parachute"
        case .rocket: return "Rocket"
        case .tethered: return "Tethered"
        case .groundObstacle: return "Ground Obstacle"
        case .other: return "Other"
        }
    }
    
    private func colorForIDType(_ type: String) -> Color {
        switch type {
        case let t where t.contains("DJI"): return .blue
        case let t where t.contains("CAA"): return .green
        case let t where t.contains("ANSI"): return .orange
        case let t where t.contains("FR"): return .purple
        default: return .gray
        }
    }
}

// MARK: - Supporting Views

private struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Data Models

private struct ChartDataItem: Identifiable {
    let id: String
    let type: String
    let count: Int
}

private struct RangeDataItem: Identifiable {
    let id: Int
    let range: String
    let count: Int
}

// MARK: - Preview

#Preview {
    DetectionsStatsView(
        cotViewModel: CoTViewModel(statusViewModel: StatusViewModel()),
        detectionMode: .drones
    )
}
