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
    @State private var updateTimer: Timer?
    
    // Real-time timeline data - computed from current detections
    // This shows detection activity over the past 6 minutes in 30-second buckets
    private var timelineData: [TimelineDataPoint] {
        let now = Date()
        let timeWindow: TimeInterval = 360 // 6 minutes
        let bucketCount = 12 // 30-second buckets
        let bucketDuration = timeWindow / Double(bucketCount)
        
        // Create time buckets going back 6 minutes
        let buckets: [(start: Date, end: Date)] = (0..<bucketCount).map { i in
            let start = now.addingTimeInterval(-timeWindow + Double(i) * bucketDuration)
            let end = now.addingTimeInterval(-timeWindow + Double(i + 1) * bucketDuration)
            return (start, end)
        }
        
        // Count detections in each bucket based on when they were observed
        return buckets.map { bucket in
            // For drones: Count how many were observed in this time bucket
            var droneCount = 0
            if detectionMode == .drones || detectionMode == .both {
                droneCount = cotViewModel.parsedMessages.filter { message in
                    // Use observedAt timestamp (when the detection was actually captured by hardware)
                    if let observedAt = message.observedAt {
                        let timestamp = Date(timeIntervalSince1970: observedAt)
                        return timestamp >= bucket.start && timestamp < bucket.end
                    }
                    // Fallback: use lastUpdated if no observedAt
                    let timestamp = message.lastUpdated
                    return timestamp >= bucket.start && timestamp < bucket.end
                }.count
            }
            
            // For aircraft: Count how many were last seen in this time bucket
            var aircraftCount = 0
            if detectionMode == .aircraft || detectionMode == .both {
                aircraftCount = cotViewModel.aircraftTracks.filter { track in
                    let timestamp = track.lastSeen
                    return timestamp >= bucket.start && timestamp < bucket.end
                }.count
            }
            
            return TimelineDataPoint(
                timestamp: bucket.end, // Use bucket end time for x-axis
                droneCount: droneCount,
                aircraftCount: aircraftCount
            )
        }
    }
    
    // Signal strength/altitude trend data - computed from current detections
    // This shows average signal strength or altitude over the past 6 minutes
    private var signalTrendData: [SignalTrendPoint] {
        let now = Date()
        let timeWindow: TimeInterval = 360 // 6 minutes
        let bucketCount = 12 // 30-second buckets
        let bucketDuration = timeWindow / Double(bucketCount)
        
        // Create time buckets going back 6 minutes
        let buckets: [(start: Date, end: Date)] = (0..<bucketCount).map { i in
            let start = now.addingTimeInterval(-timeWindow + Double(i) * bucketDuration)
            let end = now.addingTimeInterval(-timeWindow + Double(i + 1) * bucketDuration)
            return (start, end)
        }
        
        return buckets.map { bucket in
            var avgRSSI: Double = -100.0
            var avgAltitude: Double = 0.0
            
            if detectionMode == .aircraft {
                // For aircraft, calculate average altitude
                let altitudes = cotViewModel.aircraftTracks.compactMap { track -> Double? in
                    let timestamp = track.lastSeen
                    guard timestamp >= bucket.start && timestamp < bucket.end else { return nil }
                    guard let altitude = track.altitudeFeet else { return nil }
                    return Double(altitude)
                }
                
                if !altitudes.isEmpty {
                    avgAltitude = altitudes.reduce(0, +) / Double(altitudes.count)
                }
            } else {
                // For drones/both, calculate average RSSI
                let rssiValues = cotViewModel.parsedMessages.compactMap { message -> Double? in
                    // Use observedAt timestamp
                    let timestamp: Date
                    if let observedAt = message.observedAt {
                        timestamp = Date(timeIntervalSince1970: observedAt)
                    } else {
                        timestamp = message.lastUpdated
                    }
                    
                    guard timestamp >= bucket.start && timestamp < bucket.end else { return nil }
                    
                    // Use normalized RSSI which handles both standard and FPV signal values
                    guard let rssi = message.normalizedRSSI else {
                        return nil
                    }
                    return rssi
                }
                
                if !rssiValues.isEmpty {
                    avgRSSI = rssiValues.reduce(0, +) / Double(rssiValues.count)
                }
            }
            
            return SignalTrendPoint(
                timestamp: bucket.end,
                averageRSSI: avgRSSI,
                averageAltitude: avgAltitude
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                timelineChart
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                
                signalTrendChart
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
            }
            
            statsHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        // No longer needed - chart uses computed property
    }
    
    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Compact Stats Header
    
    private var compactStatsHeader: some View {
        HStack(spacing: 12) {
            if detectionMode == .drones || detectionMode == .both {
                StatPill(icon: "airplane.circle.fill", value: "\(activeDroneCount)", label: "Drones", color: .blue)
                StatPill(icon: "number.circle.fill", value: "\(uniqueMacCount)", label: "MACs", color: .purple)
            }
            
            if detectionMode == .aircraft || detectionMode == .both {
                StatPill(icon: "airplane.departure", value: "\(cotViewModel.aircraftTracks.count)", label: "Aircraft", color: .cyan)
                if let maxAlt = maxAircraftAltitude {
                    StatPill(icon: "arrow.up.circle.fill", value: "\(maxAlt/1000)k", label: "Alt", color: .green)
                }
            }
        }
    }
    
    // MARK: - Signal Strength Trend Chart
    
    private var signalTrendChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SIGNAL STRENGTH TREND")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            if detectionMode == .aircraft {
                // For aircraft mode, show altitude trend instead
                Chart(signalTrendData) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Avg Alt", point.averageAltitude)
                    )
                    .foregroundStyle(.cyan)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Avg Alt", point.averageAltitude)
                    )
                    .foregroundStyle(.cyan.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("Altitude (ft)", alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.hour().minute(), anchor: .top)
                            .font(.system(size: 9))
                    }
                    AxisMarks(values: .stride(by: .minute, count: 2)) { _ in
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 80)
            } else {
                // For drones/both mode, show RSSI trend
                Chart(signalTrendData) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Avg RSSI", point.averageRSSI)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Avg RSSI", point.averageRSSI)
                    )
                    .foregroundStyle(.orange.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                    
                    // Warning threshold line (stronger signal = closer)
                    RuleMark(y: .value("Warning", -60))
                        .foregroundStyle(.red.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
                .chartYScale(domain: -128...(-20))
                .chartYAxisLabel("RSSI (dBm)", alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.hour().minute(), anchor: .top)
                            .font(.system(size: 9))
                    }
                    AxisMarks(values: .stride(by: .minute, count: 2)) { _ in
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 80)
            }
        }
    }
    
    // MARK: - Timeline Chart
    
    private var timelineChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DETECTIONS TIMELINE")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Chart(timelineData) { point in
                if detectionMode == .drones || detectionMode == .both {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Drones", point.droneCount)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Drones", point.droneCount)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
                
                if detectionMode == .aircraft || detectionMode == .both {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Aircraft", point.aircraftCount)
                    )
                    .foregroundStyle(.cyan)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Aircraft", point.aircraftCount)
                    )
                    .foregroundStyle(.cyan.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 80)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 2)) { value in
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                }
                AxisMarks(values: .stride(by: .minute, count: 2)) { _ in
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
    }
    
    // MARK: - Timeline Data Management
    // No longer needed - using computed property for real-time data
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("OVERVIEW")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Quick stats grid - COMPACT VERSION
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                if detectionMode == .drones || detectionMode == .both {
                    QuickStatCard(
                        title: "Active",
                        value: "\(activeDroneCount)",
                        icon: "airplane.circle.fill",
                        color: .blue
                    )
                    
                    QuickStatCard(
                        title: "MACs",
                        value: "\(uniqueMacCount)",
                        icon: "number.circle.fill",
                        color: .purple
                    )
                    
                    QuickStatCard(
                        title: "FPV",
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
                            value: "\(maxAlt/1000)k",
                            icon: "arrow.up.circle.fill",
                            color: .green
                        )
                    }
                    
                    QuickStatCard(
                        title: "Alert",
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
        VStack(alignment: .leading, spacing: 12) {
            // Drone Type Distribution
            VStack(alignment: .leading, spacing: 6) {
                Text("DRONE TYPES")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
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
                .frame(height: CGFloat(droneTypeData.count * 28 + 20))
                .chartLegend(.hidden)
            }
            
            // Signal Strength Distribution
            if !droneSignalData.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SIGNAL STRENGTH")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
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
                    .frame(height: 100)
                }
            }
            
            // ID Type Distribution (Pie/Donut Chart)
            if !idTypeData.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ID PROTOCOLS")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
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
                        .frame(height: 100)
                        
                        // Legend
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(idTypeData) { item in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(colorForIDType(item.type))
                                        .frame(width: 6, height: 6)
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
        VStack(alignment: .leading, spacing: 12) {
            // Altitude Distribution
            if !altitudeData.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ALTITUDE DISTRIBUTION")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
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
                    .frame(height: 100)
                }
            }
            
            // Speed Distribution
            if !speedData.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SPEED DISTRIBUTION")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
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
                    .frame(height: 100)
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
        let signals = cotViewModel.parsedMessages.compactMap { $0.normalizedRSSI }
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

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
        )
    }
}

private struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            // Icon in a circle badge
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            // Value
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            
            // Label
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Data Models

private struct TimelineDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let droneCount: Int
    let aircraftCount: Int
}

private struct SignalTrendPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let averageRSSI: Double
    let averageAltitude: Double
}

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
