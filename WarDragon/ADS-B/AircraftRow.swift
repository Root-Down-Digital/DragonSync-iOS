//
//  AircraftRow.swift
//  WarDragon
//
//  Aircraft list row view for ADS-B tracking
//

import SwiftUI
import MapKit

struct AircraftRow: View {
    let aircraft: Aircraft
    
    var body: some View {
        NavigationLink {
            AircraftDetailContent(aircraft: aircraft)
        } label: {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                
                // Aircraft icon and info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: aircraftIcon)
                            .foregroundColor(aircraft.isEmergency ? .red : .primary)
                        
                        Text(aircraft.displayName)
                            .font(.headline)
                        
                        if aircraft.isEmergency {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    
                    // Position info
                    if let coord = aircraft.coordinate {
                        HStack(spacing: 8) {
                            Label {
                                Text(formatCoordinate(coord.latitude, coord.longitude))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } icon: {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                            }
                            
                            if let alt = aircraft.altitudeFeet {
                                Divider()
                                    .frame(height: 12)
                                Label {
                                    Text("\(alt) ft")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } icon: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    
                    // Speed and heading
                    HStack(spacing: 8) {
                        if let speed = aircraft.speedKnots {
                            Label {
                                Text("\(speed) kts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } icon: {
                                Image(systemName: "speedometer")
                                    .font(.caption2)
                            }
                        }
                        
                        if let track = aircraft.track {
                            Divider()
                                .frame(height: 12)
                            Label {
                                Text("\(Int(track))°")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } icon: {
                                Image(systemName: "location.north.fill")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Signal quality
                VStack(alignment: .trailing, spacing: 4) {
                    if let rssi = aircraft.rssi {
                        Text(String(format: "%.1f dB", rssi))
                            .font(.caption)
                            .foregroundColor(signalColor(rssi: rssi))
                    }
                    
                    Image(systemName: signalIcon)
                        .foregroundColor(signalColor(rssi: aircraft.rssi ?? -100))
                        .font(.caption)
                    
                    // Data age indicator
                    if aircraft.isStale {
                        Text("Stale")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        if aircraft.isEmergency {
            return .red
        } else if aircraft.isStale {
            return .orange
        } else {
            return .green
        }
    }
    
    private var aircraftIcon: String {
        if aircraft.isOnGround {
            return "airplane.arrival"
        } else if let vr = aircraft.verticalRate {
            if vr > 500 {
                return "airplane.departure"
            } else if vr < -500 {
                return "airplane.arrival"
            }
        }
        return "airplane"
    }
    
    private var signalIcon: String {
        guard let rssi = aircraft.rssi else { return "antenna.radiowaves.left.and.right.slash" }
        
        switch rssi {
        case -10...0:
            return "antenna.radiowaves.left.and.right"
        case -20..<(-10):
            return "antenna.radiowaves.left.and.right"
        case -30..<(-20):
            return "wifi"
        default:
            return "wifi.slash"
        }
    }
    
    private func signalColor(rssi: Double) -> Color {
        switch rssi {
        case -10...0: return .green
        case -20..<(-10): return .blue
        case -30..<(-20): return .yellow
        default: return .red
        }
    }
    
    private func formatCoordinate(_ lat: Double, _ lon: Double) -> String {
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.4f°%@ %.4f°%@", abs(lat), latDir, abs(lon), lonDir)
    }
}

// MARK: - Aircraft Detail View

struct AircraftDetailContent: View {
    let aircraft: Aircraft
    @State private var showOnMap = false
    
    var body: some View {
        List {
            // Header section with map
            Section {
                if let coord = aircraft.coordinate {
                    Map(position: .constant(.region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )))) {
                        Annotation(aircraft.displayName, coordinate: coord) {
                            Image(systemName: "airplane")
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Circle().fill(.white))
                                .shadow(radius: 2)
                        }
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                }
            }
            
            // Identity section
            Section("Identity") {
                DetailRow(label: "ICAO", value: aircraft.hex.uppercased())
                if let callsign = aircraft.flight?.trimmingCharacters(in: .whitespaces) {
                    DetailRow(label: "Callsign", value: callsign)
                }
                if let squawk = aircraft.squawk {
                    DetailRow(label: "Squawk", value: squawk)
                }
                if let category = aircraft.category {
                    DetailRow(label: "Category", value: category)
                }
            }
            
            // Position section
            if let coord = aircraft.coordinate {
                Section("Position") {
                    DetailRow(label: "Latitude", value: String(format: "%.6f°", coord.latitude))
                    DetailRow(label: "Longitude", value: String(format: "%.6f°", coord.longitude))
                    
                    if let alt = aircraft.altitudeFeet {
                        DetailRow(label: "Altitude (Baro)", value: "\(alt) ft")
                    }
                    if let altGeom = aircraft.altitudeGeom {
                        DetailRow(label: "Altitude (GNSS)", value: "\(Int(altGeom)) ft")
                    }
                    
                    DetailRow(label: "On Ground", value: aircraft.isOnGround ? "Yes" : "No")
                }
            }
            
            // Velocity section
            Section("Velocity") {
                if let speed = aircraft.speedKnots {
                    DetailRow(label: "Ground Speed", value: "\(speed) kts")
                }
                if let track = aircraft.track {
                    DetailRow(label: "Track", value: String(format: "%.1f°", track))
                }
                if let vr = aircraft.verticalRate {
                    DetailRow(label: "Vertical Rate", value: "\(vr) ft/min")
                }
                if let ias = aircraft.ias {
                    DetailRow(label: "IAS", value: "\(ias) kts")
                }
                if let tas = aircraft.tas {
                    DetailRow(label: "TAS", value: "\(tas) kts")
                }
            }
            
            // Signal section
            Section("Signal Quality") {
                if let rssi = aircraft.rssi {
                    DetailRow(label: "RSSI", value: String(format: "%.1f dBFS", rssi))
                }
                if let messages = aircraft.messages {
                    DetailRow(label: "Messages", value: "\(messages)")
                }
                if let seen = aircraft.seen {
                    DetailRow(label: "Last Seen", value: String(format: "%.1f sec ago", seen))
                }
                if let seenPos = aircraft.seenPos {
                    DetailRow(label: "Last Position", value: String(format: "%.1f sec ago", seenPos))
                }
            }
            
            // Accuracy section
            if aircraft.nacp != nil || aircraft.nacv != nil || aircraft.sil != nil {
                Section("Accuracy") {
                    if let nacp = aircraft.nacp {
                        DetailRow(label: "NAC-P", value: "\(nacp)")
                    }
                    if let nacv = aircraft.nacv {
                        DetailRow(label: "NAC-V", value: "\(nacv)")
                    }
                    if let sil = aircraft.sil {
                        DetailRow(label: "SIL", value: "\(sil)")
                    }
                    if let silType = aircraft.silType {
                        DetailRow(label: "SIL Type", value: silType)
                    }
                }
            }
            
            // Emergency status
            if aircraft.isEmergency {
                Section("Status") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Emergency: \(aircraft.emergency ?? "Unknown")")
                            .foregroundColor(.red)
                            .font(.headline)
                    }
                }
            }
        }
        .navigationTitle(aircraft.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Legacy wrapper for backwards compatibility
struct AircraftDetailView: View {
    let aircraft: Aircraft
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            AircraftDetailContent(aircraft: aircraft)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// Helper view for detail rows
private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    let sampleAircraft = Aircraft(
        hex: "A12345",
        lat: 37.7749,
        lon: -122.4194,
        altitude: 35000,
        track: 270,
        groundSpeed: 450,
        flight: "UAL123",
        squawk: "1200",
        rssi: -15.5
    )
    
    return List {
        AircraftRow(aircraft: sampleAircraft)
    }
}
