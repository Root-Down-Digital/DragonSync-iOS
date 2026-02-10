//
//  MessageRow.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import MapKit

@MainActor
private final class EditorStateStore: ObservableObject {
    static let shared = EditorStateStore()
    @Published var editingSessions: [String: EditingData] = [:]
    
    struct EditingData {
        var name: String
        var trust: DroneSignature.UserDefinedInfo.TrustStatus
    }
}

private struct DroneInfoEditorSheet: View {
    let droneId: String
    @Binding var isPresented: Bool
    @StateObject private var store = EditorStateStore.shared
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Drone Name", text: Binding(
                    get: { store.editingSessions[droneId]?.name ?? "" },
                    set: { newName in
                        if var session = store.editingSessions[droneId] {
                            session.name = newName
                            store.editingSessions[droneId] = session
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.appDefault)
                .padding(.bottom, 8)
                .autocorrectionDisabled()
                
                Text("Trust Status")
                    .font(.appSubheadline)
                    .padding(.bottom, 4)
                
                HStack(spacing: 16) {
                    TrustButton(
                        title: "Trusted",
                        icon: "checkmark.shield.fill",
                        color: .green,
                        isSelected: store.editingSessions[droneId]?.trust == .trusted,
                        action: {
                            if var session = store.editingSessions[droneId] {
                                session.trust = .trusted
                                store.editingSessions[droneId] = session
                            }
                        }
                    )
                    
                    TrustButton(
                        title: "Unknown",
                        icon: "shield.fill",
                        color: .gray,
                        isSelected: store.editingSessions[droneId]?.trust == .unknown,
                        action: {
                            if var session = store.editingSessions[droneId] {
                                session.trust = .unknown
                                store.editingSessions[droneId] = session
                            }
                        }
                    )
                    
                    TrustButton(
                        title: "Untrusted",
                        icon: "xmark.shield.fill",
                        color: .red,
                        isSelected: store.editingSessions[droneId]?.trust == .untrusted,
                        action: {
                            if var session = store.editingSessions[droneId] {
                                session.trust = .untrusted
                                store.editingSessions[droneId] = session
                            }
                        }
                    )
                }
                .padding(.bottom, 16)
                
                Button(action: saveChanges) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Drone Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .onAppear {
            if store.editingSessions[droneId] == nil {
                let encounter = DroneStorageManager.shared.encounters[droneId]
                store.editingSessions[droneId] = EditorStateStore.EditingData(
                    name: encounter?.customName ?? "",
                    trust: encounter?.trustStatus ?? .unknown
                )
            }
        }
    }
    
    private func saveChanges() {
        if let session = store.editingSessions[droneId] {
            DroneStorageManager.shared.updateDroneInfo(
                id: droneId,
                name: session.name,
                trustStatus: session.trust
            )
        }
        store.editingSessions.removeValue(forKey: droneId)
        isPresented = false
    }
}

struct MessageRow: View, Equatable {
    let message: CoTViewModel.CoTMessage
    let cotViewModel: CoTViewModel
    let isCompact: Bool
    @State private var droneEncounter: DroneEncounter?
    @State private var droneSignature: DroneSignature?
    @State private var activeSheet: SheetType?
    @State private var showingSaveConfirmation = false
    @State private var showingInfoEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var editorDroneId: String = ""
    
    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message.uid == rhs.message.uid && lhs.isCompact == rhs.isCompact
    }
    @State private var showingSaveConfirmation = false
    @State private var showingInfoEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var editorDroneId: String = "" // Store drone ID for editor separately
    
    init(message: CoTViewModel.CoTMessage, cotViewModel: CoTViewModel, isCompact: Bool = false) {
        self.message = message
        self.cotViewModel = cotViewModel
        self.isCompact = isCompact
        _droneEncounter = State(initialValue: DroneStorageManager.shared.encounters[message.uid])
        _droneSignature = State(initialValue: cotViewModel.droneSignatures.first(where: { $0.primaryId.id == message.uid }))
        _editorDroneId = State(initialValue: message.uid) // Initialize with current ID
    }
    
    enum SheetType: Identifiable {
        case liveMap
        case detailView
        
        var id: Int { hashValue }
    }
    
    //MARK - FPV
    private var displayRSSI: String {
        if message.isFPVDetection {
            return message.fpvSignalStrengthFormatted
        } else if let rssi = getRSSI() {
            if rssi > 1000 {
                // MDN-style values
                return String(format: "%.0f", rssi)
            } else {
                // Standard dBm values
                return String(format: "%.0f dBm", rssi)
            }
        }
        return "Unknown"
    }

    private var displayName: String {
        if message.isFPVDetection {
            return message.fpvDisplayName
        }
        return message.description.isEmpty ? "Unnamed Drone" : message.description
    }

    private var displayDetails: String {
        if message.isFPVDetection {
            return message.fpvFrequencyFormatted
        }
        
        // Regular drone details
        var details: [String] = []
        
        if let mac = getMAC() {
            details.append(mac)
        }
        
        if message.speed != "0.0" && !message.speed.isEmpty {
            details.append("\(message.speed) m/s")
        }
        
        return details.joined(separator: " • ")
    }
    
    // MARK: - Helper Properties
    
    private var currentEncounter: DroneEncounter? {
        droneEncounter  // Use cached value
    }
    
    private var signature: DroneSignature? {
        droneSignature  // Use cached value
    }
    
    private func removeDroneFromTracking() {
        // Get all possible ID variants for this drone
        let baseId = message.uid.replacingOccurrences(of: "drone-", with: "")
        let droneId = message.uid.hasPrefix("drone-") ? message.uid : "drone-\(message.uid)"
        
        let idsToRemove = [
            message.uid,
            droneId,
            baseId,
            "drone-\(baseId)"
        ]
        
        // Remove from active messages - use both ID and UID matching
        cotViewModel.parsedMessages.removeAll { msg in
            return idsToRemove.contains(msg.uid) || idsToRemove.contains(msg.id) || msg.uid.contains(baseId)
        }
        
        // Remove signatures for all ID variants
        cotViewModel.droneSignatures.removeAll { signature in
            return idsToRemove.contains(signature.primaryId.id)
        }
        
        // Remove MAC history for all ID variants
        for id in idsToRemove {
            cotViewModel.macIdHistory.removeValue(forKey: id)
            cotViewModel.macProcessing.removeValue(forKey: id)
        }
        
        // Remove any alert rings for all ID variants
        cotViewModel.alertRings.removeAll { ring in
            return idsToRemove.contains(ring.droneId)
        }
        
        // Mark this device as "do not track" in storage for all possible ID formats
        for id in idsToRemove {
            DroneStorageManager.shared.markAsDoNotTrack(id: id)
        }
        
        // Force immediate UI update
        cotViewModel.objectWillChange.send()
        
        print("Stopped tracking drone with IDs: \(idsToRemove)")
    }
    
    private func deleteDroneFromStorage() {
        let baseId = message.uid.replacingOccurrences(of: "drone-", with: "")
        let possibleIds = [
            message.uid,
            "drone-\(message.uid)",
            baseId,
            "drone-\(baseId)"
        ]
        for id in possibleIds {
            DroneStorageManager.shared.deleteEncounter(id: id)
        }
    }

    // No longer needed - removed findEncounterForID
    // MARK: - Helper Methods
    
    private func rssiColor(_ rssi: Double) -> Color {
        // FPV RX5808 RSSI Pin
        if rssi >= 1000 {
            switch rssi {
            case 1000..<2000: return .red    // Weak signal
            case 2000..<2800: return .yellow // Medium signal
            case 2800...3500: return .green  // Strong signal
            default: return .gray
            }
        }
        
        // Handle standard drone dBm
        switch rssi {
        case ..<(-75): return .red
        case -75..<(-50): return .yellow
        case 0...0: return .red
        default: return .green
        }
    }
    
    private func getRSSI() -> Double? {
        // First check signal sources for strongest RSSI
        if !message.signalSources.isEmpty {
            let strongestSource = message.signalSources.max(by: { $0.rssi < $1.rssi })
            if let rssi = strongestSource?.rssi {
                return Double(rssi)
            }
        }
        
        // Get RSSI from transmission info
        if let signature = signature, let rssi = signature.transmissionInfo.signalStrength {
            return rssi
        }
        
        // Fallback to raw message parsing
        if let basicId = message.rawMessage["Basic ID"] as? [String: Any] {
            if let rssi = basicId["RSSI"] as? Double {
                return rssi
            }
            if let rssi = basicId["rssi"] as? Double {
                return rssi
            }
        }
        
        if let auxAdvInd = message.rawMessage["AUX_ADV_IND"] as? [String: Any],
           let rssi = auxAdvInd["rssi"] as? Double {
            return rssi
        }
        
        if let rssi = message.rssi {
            return Double(rssi)
        }
        
        // Check remarks field for RSSI
        if let details = message.rawMessage["detail"] as? [String: Any],
           let remarks = details["remarks"] as? String,
           let match = remarks.firstMatch(of: /RSSI[: ]*(-?\d+)/) {
            return Double(match.1)
        }
        
        return nil
    }
    
    private func getMAC() -> String? {
        // Function to validate MAC format
        func isValidMAC(_ mac: String) -> Bool {
            return mac.range(of: "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", options: .regularExpression) != nil
        }
        
        // Check signature for MAC
        if let signature = signature,
           let mac = signature.transmissionInfo.macAddress,
           isValidMAC(mac) {
            return mac
        }
        
        // Check Basic ID in raw message
        if let basicId = message.rawMessage["Basic ID"] as? [String: Any] {
            if let mac = basicId["MAC"] as? String, isValidMAC(mac) {
                return mac
            }
            if let mac = basicId["mac"] as? String, isValidMAC(mac) {
                return mac
            }
        }
        
        // Check AUX_ADV_IND in raw message
        if let auxAdvInd = message.rawMessage["AUX_ADV_IND"] as? [String: Any],
           let mac = auxAdvInd["mac"] as? String,
           isValidMAC(mac) {
            return mac
        }
        
        // Check remarks field for MAC address
        if let details = message.rawMessage["detail"] as? [String: Any],
           let remarks = details["remarks"] as? String {
            if let match = remarks.firstMatch(of: /MAC[: ]*([0-9a-fA-F:]+)/),
               isValidMAC(String(match.1)) {
                return String(match.1)
            }
        }
        
        return nil
    }
    
    // MARK: - Subview Builders
    
    @ViewBuilder
    private func headerView() -> some View {
        HStack {
            let customName = currentEncounter?.customName ?? ""
            let trustStatus = currentEncounter?.trustStatus ?? .unknown
            
            VStack(alignment: .leading) {
                if !customName.isEmpty {
                    Text(customName)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text(message.id)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.primary)
                        .onAppear {
                            print("Displaying drone: ID=\(message.id), UID=\(message.uid)")
                        }
                }
                
                if let caaReg = message.caaRegistration, !caaReg.isEmpty {
                    Text("CAA ID: \(caaReg)")
                        .font(.appSubheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Status indicator
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(message.statusColor)
                            .frame(width: 8, height: 8)
                        Text(message.statusDescription)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(message.statusColor)
                    }
                    
                    Image(systemName: trustStatus.icon)
                        .foregroundColor(trustStatus.color)
                        .font(.system(size: 18))
                }
                
                // Add FAA lookup button if we have the necessary IDs
                if message.idType.contains("Serial Number") ||
                    message.idType.contains("ANSI") ||
                    message.idType.contains("CTA-2063-A") {
                    FAALookupButton(mac: message.mac, remoteId: message.uid.replacingOccurrences(of: "drone-", with: ""))
                }
                
                Menu {
                    Button(action: { 
                        editorDroneId = message.uid // Capture ID before opening
                        showingInfoEditor = true 
                    }) {
                        Label("Edit Info", systemImage: "pencil")
                    }
                    
                    Button(action: { activeSheet = .liveMap }) {
                        Label("Live Map", systemImage: "map")
                    }
                    
                   
                    
                    Divider()
                    
                    Button(action: {
                        removeDroneFromTracking()
                    }) {
                        Label("Stop Tracking", systemImage: "eye.slash")
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    @ViewBuilder
    private func typeInfoView() -> some View {
        Text("Type: \(message.type)")
            .font(.appSubheadline)
    }
    
    @ViewBuilder
    private func signalSourcesView() -> some View {
        if !message.signalSources.isEmpty {
            VStack(alignment: .leading) {
                // Sort by timestamp (most recent first)
                let sortedSources = message.signalSources.sorted(by: { $0.timestamp > $1.timestamp })
                
                ForEach(sortedSources, id: \.self) { source in
                    signalSourceRow(source)
                }
            }
        } else if let rssi = getRSSI() {
            // Fallback for messages without signal sources
            HStack(spacing: 8) {
                Label("\(Int(rssi))dBm", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.appCaption)
                    .fontWeight(.bold)
                    .foregroundColor(rssiColor(rssi))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .background(rssiColor(rssi).opacity(0.1))
            }
        }
    }
    
    private func signalSourceRow(_ source: CoTViewModel.SignalSource) -> some View {
        let iconName: String
        let iconColor: Color
        
        // Determine icon and color based on source type
        switch source.type {
        case .bluetooth:
            iconName = "antenna.radiowaves.left.and.right.circle"
            iconColor = .blue
        case .wifi:
            iconName = "wifi.circle"
            iconColor = .green
        case .sdr:
            iconName = "dot.radiowaves.left.and.right"
            iconColor = .purple
        case .fpv:
            iconName = "antenna.radiowaves.left.and.right"
            iconColor = .orange
        default:
            iconName = "questionmark.circle"
            iconColor = .gray
        }
        
        return HStack {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading) {
                HStack {
                    Text(source.mac)
                        .font(.appCaption)
                    Text(source.type.rawValue)
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("\(source.rssi) dBm")
                        .font(.appCaption)
                        .fontWeight(.bold)
                        .foregroundColor(rssiColor(Double(source.rssi)))
                    Spacer()
                    Text(source.timestamp.formatted(.relative(presentation: .numeric)))
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .background(rssiColor(Double(source.rssi)).opacity(0.1))
        .cornerRadius(6)
        .id("\(source.mac)-\(source.timestamp.timeIntervalSince1970)")
    }
    
    @ViewBuilder
    private func macRandomizationView() -> some View {
        if let macs = cotViewModel.macIdHistory[message.uid], macs.count > 2 {
            let macCount = macs.count
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("MAC randomizing")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text("(\(macCount > 10 ? "10+" : String(macCount)) MACs)")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                
                if cotViewModel.macProcessing[message.uid] == true {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.yellow)
                        .help("Random MAC addresses detected")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.1))
        }
    }
    
    @ViewBuilder
    private func mapSectionView() -> some View {
        if message.isFPVDetection {
            // Try to get alert ring first, otherwise use message coordinate
            if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }),
               !(ring.centerCoordinate.latitude == 0 && ring.centerCoordinate.longitude == 0) {
                // FPV with valid alert ring - use fixed position to prevent auto-zoom
                VStack(alignment: .leading, spacing: 0) {
                    // Quick preview label
                    HStack {
                        Text("Signal Range Map")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            activeSheet = .detailView
                        }) {
                            HStack(spacing: 4) {
                                Text("Quick View")
                                    .font(.caption2)
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.05))
                    
                    Map(position: .constant(.camera(MapCamera(
                        centerCoordinate: ring.centerCoordinate,
                        distance: ring.radius * 3 // 3x the radius for good viewing
                    ))), interactionModes: [.pan, .zoom]) {
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .foregroundStyle(.orange.opacity(0.1))
                            .stroke(.orange, lineWidth: 2)
                        
                        Annotation("Monitor", coordinate: ring.centerCoordinate) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                                .font(.title2)
                                .background(Circle().fill(.white))
                        }
                        
                        Annotation("FPV \(message.fpvFrequency ?? 0)MHz", coordinate: ring.centerCoordinate) {
                            VStack {
                                Text("FPV Signal")
                                    .font(.caption)
                                Text("\(Int(ring.radius))m radius")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .frame(height: 150)
                }
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange, lineWidth: 1)
                )
                .allowsHitTesting(true)
            } else if let coord = message.coordinate, !(coord.latitude == 0 && coord.longitude == 0) {
                // FPV detection with coordinate (from user's location) but no alert ring
                VStack(alignment: .leading, spacing: 0) {
                    // Quick preview label
                    HStack {
                        Text("Signal Location Map")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            activeSheet = .detailView
                        }) {
                            HStack(spacing: 4) {
                                Text("Quick View")
                                    .font(.caption2)
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.05))
                    
                    Map(position: .constant(.camera(MapCamera(
                        centerCoordinate: coord,
                        distance: 500
                    ))), interactionModes: [.pan, .zoom]) {
                        Annotation("FPV \(message.fpvFrequency ?? 0)MHz", coordinate: coord) {
                            VStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                                    .background(Circle().fill(.white).frame(width: 30, height: 30))
                                Text("FPV Signal")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .frame(height: 150)
                }
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange, lineWidth: 1)
                )
                .allowsHitTesting(true)
            } else {
                // No location data available for FPV
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            Text(message.fpvDisplayName)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("No location data")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .frame(height: 80)
            }
        } else {
            let encounter = DroneStorageManager.shared.encounters[message.uid]
            
            let validCoordinate: CLLocationCoordinate2D? = {
                guard let coord = message.coordinate else { return nil }
                guard coord.latitude != 0 || coord.longitude != 0 else { return nil }
                return coord
            }()
            
            // Filter out 0/0 coordinates from flight path
            let flightCoords: [CLLocationCoordinate2D] = {
                var coords = encounter?.flightPath.compactMap { point -> CLLocationCoordinate2D? in
                    let coord = point.coordinate
                    guard coord.latitude != 0 || coord.longitude != 0 else { return nil }
                    return coord
                } ?? []
                
                if let currentCoord = validCoordinate,
                   !coords.contains(where: { coord in
                       abs(coord.latitude - currentCoord.latitude) < 0.00001 &&
                       abs(coord.longitude - currentCoord.longitude) < 0.00001
                   }) {
                    coords.append(currentCoord)
                }
                
                return coords
            }()
            
            let pilotCoordinate: CLLocationCoordinate2D? = {
                guard let pilotLatStr = encounter?.metadata["pilotLat"],
                      let pilotLonStr = encounter?.metadata["pilotLon"],
                      let pilotLat = Double(pilotLatStr),
                      let pilotLon = Double(pilotLonStr),
                      pilotLat != 0 || pilotLon != 0 else {
                    return nil
                }
                return CLLocationCoordinate2D(latitude: pilotLat, longitude: pilotLon)
            }()
            
            let takeoffCoordinate: CLLocationCoordinate2D? = {
                guard let homeLatStr = encounter?.metadata["homeLat"],
                      let homeLonStr = encounter?.metadata["homeLon"],
                      let homeLat = Double(homeLatStr),
                      let homeLon = Double(homeLonStr),
                      homeLat != 0 || homeLon != 0 else {
                    return nil
                }
                return CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)
            }()
            
            let centerCoordinate = validCoordinate ?? pilotCoordinate ?? takeoffCoordinate
            
            if let center = centerCoordinate {
                Map(position: .constant(.camera(MapCamera(
                    centerCoordinate: center,
                    distance: 500
                ))), interactionModes: [.pan, .zoom]) {
                    // Flight path - only use valid coordinates
                    if flightCoords.count > 1 {
                        MapPolyline(coordinates: flightCoords)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    
                    if let coordinate = validCoordinate {
                        Annotation(message.uid, coordinate: coordinate) {
                            Image(systemName: "airplane")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .rotationEffect(.degrees(message.headingDeg - 90))
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    if let pilotCoordinate = pilotCoordinate {
                        Annotation("Pilot", coordinate: pilotCoordinate) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.orange)
                                .background(Circle().fill(.white))
                        }
                    }
                    
                    if let takeoffCoordinate = takeoffCoordinate {
                        Annotation("Takeoff", coordinate: takeoffCoordinate) {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.green)
                                .background(Circle().fill(.white))
                        }
                    }
                }
                .mapStyle(.standard)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .frame(height: 150)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .allowsHitTesting(true)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "airplane.circle")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            Text(message.id)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("No location data")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .frame(height: 80)
            }
        }
    }
    
    @ViewBuilder
    private func detailsView() -> some View {
        Group {
            if message.isFPVDetection {
                // FPV specific details
                if let frequency = message.fpvFrequency {
                    Text("Frequency: \(frequency) MHz")
                }
                if let bandwidth = message.fpvBandwidth, !bandwidth.isEmpty {
                    Text("Bandwidth: \(bandwidth)")
                }
                if let source = message.fpvSource {
                    Text("Source: \(source)")
                }
                if let fpvRSSI = message.fpvRSSI {
                    Text("Signal Strength: \(String(format: "%.1f", fpvRSSI))")
                }
            } else {
                // Regular drone details (existing code)
                if message.lat != "0.0" {
                    Text("Position: \(message.lat), \(message.lon)")
                }
                if message.alt != "0.0" {
                    if let formattedAlt = message.formattedAltitude {
                        if let formattedHeight = message.formattedHeight {
                            Text("Altitude: \(formattedAlt) • AGL: \(formattedHeight)")
                        } else {
                            Text("Altitude: \(formattedAlt)")
                        }
                    } else if let altValue = Double(message.alt) {
                        if let formattedHeight = message.formattedHeight {
                            Text("Altitude: \(String(format: "%.1f", altValue))m • AGL: \(formattedHeight)")
                        } else {
                            Text("Altitude: \(String(format: "%.1f", altValue))m")
                        }
                    } else {
                        if let formattedHeight = message.formattedHeight {
                            Text("Altitude: \(message.alt)m • AGL: \(formattedHeight)")
                        } else {
                            Text("Altitude: \(message.alt)m")
                        }
                    }
                }
                if message.speed != "0.0" {
                    Text("Speed: \(message.speed)m/s")
                }
                if message.pilotLat != "0.0" {
                    Text("Pilot Location: \(message.pilotLat), \(message.pilotLon)")
                }
                if message.homeLat != "0.0" {
                    Text("Takeoff Location: \(message.homeLat), \(message.homeLon)")
                }
                if let mac = message.mac, !mac.isEmpty {
                    Text("MAC: \(mac)")
                }
                if message.operator_id != "" {
                    Text("Operator ID: \(message.operator_id ?? "")")
                }
                if let manufacturer = message.manufacturer, manufacturer != "Unknown" {
                    Text("Manufacturer: \(manufacturer)")
                }
            }
        }
        .font(.appCaption)
        .foregroundColor(.primary)
    }
    
    @ViewBuilder
    private func spoofDetectionView() -> some View {
        if message.isSpoofed, let details = message.spoofingDetails {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Possible Spoofed Signal")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(String(format: "Confidence: %.0f%%", details.confidence * 100))
                        .foregroundColor(.primary)
                }
                
                ForEach(details.reasons, id: \.self) { reason in
                    Text("• \(reason)")
                        .font(.appCaption)
                        .foregroundColor(.primary)
                }
            }
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Main View
    
    var body: some View {
        if isCompact {
            compactView
        } else {
            expandedView
        }
    }
    
    private var compactView: some View {
        Button(action: {
            activeSheet = .detailView
        }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(message.statusColor)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(message.id)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if let customName = currentEncounter?.customName, !customName.isEmpty {
                            Text("(\(customName))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let rssi = getRSSI() {
                            HStack(spacing: 4) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption2)
                                    .foregroundColor(rssiColor(rssi))
                                Text("\(Int(rssi)) dBm")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(rssiColor(rssi))
                            }
                        }
                        
                        if message.alt != "0.0", let alt = Double(message.alt) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text("\(Int(alt))m")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if message.speed != "0.0", let speed = Double(message.speed) {
                            HStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text(String(format: "%.1f m/s", speed))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: (currentEncounter?.trustStatus ?? .unknown).icon)
                        .foregroundColor((currentEncounter?.trustStatus ?? .unknown).color)
                        .font(.system(size: 16))
                    
                    Text(message.lastUpdated.formatted(.relative(presentation: .numeric)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(message.uid)
        .contextMenu {
            contextMenuItems
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            swipeActionItems
        }
        .onAppear {
            updateEncounterData()
        }
        .onReceive(DroneStorageManager.shared.objectWillChange) { _ in
            // Don't update while user is editing info - prevents text field from clearing
            guard !showingInfoEditor else { return }
            updateEncounterData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DroneInfoUpdated"))) { notification in
            guard !showingInfoEditor else { return }
            if let droneId = notification.userInfo?["droneId"] as? String,
               droneId == message.uid {
                updateEncounterData()
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            sheetContent(for: sheetType)
        }
        .sheet(isPresented: $showingInfoEditor, onDismiss: {
            // Update the encounter data after the editor is dismissed
            // This ensures the UI reflects any changes made in the editor
            updateEncounterData()
        }) {
            DroneInfoEditorSheet(droneId: editorDroneId, isPresented: $showingInfoEditor)
        }
        .alert("Delete Drone", isPresented: $showingDeleteConfirmation) {
            deleteConfirmationButtons
        } message: {
            deleteConfirmationMessage
        }
    }
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // Tappable header section
                Button(action: {
                    activeSheet = .detailView
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        headerView()
                        typeInfoView()
                        signalSourcesView()
                        macRandomizationView()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Non-tappable map section (allows map interactions)
                mapSectionView()
                
                // Tappable details section
                Button(action: {
                    activeSheet = .detailView
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        detailsView()
                        spoofDetectionView()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .cornerRadius(8)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary, lineWidth: 3)
                    .padding(-8)
            )
        }
        .id(message.uid)
        .onAppear {
            updateEncounterData()
        }
        .onReceive(DroneStorageManager.shared.objectWillChange) { _ in
            guard !showingInfoEditor else { return }
            updateEncounterData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DroneInfoUpdated"))) { notification in
            guard !showingInfoEditor else { return }
            if let droneId = notification.userInfo?["droneId"] as? String,
               droneId == message.uid {
                updateEncounterData()
            }
        }
        .contextMenu {
            contextMenuItems
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            swipeActionItems
        }
        .sheet(item: $activeSheet) { sheetType in
            sheetContent(for: sheetType)
        }
        .sheet(isPresented: $showingInfoEditor, onDismiss: {
            // Update the encounter data after the editor is dismissed
            // This ensures the UI reflects any changes made in the editor
            updateEncounterData()
        }) {
            DroneInfoEditorSheet(droneId: editorDroneId, isPresented: $showingInfoEditor)
        }
        .alert("Delete Drone", isPresented: $showingDeleteConfirmation) {
            deleteConfirmationButtons
        } message: {
            deleteConfirmationMessage
        }
    }
    
    // MARK: - Helper Functions
    
    private func updateEncounterData() {
        // Don't update cached data while the editor sheet is open
        // This prevents the text fields from being cleared during editing
        guard !showingInfoEditor else { return }
        
        droneEncounter = DroneStorageManager.shared.encounters[message.uid]
        droneSignature = cotViewModel.droneSignatures.first(where: { $0.primaryId.id == message.uid })
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: {
            removeDroneFromTracking()
        }) {
            Label("Stop Tracking", systemImage: "eye.slash")
        }
        
        Button(role: .destructive, action: {
            showingDeleteConfirmation = true
        }) {
            Label("Delete from History", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private var swipeActionItems: some View {
        Button(role: .destructive) {
            removeDroneFromTracking()
            deleteDroneFromStorage()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        
        Button {
            removeDroneFromTracking()
        } label: {
            Label("Stop", systemImage: "eye.slash")
        }
        .tint(.orange)
    }
    
    @ViewBuilder
    private func sheetContent(for sheetType: SheetType) -> some View {
        switch sheetType {
        case .liveMap:
            NavigationStack {
                LiveMapView(cotViewModel: cotViewModel, initialMessage: message)
                    .navigationTitle("Live Drone Map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                activeSheet = nil
                            }
                        }
                    }
            }
        case .detailView:
            NavigationStack {
                DroneDetailView(
                    message: message,
                    flightPath: DroneStorageManager.shared
                        .encounters[message.uid]?.flightPath
                        .map { $0.coordinate } ?? [],
                    cotViewModel: cotViewModel
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            activeSheet = nil
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var deleteConfirmationButtons: some View {
        Button("Delete", role: .destructive) {
            removeDroneFromTracking()
            deleteDroneFromStorage()
        }
        Button("Cancel", role: .cancel) {}
    }
    
    private var deleteConfirmationMessage: some View {
        Text("Are you sure you want to delete this drone from tracking and history? This action cannot be undone.")
    }
}
