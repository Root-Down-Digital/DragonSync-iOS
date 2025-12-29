//
//  StatusMessageView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import MapKit
import CoreLocation


// MARK: - Sheet Types for Status View
enum StatusSheetType: Identifiable {
    case memory
    case map
    case adsbHistory
    
    var id: String {
        switch self {
        case .memory: return "memory"
        case .map: return "map"
        case .adsbHistory: return "adsbHistory"
        }
    }
}

//MARK - Helper for status data

fileprivate func formatBytes(_ bytes: Int64) -> String {
    let b  = Double(bytes)
    let KB = 1024.0
    let MB = KB * 1024.0
    let GB = MB * 1024.0
    
    switch b {
    case    0 ..< KB:
        return "\(bytes) B"
    case   KB ..< MB:
        return String(format: "%.2f KB", b / KB)
    case   MB ..< GB:
        return String(format: "%.2f MB", b / MB)
    default:
        return String(format: "%.2f GB", b / GB)
    }
}


// MARK: - CircularGauge View
struct CircularGauge: View {
    let value: Double
    let maxValue: Double
    let title: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(min(value / maxValue, 1.0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: value)
                
                VStack(spacing: 1) {
                    Text(String(format: "%.0f", value))
                        .font(.system(.title2, design: .monospaced))
                        .foregroundColor(color)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, height: 70)
            
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }
}

// MARK: - ResourceBar View
struct ResourceBar: View {
    let title: String
    let usedPercent: Double
    let details: String
    let color: Color
    let isInteractive: Bool
    let action: (() -> Void)?
    
    init(title: String, usedPercent: Double, details: String, color: Color, isInteractive: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.usedPercent = usedPercent
        self.details = details
        self.color = color
        self.isInteractive = isInteractive
        self.action = action
    }
    
    var body: some View {
        Button(action: action ?? {}) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title.uppercased())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(String(format: "%.1f%%", usedPercent))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(color)
                        .fontWeight(.bold)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [color.opacity(0.8), color]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(min(usedPercent / 100, 1.0)))
                            .animation(.easeInOut(duration: 0.3), value: usedPercent)
                    }
                }
                .frame(height: 8)
                
                Text(details)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isInteractive, let action = action {
                action()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StatusMessageView with Adaptive Layout
struct StatusMessageView: View {
    let message: StatusViewModel.StatusMessage
    @ObservedObject var statusViewModel: StatusViewModel
    @State private var activeSheet: StatusSheetType?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    init(message: StatusViewModel.StatusMessage, statusViewModel: StatusViewModel) {
        self.message = message
        self.statusViewModel = statusViewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Status Header
            statusHeader
            
            // Adaptive Content Layout
            if horizontalSizeClass == .regular {
                // iPad Layout - Horizontal
                iPadLayout
            } else {
                // iPhone Layout - Vertical
                iPhoneLayout
            }
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .memory:
                MemoryDetailView(memory: message.systemStats.memory)
            case .map:
                MapDetailView(coordinate: message.gpsData.coordinate)
            case .adsbHistory:
                ADSBHistoryView(statusViewModel: statusViewModel)
            }
        }
        .alert("Use Your Location for Status?", isPresented: $statusViewModel.showESP32LocationAlert) {
            Button("Allow") {
                Settings.shared.updateStatusLocationSettings(useLocation: true)
                LocationManager.shared.requestLocationPermission()
                statusViewModel.showESP32LocationAlert = false
            }
            Button("Don't Allow") {
                Settings.shared.updateStatusLocationSettings(useLocation: false)
                statusViewModel.showESP32LocationAlert = false
            }
        } message: {
            Text("This external device doesn't have GPS coordinates. Would you like to use your device's location?")
        }
    }
    
    // MARK: - Status Header
    private var statusHeader: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusViewModel.statusColor)
                        .frame(width: 12, height: 12)
                        .scaleEffect(statusViewModel.isSystemOnline ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: statusViewModel.isSystemOnline)
                    
                    Text(statusViewModel.statusText)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(statusViewModel.statusColor)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                Text(message.serialNumber)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(formatUptime(message.systemStats.uptime))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
            }
            
            // Last Received Status Row
            HStack {
                Text("LAST RECEIVED:")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(statusViewModel.lastReceivedText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(statusViewModel.isSystemOnline ? .green : .red)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    statusViewModel.statusColor.opacity(0.15),
                    statusViewModel.statusColor.opacity(0.08)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
    
    // MARK: - iPad Layout (Horizontal)
    private var iPadLayout: some View {
        VStack(spacing: 20) {
            // System Metrics Row (Full Width)
            HStack(alignment: .top, spacing: 20) {
                // Left Column - CPU and Temperature dials
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("SYSTEM METRICS", icon: "cpu")
                    
                    HStack(spacing: 16) {
                        CircularGauge(
                            value: message.systemStats.cpuUsage,
                            maxValue: 100,
                            title: "CPU",
                            unit: "%",
                            color: cpuColor(message.systemStats.cpuUsage)
                        )
                        
                        CircularGauge(
                            value: message.systemStats.temperature,
                            maxValue: 100,
                            title: "TEMP",
                            unit: "°C",
                            color: temperatureColor(message.systemStats.temperature)
                        )
                        
                        if message.antStats.plutoTemp > 0 {
                            CircularGauge(
                                value: message.antStats.plutoTemp,
                                maxValue: 100,
                                title: "PLUTO",
                                unit: "°C",
                                color: temperatureColor(message.antStats.plutoTemp)
                            )
                        }
                        
                        if message.antStats.zynqTemp > 0 {
                            CircularGauge(
                                value: message.antStats.zynqTemp,
                                maxValue: 100,
                                title: "ZYNQ",
                                unit: "°C",
                                color: temperatureColor(message.antStats.zynqTemp)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Right Column - Resource Bars
                VStack(spacing: 12) {
                    ResourceBar(
                        title: "MEMORY",
                        usedPercent: memoryUsagePercent,
                        details: "\(formatBytes(message.systemStats.memory.total - message.systemStats.memory.available)) / \(formatBytes(message.systemStats.memory.total))",
                        color: memoryColor(memoryUsagePercent),
                        isInteractive: true,
                        action: { activeSheet = .memory }
                    )
                    
                    ResourceBar(
                        title: "DISK",
                        usedPercent: diskUsagePercent,
                        details: "\(formatBytes(message.systemStats.disk.used)) / \(formatBytes(message.systemStats.disk.total))",
                        color: diskColor(diskUsagePercent),
                        isInteractive: false
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // ADS-B History Quick Access
            if !statusViewModel.adsbEncounterHistory.isEmpty {
                Button(action: { activeSheet = .adsbHistory }) {
                    HStack {
                        Image(systemName: "airplane.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ADS-B Encounter History")
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("\(statusViewModel.adsbEncounterHistory.count) aircraft tracked")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Location and Map Section (Full Width)
            VStack(alignment: .leading, spacing: 12) {
                // Location header and details - FULL WIDTH
                expandedLocationSection
                
                // Map Preview
                mapPreviewSection
            }
        }
        .padding(20)
    }
    
    private var expandedLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("LOCATION & SYSTEM STATUS", icon: "location")
            
            // Full-width location and system details
            HStack(spacing: 20) {
                // Location Details
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("COORDINATES")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: { activeSheet = .map }) {
                            HStack {
                                Text(String(format: "%.6f°", message.gpsData.latitude))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .fontWeight(.medium)
                                
                                Image(systemName: "location")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Text(String(format: "%.6f°", message.gpsData.longitude))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Alt:")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", message.gpsData.altitude))m")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("Speed:")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", message.gpsData.speed)) m/s")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // System Status Summary
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SYSTEM STATUS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CPU")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", message.systemStats.cpuUsage))%")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(cpuColor(message.systemStats.cpuUsage))
                                .fontWeight(.bold)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TEMP")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", message.systemStats.temperature))°C")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(temperatureColor(message.systemStats.temperature))
                                .fontWeight(.bold)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UPTIME")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(formatUptime(message.systemStats.uptime))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MEMORY")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", memoryUsagePercent))%")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(memoryColor(memoryUsagePercent))
                                .fontWeight(.bold)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DISK")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", diskUsagePercent))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(diskColor(diskUsagePercent))
                                .fontWeight(.bold)
                        }
                        
                        if message.antStats.plutoTemp > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PLUTO")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.1f", message.antStats.plutoTemp))°C")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(temperatureColor(message.antStats.plutoTemp))
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
    
    // MARK: - iPhone Layout (Vertical)
    private var iPhoneLayout: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                // System Metrics Column
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("SYSTEM METRICS", icon: "cpu")
                    
                    // Dials in 2x2 grid for iPhone
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        CircularGauge(
                            value: message.systemStats.cpuUsage,
                            maxValue: 100,
                            title: "CPU",
                            unit: "%",
                            color: cpuColor(message.systemStats.cpuUsage)
                        )
                        
                        CircularGauge(
                            value: message.systemStats.temperature,
                            maxValue: 100,
                            title: "TEMP",
                            unit: "°C",
                            color: temperatureColor(message.systemStats.temperature)
                        )
                        
                        if message.antStats.plutoTemp > 0 {
                            CircularGauge(
                                value: message.antStats.plutoTemp,
                                maxValue: 100,
                                title: "PLUTO",
                                unit: "°C",
                                color: temperatureColor(message.antStats.plutoTemp)
                            )
                        }
                        
                        if message.antStats.zynqTemp > 0 {
                            CircularGauge(
                                value: message.antStats.zynqTemp,
                                maxValue: 100,
                                title: "ZYNQ",
                                unit: "°C",
                                color: temperatureColor(message.antStats.zynqTemp)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Resource Bars (Full Width)
            VStack(spacing: 12) {
                ResourceBar(
                    title: "MEMORY",
                    usedPercent: memoryUsagePercent,
                    details: "\(formatBytes(message.systemStats.memory.total - message.systemStats.memory.available)) / \(formatBytes(message.systemStats.memory.total))",
                    color: memoryColor(memoryUsagePercent),
                    isInteractive: true,
                    action: { activeSheet = .memory }
                )
                
                ResourceBar(
                    title: "DISK",
                    usedPercent: diskUsagePercent,
                    details: "\(formatBytes(message.systemStats.disk.used)) / \(formatBytes(message.systemStats.disk.total))",
                    color: diskColor(diskUsagePercent),
                    isInteractive: false
                )
            }
            
            // ADS-B History Quick Access
            if !statusViewModel.adsbEncounterHistory.isEmpty {
                Button(action: { activeSheet = .adsbHistory }) {
                    HStack {
                        Image(systemName: "airplane.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ADS-B Encounter History")
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("\(statusViewModel.adsbEncounterHistory.count) aircraft tracked")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Map Preview
            mapPreviewSection
        }
        .padding(20)
    }
    
    // MARK: - Shared Components
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.blue)
            
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .fontWeight(.bold)
        }
    }
    
    private var mapPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MAP VIEW", icon: "map")
            
            Button(action: { activeSheet = .map }) {
                ZStack {
                    // Compact map preview
                    Map {
                        Marker(message.serialNumber, coordinate: message.gpsData.coordinate)
                            .tint(.blue)
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false) // Prevent map interaction, let button handle tap
                    
                    // Overlay with essential coordinates only
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(format: "%.4f°", message.gpsData.latitude)), \(String(format: "%.4f°", message.gpsData.longitude))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Computed Properties
    private var memoryUsagePercent: Double {
        guard message.systemStats.memory.total > 0 else { return 0 }
        let used = message.systemStats.memory.total - message.systemStats.memory.available
        return Double(used) / Double(message.systemStats.memory.total) * 100
    }
    
    private var diskUsagePercent: Double {
        guard message.systemStats.disk.total > 0 else { return 0 }
        // Use the percent field directly if it's available and non-zero
        if message.systemStats.disk.percent > 0 {
            return message.systemStats.disk.percent
        }
        // Fallback to calculation
        return Double(message.systemStats.disk.used) / Double(message.systemStats.disk.total) * 100
    }
    
    private func formatUptime(_ uptime: Double) -> String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func cpuColor(_ usage: Double) -> Color {
        switch usage {
        case 0..<60: return .green
        case 60..<80: return .yellow
        default: return .red
        }
    }
    
    private func memoryColor(_ percent: Double) -> Color {
        switch percent {
        case 0..<70: return .green
        case 70..<85: return .yellow
        default: return .red
        }
    }
    
    private func diskColor(_ percent: Double) -> Color {
        switch percent {
        case 0..<70: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case 0..<60: return .green
        case 60..<75: return .yellow
        default: return .red
        }
    }
}

// MARK: - LocationStatsView
struct LocationStatsView: View {
    let gpsData: StatusViewModel.StatusMessage.GPSData
    let onLocationTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onLocationTap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.6f°", gpsData.latitude))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                    
                    Text(String(format: "%.6f°", gpsData.longitude))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Alt:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", gpsData.altitude))m")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text("Speed:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", gpsData.speed)) m/s")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

// MARK: - Detail Views
struct MemoryDetailView: View {
    let memory: StatusViewModel.StatusMessage.SystemStats.MemoryStats
    
    
    var body: some View {
        NavigationView {
            List {
                Section("Memory Usage") {
                    MemoryBarView(title: "Total", value: memory.total, total: memory.total, color: .blue)
                    MemoryBarView(title: "Used", value: memory.used > 0 ? memory.used : (memory.total - memory.available), total: memory.total, color: .red)
                    MemoryBarView(title: "Available", value: memory.available, total: memory.total, color: .green)
                    MemoryBarView(title: "Free", value: memory.free, total: memory.total, color: .green)
                    MemoryBarView(title: "Active", value: memory.active, total: memory.total, color: .orange)
                    MemoryBarView(title: "Inactive", value: memory.inactive, total: memory.total, color: .yellow)
                    MemoryBarView(title: "Buffers", value: memory.buffers, total: memory.total, color: .purple)
                    MemoryBarView(title: "Cached", value: memory.cached, total: memory.total, color: .cyan)
                    MemoryBarView(title: "Shared", value: memory.shared, total: memory.total, color: .pink)
                    MemoryBarView(title: "Slab", value: memory.slab, total: memory.total, color: .indigo)
                }
            }
            .navigationTitle("Memory Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MemoryBarView: View {
    let title: String
    let value: Int64
    let total: Int64
    let color: Color
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total) * 100
    }
    

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatBytes(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(color)
                    .fontWeight(.medium)
                
                Text("(\(String(format: "%.1f", percentage))%)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

struct MapDetailView: View {
    let coordinate: CLLocationCoordinate2D
    @State private var mapCameraPosition: MapCameraPosition
    @Environment(\.dismiss) private var dismiss
    
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        self._mapCameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ))
    }
    
    var body: some View {
        NavigationView {
            Map(position: $mapCameraPosition) {
                Marker("System Location", coordinate: coordinate)
                    .tint(.red)
            }
            .navigationTitle("System Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MapPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - ADS-B History View
struct ADSBHistoryView: View {
    @ObservedObject var statusViewModel: StatusViewModel
    @State private var searchText = ""
    @State private var sortBy: SortOption = .lastSeen
    @Environment(\.dismiss) private var dismiss
    
    enum SortOption: String, CaseIterable {
        case lastSeen = "Last Seen"
        case firstSeen = "First Seen"
        case duration = "Duration"
        case altitude = "Max Altitude"
        case callsign = "Callsign"
    }
    
    var filteredHistory: [StatusViewModel.ADSBEncounter] {
        var history = statusViewModel.adsbEncounterHistory
        
        // Apply search filter
        if !searchText.isEmpty {
            history = history.filter { encounter in
                encounter.displayName.localizedCaseInsensitiveContains(searchText) ||
                encounter.id.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        switch sortBy {
        case .lastSeen:
            return history.sorted { $0.lastSeen > $1.lastSeen }
        case .firstSeen:
            return history.sorted { $0.firstSeen > $1.firstSeen }
        case .duration:
            return history.sorted { $0.duration > $1.duration }
        case .altitude:
            return history.sorted { $0.maxAltitude > $1.maxAltitude }
        case .callsign:
            return history.sorted { $0.displayName < $1.displayName }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Stats header
                if !statusViewModel.adsbEncounterHistory.isEmpty {
                    historyStatsHeader
                        .padding()
                        .background(Color(.secondarySystemBackground))
                }
                
                // Main list
                if statusViewModel.adsbEncounterHistory.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredHistory) { encounter in
                            ADSBEncounterRow(encounter: encounter)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search by callsign or ICAO")
                }
            }
            .navigationTitle("ADS-B Encounter History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sortBy = option
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if sortBy == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            statusViewModel.clearADSBHistory()
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var historyStatsHeader: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("\(statusViewModel.adsbEncounterHistory.count)")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                Text("Total")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 4) {
                Text("\(recentCount)")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text("Last Hour")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            if let highest = highestAltitude {
                VStack(spacing: 4) {
                    Text("\(Int(highest))")
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Max Alt (ft)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Aircraft Encounters")
                .font(.headline)
            
            Text("ADS-B aircraft encounters will appear here as they are detected")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var recentCount: Int {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return statusViewModel.adsbEncounterHistory.filter { $0.lastSeen > oneHourAgo }.count
    }
    
    private var highestAltitude: Double? {
        statusViewModel.adsbEncounterHistory.map { $0.maxAltitude }.max()
    }
}

// MARK: - ADS-B Encounter Row
struct ADSBEncounterRow: View {
    let encounter: StatusViewModel.ADSBEncounter
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(encounter.lastSeen)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Aircraft icon
            VStack {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .frame(width: 40)
            
            // Main info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(encounter.displayName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(timeAgo)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    Label("\(Int(encounter.maxAltitude))ft", systemImage: "arrow.up")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Label(encounter.formattedDuration, systemImage: "clock")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Label("\(encounter.totalSightings)", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

