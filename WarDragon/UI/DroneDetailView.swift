//
//  DroneDetailView.swift
//  WarDragon
//
//  Created by Luke on 12/09/24.
//


import SwiftUI
import MapKit
import CoreLocation

struct DroneDetailView: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showingInfoEditor = false
    let message: CoTViewModel.CoTMessage
    let flightPath: [CLLocationCoordinate2D]
    
    init(message: CoTViewModel.CoTMessage, flightPath: [CLLocationCoordinate2D], cotViewModel: CoTViewModel) {
        self.cotViewModel = cotViewModel
        self.message = message
        self.flightPath = flightPath
    }

    //MARK: - Main Detail View

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    let encounter = DroneStorageManager.shared.encounters[message.uid]
                    let customName = encounter?.customName ?? ""
                    let trustStatus = encounter?.trustStatus ?? .unknown
                    
                    VStack(alignment: .leading) {
                        if !customName.isEmpty {
                            Text(customName)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        
                        
                        HStack {
                            Text(message.uid)
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                            
                            
                            Image(systemName: trustStatus.icon)
                                .foregroundColor(trustStatus.color)
                        }
                    }
                    
                    
                    Spacer()
                    
                    
                    Button(action: { showingInfoEditor = true }) {
                        Label("Edit", systemImage: "pencil")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                
                
                Map(position: $mapCameraPosition) {
                    if message.lat != "0.0" && message.lon != "0.0" {
                        Annotation(message.uid, coordinate: CLLocationCoordinate2D(
                            latitude: Double(message.lat) ?? 0,
                            longitude: Double(message.lon) ?? 0
                        )) {
                            Image(systemName: message.uaType.icon)
                                .foregroundStyle(.blue)
                        }
                    }
                    if flightPath.count > 1 {
                        MapPolyline(coordinates: flightPath)
                            .stroke(.blue, lineWidth: 2)
                    }
                    
                    
                    if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }),
                       Double(message.lat) ?? 0 == 0 && Double(message.lon) ?? 0 == 0 {
                        MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                            .foregroundStyle(.yellow.opacity(0.1))
                            .stroke(.yellow, lineWidth: 2)
                        
                        
                        Annotation("RSSI: \(ring.rssi) dBm", coordinate: ring.centerCoordinate) {
                            VStack {
                                Text("Encrypted Drone")
                                    .font(.caption)
                                Text("\(Int(ring.radius))m radius")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                    }
                    
                    
                    if message.pilotLat != "0.0" && message.pilotLon != "0.0" {
                        let pilotCoord = CLLocationCoordinate2D(
                            latitude: Double(message.pilotLat) ?? 0,
                            longitude: Double(message.pilotLon) ?? 0
                        )
                        Annotation("Operator", coordinate: pilotCoord) {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.green)
                        }
                    }
                    
                    
                    if message.homeLat != "0.0" && message.homeLon != "0.0" {
                        let homeCoord = CLLocationCoordinate2D(
                            latitude: Double(message.homeLat) ?? 0,
                            longitude: Double(message.homeLon) ?? 0
                        )
                        Annotation("Takeoff", coordinate: homeCoord) {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(height: 300)
                .cornerRadius(12)
                .font(.appDefault)
                .onAppear {
                    updateMapRegion()
                }
                .onChange(of: [message.lat, message.lon]) { oldValue, newValue in
                    updateMapRegion()
                }
                
                Group {
                    if !message.signalSources.isEmpty {
                        SectionHeader(title: "Signal Sources")
                        // Each type gets its own group
                        Group {
                            // Sort by signal strength within each type
                            let sortedSources = message.signalSources.sorted(by: { $0.rssi > $1.rssi })
                            ForEach(sortedSources, id: \.self) { source in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Image(systemName: source.type == .bluetooth ? "antenna.radiowaves.left.and.right.circle" :
                                                source.type == .wifi ? "wifi.circle" :
                                                source.type == .sdr ? "dot.radiowaves.left.and.right" :
                                                "questionmark.circle")
                                        .foregroundColor(source.type == .bluetooth ? .blue :
                                                            source.type == .wifi ? .green :
                                                            source.type == .sdr ? .purple :
                                                .gray)
                                        
                                        
                                        Text(source.type.rawValue)
                                            .font(.appCaption)
                                            .foregroundColor(source.type == .bluetooth ? .blue :
                                                                source.type == .wifi ? .green :
                                                                source.type == .sdr ? .purple :
                                                    .gray)
                                    }
                                    InfoRow(title: "MAC", value: source.mac)
                                    InfoRow(title: "RSSI", value: "\(source.rssi) dBm")
                                    InfoRow(title: "Last Seen", value: source.timestamp.formatted(date: .numeric, time: .standard))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(rssiColor(Double(source.rssi)).opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    
                    Group {
                        if let macs = cotViewModel.macIdHistory[message.uid], macs.count >= 3 {
                            SectionHeader(title: "MAC Randomization")
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text("Device using MAC randomization")
                                        .foregroundColor(.primary)
                                }
                                .padding(.bottom, 4)
                                
                                
                                Text("Last seen MACs:")
                                    .font(.appCaption)
                                    .foregroundColor(.secondary)
                                
                                
                                ForEach(Array(macs).sorted(), id: \.self) { mac in
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                        Text(mac)
                                            .font(.appCaption)
                                            .foregroundColor(mac == message.mac ? .primary : .secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    
                    Group {
                        InfoRow(title: "ID", value: message.uid)
                        if message.caaRegistration != nil {
                            InfoRow(title: "CAA Registration", value: message.caaRegistration ?? "")
                        }
                        if !message.description.isEmpty {
                            InfoRow(title: "Description", value: message.description)
                        }
                        if !message.selfIDText.isEmpty {
                            InfoRow(title: "Info", value: message.selfIDText)
                        }
                        
                        
                        if !message.uaType.rawValue.isEmpty {
                            InfoRow(title: "UA Type", value: message.uaType.rawValue)
                        }
                        
                        
                        // MAC from multiple sources
                        if let mac = message.mac ??
                            (message.rawMessage["Basic ID"] as? [String: Any])?["MAC"] as? String ??
                            (message.rawMessage["AUX_ADV_IND"] as? [String: Any])?["addr"] as? String {
                            InfoRow(title: "MAC", value: mac)
                        }
                        
                        
                        // RSSI from multiple sources
                        if let rssi = message.rssi ??
                            (message.rawMessage["Basic ID"] as? [String: Any])?["RSSI"] as? Int ??
                            (message.rawMessage["AUX_ADV_IND"] as? [String: Any])?["rssi"] as? Int {
                            InfoRow(title: "RSSI", value: "\(rssi) dBm")
                        }
                        
                        
                    }
                    
                    
                    // Operator Section
                    if message.pilotLat != "0.0" || ((message.operator_id?.isEmpty) == nil) || message.manufacturer != "Unknown" {
                        Group {
                            if message.manufacturer != "Unknown" {
                                InfoRow(title: "Manufacturer", value: message.manufacturer ?? "Unknown")
                            }
                            SectionHeader(title: "Operator")
                            if message.operator_id != "" {
                                InfoRow(title: "ID", value: message.operator_id ?? "Unknown")
                            }
                            if message.homeLat != "0.0" {
                                InfoRow(title: "Takeoff Location", value: "\(message.homeLat)/\(message.homeLon)")
                            }
                            if message.pilotLat != "0.0" {
                                InfoRow(title: "Pilot Location", value: "\(message.pilotLat)/\(message.pilotLon)")
                            }
                            if message.operatorAltGeo != nil {
                                InfoRow(title: "Pilot Altitude", value: message.operatorAltGeo ?? "")
                            }
                            
                            
                        }
                    }
                    
                    
                    Group {
                        SectionHeader(title: "Position")
                        InfoRow(title: "Latitude", value: message.lat)
                        InfoRow(title: "Longitude", value: message.lon)
                        InfoRow(title: "Altitude", value: "\(message.alt)m")
                        if let heightformatted = message.formattedHeight {
                            InfoRow(title: "Height", value: "\(heightformatted)m")
                        }
                        if let heightType = message.heightType {
                            InfoRow(title: "Height Type", value: heightType)
                            
                            
                        }
                        if message.op_status != "" {
                            InfoRow(title: "Operation Status", value: message.op_status ?? "Unknown")
                        }
                        
                        
                    }
                    
                    
                    Group {
                        if message.speed != "" {
                            SectionHeader(title: "Movement")
                            InfoRow(title: "E/W Direction", value: "\(message.ew_dir_segment ?? "")")
                            InfoRow(title: "Speed", value: "\(message.speed)m/s")
                            InfoRow(title: "Vertical Speed", value: "\(message.vspeed)m/s")
                        }
                        if let timeSpeed = message.timeSpeed {
                            InfoRow(title: "Time Speed", value: timeSpeed)
                        }
                    }
                    
                    
                    Group {
                        if let auxAdvData = message.rawMessage.lazy
                            .compactMap({ $0.value as? [String: Any] })
                            .first(where: { $0.keys.contains("rssi") }) {
                            
                            
                            SectionHeader(title: "Signal Data")
                            
                            
                            if let rssi = auxAdvData["rssi"] as? Int {
                                InfoRow(title: "RSSI", value: "\(rssi) dBm")
                            }
                            
                            
                            if let channel = auxAdvData["chan"] as? Int {
                                InfoRow(title: "Channel", value: "\(channel)")
                            }
                            
                            
                            if let phy = auxAdvData["phy"] as? Int {
                                InfoRow(title: "PHY", value: "\(phy)")
                            }
                            
                            
                            if let aa = auxAdvData["aa"] as? Int {
                                InfoRow(title: "Access Address", value: String(format: "0x%08X", aa))
                            }
                        }
                    }
                    
                    
                    Group {
                        if message.horizAcc != nil || message.vertAcc != nil || message.baroAcc != nil || message.speedAcc != nil {
                            SectionHeader(title: "Accuracy")
                            
                            
                            if let horizAcc = message.horizAcc {
                                InfoRow(title: "Horizontal", value: "\(horizAcc)m")
                            }
                            if let vertAcc = message.vertAcc {
                                InfoRow(title: "Vertical", value: "\(vertAcc)m")
                            }
                            if let baroAcc = message.baroAcc {
                                InfoRow(title: "Barometric", value: "\(baroAcc)m")
                            }
                            if let speedAcc = message.speedAcc {
                                InfoRow(title: "Speed", value: "\(speedAcc)m/s")
                            }
                        }
                    }
                    

                    if let aux = message.rawMessage["AUX_ADV_IND"] as? [String: Any],
                       let aext = message.rawMessage["aext"] as? [String: Any] {
                        Group {
                            SectionHeader(title: "Transmission Data")
                            if let rssi = aux["rssi"] as? Int {
                                InfoRow(title: "Signal", value: "\(rssi) dBm")
                            }
                            if let channel = aux["chan"] as? Int {
                                InfoRow(title: "Channel", value: "\(channel)")
                            }
                            if let mode = aext["AdvMode"] as? String {
                                InfoRow(title: "Mode", value: mode)
                            }
                            if let addr = aext["AdvA"] as? String {
                                InfoRow(title: "Address", value: addr)
                            }
                            if let dataInfo = aext["AdvDataInfo"] as? [String: Any] {
                                if let did = dataInfo["did"] as? Int {
                                    InfoRow(title: "Data ID", value: "\(did)")
                                }
                                if let sid = dataInfo["sid"] as? Int {
                                    InfoRow(title: "Set ID", value: "\(sid)")
                                }
                            }
                        }
                    }
                    
                    
                    if let areaCount = message.areaCount, areaCount != "0" {
                        Group {
                            SectionHeader(title: "Operation Area")
                            InfoRow(title: "Count", value: areaCount)
                            if let radius = message.areaRadius {
                                InfoRow(title: "Radius", value: "\(radius)m")
                            }
                            if let ceiling = message.areaCeiling {
                                InfoRow(title: "Ceiling", value: "\(ceiling)m")
                            }
                            if let floor = message.areaFloor {
                                InfoRow(title: "Floor", value: "\(floor)m")
                            }
                        }
                    }
                    
                    
                    if let status = message.status {
                        Group {
                            SectionHeader(title: "System Status")
                            InfoRow(title: "Status Code", value: status)
                            if let classification = message.classification {
                                InfoRow(title: "Classification", value: classification)
                            }
                        }
                    }
                }
                
                // Transmission data section
                if let aux = message.rawMessage["AUX_ADV_IND"] as? [String: Any],
                   let aext = message.rawMessage["aext"] as? [String: Any] {
                    DroneTransmissionSection(aux: aux, aext: aext)
                }
                
                // Operation area section
                if let areaCount = message.areaCount, areaCount != "0" {
                    DroneOperationAreaSection(message: message)
                }
                
                // System status section
                if let status = message.status {
                    DroneSystemStatusSection(message: message, status: status)
                }
            }
            .navigationTitle("Drone Details")
            .font(.appSubheadline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        let lat = Double(message.lat) ?? 0
                        let lon = Double(message.lon) ?? 0
                        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        mapItem.name = message.uid
                        mapItem.openInMaps()
                    }) {
                        Image(systemName: "map")
                    }
                }
            }
        }
        .sheet(isPresented: $showingInfoEditor) {
            NavigationView {
                DroneInfoEditor(droneId: message.uid)
                    .navigationTitle("Edit Drone Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingInfoEditor = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            updateMapRegion()
        }
    }
    
    
    struct InfoRow: View {
        let title: String
        let value: String
        
        
        var body: some View {
            HStack {
                Text(title)
                    .font(.appHeadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.appCaption)
                    .foregroundColor(.primary)
            }
        }
    }
    
    
    struct SectionHeader: View {
        let title: String
        
        
        var body: some View {
            Text(title)
                .font(.appHeadline)
                .padding(.top, 8)
        }
    }
    
    struct DronePositionSection: View {
        let message: CoTViewModel.CoTMessage
        
        var body: some View {
            Group {
                SectionHeader(title: "Position")
                InfoRow(title: "Latitude", value: message.lat)
                InfoRow(title: "Longitude", value: message.lon)
                InfoRow(title: "Altitude", value: "\(message.alt)m")
                
                if let heightformatted = message.formattedHeight {
                    InfoRow(title: "Height", value: heightformatted)
                }
                
                if let heightType = message.heightType {
                    InfoRow(title: "Height Type", value: heightType)
                }
                
                if message.op_status != "" {
                    InfoRow(title: "Operation Status", value: message.op_status ?? "Unknown")
                }
            }
        }
    }

    struct DroneMovementSection: View {
        let message: CoTViewModel.CoTMessage
        
        var body: some View {
            Group {
                SectionHeader(title: "Movement")
                InfoRow(title: "E/W Direction", value: "\(message.ew_dir_segment ?? "")")
                InfoRow(title: "Speed", value: "\(message.speed)m/s")
                InfoRow(title: "Vertical Speed", value: "\(message.vspeed)m/s")
                
                if let timeSpeed = message.timeSpeed {
                    InfoRow(title: "Time Speed", value: timeSpeed)
                }
            }
        }
    }

    struct DroneSignalDataSection: View {
        let auxAdvData: [String: Any]
        
        var body: some View {
            Group {
                SectionHeader(title: "Signal Data")
                
                if let rssi = auxAdvData["rssi"] as? Int {
                    InfoRow(title: "RSSI", value: "\(rssi) dBm")
                }
                
                if let channel = auxAdvData["chan"] as? Int {
                    InfoRow(title: "Channel", value: "\(channel)")
                }
                
                if let phy = auxAdvData["phy"] as? Int {
                    InfoRow(title: "PHY", value: "\(phy)")
                }
                
                if let aa = auxAdvData["aa"] as? Int {
                    InfoRow(title: "Access Address", value: String(format: "0x%08X", aa))
                }
            }
        }
    }

    struct DroneAccuracySection: View {
        let message: CoTViewModel.CoTMessage
        
        var body: some View {
            Group {
                SectionHeader(title: "Accuracy")
                
                if let horizAcc = message.horizAcc {
                    InfoRow(title: "Horizontal", value: "\(horizAcc)m")
                }
                
                if let vertAcc = message.vertAcc {
                    InfoRow(title: "Vertical", value: "\(vertAcc)m")
                }
                
                if let baroAcc = message.baroAcc {
                    InfoRow(title: "Barometric", value: "\(baroAcc)m")
                }
                
                if let speedAcc = message.speedAcc {
                    InfoRow(title: "Speed", value: "\(speedAcc)m/s")
                }
            }
        }
    }

    struct DroneTransmissionSection: View {
        let aux: [String: Any]
        let aext: [String: Any]
        
        var body: some View {
            Group {
                SectionHeader(title: "Transmission Data")
                
                if let rssi = aux["rssi"] as? Int {
                    InfoRow(title: "Signal", value: "\(rssi) dBm")
                }
                
                if let channel = aux["chan"] as? Int {
                    InfoRow(title: "Channel", value: "\(channel)")
                }
                
                if let mode = aext["AdvMode"] as? String {
                    InfoRow(title: "Mode", value: mode)
                }
                
                if let addr = aext["AdvA"] as? String {
                    InfoRow(title: "Address", value: addr)
                }
                
                if let dataInfo = aext["AdvDataInfo"] as? [String: Any] {
                    if let did = dataInfo["did"] as? Int {
                        InfoRow(title: "Data ID", value: "\(did)")
                    }
                    
                    if let sid = dataInfo["sid"] as? Int {
                        InfoRow(title: "Set ID", value: "\(sid)")
                    }
                }
            }
        }
    }

    struct DroneOperationAreaSection: View {
        let message: CoTViewModel.CoTMessage
        
        var body: some View {
            Group {
                SectionHeader(title: "Operation Area")
                InfoRow(title: "Count", value: message.areaCount ?? "")
                
                if let radius = message.areaRadius {
                    InfoRow(title: "Radius", value: "\(radius)m")
                }
                
                if let ceiling = message.areaCeiling {
                    InfoRow(title: "Ceiling", value: "\(ceiling)m")
                }
                
                if let floor = message.areaFloor {
                    InfoRow(title: "Floor", value: "\(floor)m")
                }
            }
        }
    }

    struct DroneSystemStatusSection: View {
        let message: CoTViewModel.CoTMessage
        let status: String
        
        var body: some View {
            Group {
                SectionHeader(title: "System Status")
                InfoRow(title: "Status Code", value: status)
                
                if let classification = message.classification {
                    InfoRow(title: "Classification", value: classification)
                }
            }
        }
    }
    
    //MARK: - Helper functions
    
    private func rssiColor(_ rssi: Double) -> Color {
        switch rssi {
        case ..<(-75): return .red
        case -75..<(-60): return .yellow
        case 0...0: return .red
        default: return .green
        }
    }
    
    private func updateMapRegion() {
        let lat = Double(message.lat) ?? 0
        let lon = Double(message.lon) ?? 0
        
        let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        
        // Proximity ring alert if 0/0
        if lat == 0 && lon == 0,
           let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }) {
            withAnimation {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: ring.centerCoordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: max(ring.radius / 1000 * 2, 0.01),
                        longitudeDelta: max(ring.radius / 1000 * 2, 0.01)
                    )
                ))
            }
        } else {
            withAnimation {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: defaultSpan
                ))
            }
        }
    }
    
    
    // MARK: - Section Components
    
    struct DroneHeaderSection: View {
        let message: CoTViewModel.CoTMessage
        @Binding var showingInfoEditor: Bool
        
        var body: some View {
            HStack {
                let encounter = DroneStorageManager.shared.encounters[message.uid]
                let customName = encounter?.customName ?? ""
                let trustStatus = encounter?.trustStatus ?? .unknown
                
                VStack(alignment: .leading) {
                    if !customName.isEmpty {
                        Text(customName)
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text(message.uid)
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: trustStatus.icon)
                            .foregroundColor(trustStatus.color)
                    }
                }
                
                Spacer()
                
                if message.idType.contains("Serial Number") {
                    FAALookupButton(mac: message.mac, remoteId: message.uid.replacingOccurrences(of: "drone-", with: ""))
                }
                
                Button(action: { showingInfoEditor = true }) {
                    Label("Edit", systemImage: "pencil")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}
