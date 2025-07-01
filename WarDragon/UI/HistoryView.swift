//
//  HistoryView.swift
//  WarDragon
//
//  Created by Luke on 1/21/25.
//

import Foundation
import UIKit
import SwiftUI
import MapKit

struct StoredEncountersView: View {
    @ObservedObject var storage = DroneStorageManager.shared
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .firstSeen
    @ObservedObject var cotViewModel: CoTViewModel
    
    enum SortOrder {
        case lastSeen, firstSeen, maxAltitude, maxSpeed
    }
    
    var sortedEncounters: [DroneEncounter] {
        // Get unique drones by MAC, falling back to ID
        let uniqueEncounters = Dictionary(grouping: storage.encounters.values) { encounter in
            encounter.metadata["mac"] ?? encounter.id
        }.values.map { encounters in
            encounters.max { $0.lastSeen < $1.lastSeen }!
        }
        
        // CAA ID handler
        let filtered = uniqueEncounters.filter { encounter in
            searchText.isEmpty ||
            encounter.id.localizedCaseInsensitiveContains(searchText) ||
            encounter.metadata["caaRegistration"]?.localizedCaseInsensitiveContains(searchText) ?? false
        }
        
        return filtered.sorted { first, second in
            switch sortOrder {
            case .lastSeen: return first.lastSeen > second.lastSeen
            case .firstSeen: return first.firstSeen < second.firstSeen
            case .maxAltitude: return first.maxAltitude > second.maxAltitude
            case .maxSpeed: return first.maxSpeed > second.maxSpeed
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedEncounters) { encounter in
                    NavigationLink(destination: EncounterDetailView(encounter: encounter)
                                      .environmentObject(cotViewModel)) {
                        EncounterRow(encounter: encounter)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        storage.deleteEncounter(id: sortedEncounters[index].id)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by ID or CAA Registration")
            .navigationTitle("Encounter History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            Text("Last Seen").tag(SortOrder.lastSeen)
                            Text("First Seen").tag(SortOrder.firstSeen)
                            Text("Max Altitude").tag(SortOrder.maxAltitude)
                            Text("Max Speed").tag(SortOrder.maxSpeed)
                        }
                        Button {
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first,
                               let rootVC = window.rootViewController {
                                storage.shareCSV(from: rootVC)
                            }
                        } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete All Encounters", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    storage.deleteAllEncounters()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    struct EncounterRow: View {
        let encounter: DroneEncounter
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Show custom/ID drone name
                    if !encounter.customName.isEmpty {
                        Text(encounter.customName)
                            .font(.appHeadline)
                            .foregroundColor(.primary)
                        
                        Text(ensureDronePrefix(encounter.id))
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(ensureDronePrefix(encounter.id))
                            .font(.appHeadline)
                    }
                    
                    if let caaReg = encounter.metadata["caaRegistration"] {
                        Text("CAA: \(caaReg)")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    
                    Image(systemName: "airplane")
                        .foregroundStyle(.blue)
                        .rotationEffect(.degrees(encounter.headingDeg))
                        .animation(.easeInOut(duration: 0.15),
                                   value: encounter.headingDeg)
                }
                
                if let mac = encounter.metadata["mac"] {
                    Text("MAC: \(mac)")
                        .font(.appCaption)
                }
                
                HStack {
                    Label("\(encounter.flightPath.count) points", systemImage: "map")
                    Label(String(format: "%.0fm", encounter.maxAltitude), systemImage: "arrow.up")
                    Label(String(format: "%.0fm/s", encounter.maxSpeed), systemImage: "speedometer")
                    if encounter.averageRSSI != 0 {
                        Label(String(format: "%.0fdB", encounter.averageRSSI),
                              systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
                
                Text("Duration: \(formatDuration(encounter.totalFlightTime))")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
//            if !encounter.macHistory.isEmpty && encounter.macHistory.count > 1 {
//                VStack(alignment: .leading) {
//                    Text("MAC RANDOMIZATION")
//                        .font(.appHeadline)
//                    ForEach(Array(encounter.macHistory).sorted(), id: \.self) { mac in
//                        Text(mac)
//                            .font(.appCaption)
//                    }
//                }
//                .padding()
//                .background(Color.yellow.opacity(0.1))
//                .cornerRadius(12)
//            }
        }
        
        private func formatDuration(_ time: TimeInterval) -> String {
            let hours = Int(time) / 3600
            let minutes = Int(time) % 3600 / 60
            let seconds = Int(time) % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        
        private func ensureDronePrefix(_ id: String) -> String {
                return id.hasPrefix("drone-") ? id : "drone-\(id)"
            }
    }
    
    struct EncounterDetailView: View {
        let encounter: DroneEncounter
        @Environment(\.dismiss) private var dismiss
        @StateObject private var storage = DroneStorageManager.shared
        @State private var showingDeleteConfirmation = false
        @State private var showingInfoEditor = false
        @State private var selectedMapType: MapStyle = .standard
        @State private var mapCameraPosition: MapCameraPosition = .automatic
        @EnvironmentObject var cotViewModel: CoTViewModel
        
        enum MapStyle {
            case standard, satellite, hybrid
        }
        
        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    // Custom name and trust status section
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if !encounter.customName.isEmpty {
                                    Text(encounter.customName)
                                        .font(.system(.title2, design: .monospaced))
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Unnamed Drone")
                                        .font(.system(.title2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let mac = encounter.metadata["mac"],
                                   !encounter.id.isEmpty {  // No 'let' needed here since these are non-optional
                                    let remoteId = encounter.id.replacingOccurrences(of: "drone-", with: "")
                                    FAALookupButton(mac: mac, remoteId: remoteId)
                                }
                                
                                Image(systemName: encounter.trustStatus.icon)
                                    .foregroundColor(encounter.trustStatus.color)
                                    .font(.system(size: 24))
                                
                                Button(action: { showingInfoEditor = true }) {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(encounter.id)
                                .font(.appCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Map and encounter stats sections
                    mapSection
                    encounterStats

//                  metadataSection // TODO metadata section
                    
                    if !encounter.macHistory.isEmpty && encounter.macHistory.count > 1 {
                        macSection
                    }
                    
                    // Flight data stats
                    flightDataSection
                }
                .padding()
            }
            .navigationTitle("Encounter Details")
            .onAppear {
                setupInitialMapPosition()
            }
            .sheet(isPresented: $showingInfoEditor) {
                NavigationView {
                    DroneInfoEditor(droneId: encounter.id)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Map Style", selection: $selectedMapType) {
                            Text("Standard").tag(MapStyle.standard)
                            Text("Satellite").tag(MapStyle.satellite)
                            Text("Hybrid").tag(MapStyle.hybrid)
                        }
                        Button {
                            exportKML()
                        } label: {
                            Label("Export KML", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete Encounter", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    storage.deleteEncounter(id: encounter.id)
                    dismiss() // Add this to return to list after deletion
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this encounter? This action cannot be undone.")
            }
        }
        
        private var mapSection: some View {
            Map(position: $mapCameraPosition) {
                if !encounter.flightPath.isEmpty {
                    // Draw regular flight path points only
                    let normalPoints = encounter.flightPath.filter { !$0.isProximityPoint }
                    if normalPoints.count > 1 {
                        MapPolyline(coordinates: normalPoints.map { $0.coordinate })
                            .stroke(.blue, lineWidth: 2)
                    }
                    
                    // Start point (only for normal points)
                    if let start = normalPoints.first {
                        Annotation("Start", coordinate: start.coordinate) {
                            Image(systemName: "airplane.departure")
                                .foregroundStyle(.green)
                                .background(Circle().fill(.white))
                        }
                    }
                    
                    // End point (only for normal points)
                    if let end = normalPoints.last, normalPoints.count > 1 {
                        Annotation("End", coordinate: end.coordinate) {
                            Image(systemName: "airplane.arrival")
                                .foregroundStyle(.red)
                                .background(Circle().fill(.white))
                        }
                    }
                    
                    // Draw proximity rings based on stored data
                    ForEach(encounter.flightPath.indices, id: \.self) { index in
                        let point = encounter.flightPath[index]
                        if point.isProximityPoint, let rssi = point.proximityRssi {
                            let generator = DroneSignatureGenerator()
                            let radius = generator.calculateDistance(rssi)
                            
                            MapCircle(center: point.coordinate, radius: radius)
                                .foregroundStyle(.yellow.opacity(0.1))
                                .stroke(.yellow, lineWidth: 2)
                            
                            Annotation("RSSI: \(Int(rssi)) dBm", coordinate: point.coordinate) {
                                VStack {
                                    Text("Encrypted Drone")
                                        .font(.caption)
                                    Text("\(Int(radius))m radius")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Home location from metadata
                if let homeLatStr = encounter.metadata["homeLat"],
                   let homeLonStr = encounter.metadata["homeLon"],
                   let homeLat = Double(homeLatStr),
                   let homeLon = Double(homeLonStr),
                   homeLat != 0 || homeLon != 0 {
                    let homeCoordinate = CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)
                    Annotation("Home", coordinate: homeCoordinate) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.green)
                            .background(Circle().fill(.white))
                    }
                }
                
                // Pilot/Operator location from metadata
                if let pilotLatStr = encounter.metadata["pilotLat"],
                   let pilotLonStr = encounter.metadata["pilotLon"],
                   let pilotLat = Double(pilotLatStr),
                   let pilotLon = Double(pilotLonStr),
                   pilotLat != 0 || pilotLon != 0 {
                    let pilotCoordinate = CLLocationCoordinate2D(latitude: pilotLat, longitude: pilotLon)
                    Annotation("Pilot", coordinate: pilotCoordinate) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.orange)
                            .background(Circle().fill(.white))
                    }
                }
                
                // Alert rings if any
                ForEach(cotViewModel.alertRings.filter { $0.droneId == encounter.id }) { ring in
                    MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                        .foregroundStyle(.red.opacity(0.2))
                        .stroke(.red, lineWidth: 2)
                }
            }
            .mapStyle(mapStyleForSelectedType())
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        
        private func setupInitialMapPosition() {
            // Collect all relevant coordinates
            var allCoordinates: [CLLocationCoordinate2D] = []
            
            // Add flight path coordinates (excluding 0,0)
            let validFlightPoints = encounter.flightPath.filter { point in
                point.latitude != 0 || point.longitude != 0
            }
            allCoordinates.append(contentsOf: validFlightPoints.map { $0.coordinate })
            
            // Add home location if available
            if let homeLatStr = encounter.metadata["homeLat"],
               let homeLonStr = encounter.metadata["homeLon"],
               let homeLat = Double(homeLatStr),
               let homeLon = Double(homeLonStr),
               homeLat != 0 || homeLon != 0 {
                allCoordinates.append(CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon))
            }
            
            // Add pilot location if available
            if let pilotLatStr = encounter.metadata["pilotLat"],
               let pilotLonStr = encounter.metadata["pilotLon"],
               let pilotLat = Double(pilotLatStr),
               let pilotLon = Double(pilotLonStr),
               pilotLat != 0 || pilotLon != 0 {
                allCoordinates.append(CLLocationCoordinate2D(latitude: pilotLat, longitude: pilotLon))
            }
            
            // Handle multiple coordinates
            if allCoordinates.count > 1 {
                let latitudes = allCoordinates.map { $0.latitude }
                let longitudes = allCoordinates.map { $0.longitude }
                
                let minLat = latitudes.min()!
                let maxLat = latitudes.max()!
                let minLon = longitudes.min()!
                let maxLon = longitudes.max()!
                
                let center = CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                )
                
                let latDelta = max((maxLat - minLat) * 1.2, 0.01)
                let lonDelta = max((maxLon - minLon) * 1.2, 0.01)
                
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                ))
            }
            // Handle single coordinate
            else if let singleCoord = allCoordinates.first {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: singleCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
            // Fallback to alert ring if no valid coordinates
            else if let ring = cotViewModel.alertRings.first(where: { $0.droneId == encounter.id }) {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: ring.centerCoordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: max(ring.radius / 111000 * 1.5, 0.01),
                        longitudeDelta: max(ring.radius / 111000 * 1.5, 0.01)
                    )
                ))
            }
        }
        
        private func mapStyleForSelectedType() -> MapKit.MapStyle {
            switch selectedMapType {
            case .standard:
                return .standard
            case .satellite:
                return .imagery
            case .hybrid:
                return .hybrid
            }
        }
        
        private var encounterStats: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("ENCOUNTER STATS")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                StatsGrid {
                    StatItem(title: "Duration", value: formatDuration(encounter.totalFlightTime))
                    StatItem(title: "Max Alt", value: String(format: "%.1fm", encounter.maxAltitude))
                    StatItem(title: "Max Speed", value: String(format: "%.1fm/s", encounter.maxSpeed))
                    StatItem(title: "Avg RSSI", value: String(format: "%.1fdBm", encounter.averageRSSI))
                    StatItem(title: "Points", value: "\(encounter.flightPath.count)")
                    StatItem(title: "Signatures", value: "\(encounter.signatures.count)")
                }
                Text("ENCOUNTER TIMELINE")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Detected")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text(formatDateTime(encounter.firstSeen))
                            .font(.appHeadline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Contact")
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text(formatDateTime(encounter.lastSeen))
                            .font(.appHeadline)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
        }
        
        private func formatDateTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
        
        private var macSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                macSectionTitle
                macSectionContent
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }

        private var macSectionTitle: some View {
            Text("MAC RANDOMIZATION")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        private var macSectionContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                macSectionHeader
                macAddressScrollView
            }
        }

        private var macSectionHeader: some View {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Device using MAC randomization")
                    .font(.appSubheadline)
                Spacer()
                Text("\(encounter.macHistory.count) addresses")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
        }

        private var macAddressScrollView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(encounter.macHistory).sorted(), id: \.self) { mac in
                        macAddressRow(mac)
                    }
                }
            }
            .frame(maxHeight: 150)
        }

        private func macAddressRow(_ mac: String) -> some View {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.yellow)
                Text(mac)
                    .font(.appCaption)
                
                if let firstSig = encounter.signatures.first(where: { $0.mac == mac }) {
                    Spacer()
                    Text(Date(timeIntervalSince1970: firstSig.timestamp), format: .dateTime.year().month().day().hour().minute())
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        
        
        
        private var flightDataSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("FLIGHT DATA")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        Spacer()
                        FlightDataChart(title: "Altitude", data: encounter.flightPath.map { $0.altitude }.filter { $0 != 0 })
                        FlightDataChart(title: "Speed", data: encounter.signatures.map { $0.speed }.filter { $0 != 0 })
                        FlightDataChart(title: "RSSI", data: encounter.signatures.map { $0.rssi }.filter { $0 != 0 })
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }

    }
    
    struct StatsGrid<Content: View>: View {
        let content: Content
        
        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        var body: some View {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                content
            }
        }
    }
    
    struct StatItem: View {
        let title: String
        let value: String
        
        var body: some View {
            VStack(spacing: 4) {
                Text(title)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.appHeadline)
            }
        }
    }
    
    struct FlightDataChart: View {
       let title: String
       let data: [Double]
       
       var body: some View {
           VStack {
               Text(title)
                   .font(.appCaption)
               
               if let minValue = data.min(), let maxValue = data.max(), data.count > 1 {
                   GeometryReader { geometry in
                       Path { path in
                           let step = geometry.size.width / CGFloat(data.count - 1)
                           let difference = maxValue - minValue
                           let scale = difference != 0 ? geometry.size.height / CGFloat(difference) : 0
                           
                           path.move(to: CGPoint(
                               x: 0,
                               y: geometry.size.height - (data[0] - minValue) * scale
                           ))
                           
                           for i in 1..<data.count {
                               path.addLine(to: CGPoint(
                                   x: CGFloat(i) * step,
                                   y: geometry.size.height - (data[i] - minValue) * scale
                               ))
                           }
                       }
                       .stroke(.blue, lineWidth: 2)
                   }
               } else {
                   Text("Insufficient data")
                       .font(.appCaption)
                       .foregroundColor(.secondary)
               }
           }
           .frame(width: 200, height: 100)
       }
    }
}

private func formatDuration(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = Int(time) % 3600 / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

extension StoredEncountersView.EncounterDetailView {
    private func generateKML(for encounter: DroneEncounter) -> String {
        let kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>\(encounter.id) Flight Path</name>
            <Style id="flightPath">
              <LineStyle>
                <color>ff0000ff</color>
                <width>4</width>
              </LineStyle>
            </Style>
            <Placemark>
              <name>\(encounter.id) Track</name>
              <styleUrl>#flightPath</styleUrl>
              <LineString>
                <altitudeMode>absolute</altitudeMode>
                <coordinates>
                    \(encounter.flightPath.map { point in
                        "\(point.longitude),\(point.latitude),\(point.altitude)"
                    }.joined(separator: "\n                    "))
                </coordinates>
              </LineString>
            </Placemark>
          </Document>
        </kml>
        """
        return kml
    }
    
    func exportKML(from viewController: UIViewController? = nil) {
        // Generate KML content
        let kmlContent = generateKML(for: encounter)
        
        // Ensure KML stuff is valid
        guard let kmlData = kmlContent.data(using: .utf8) else {
            print("Failed to convert KML content to NSData.")
            return
        }
        
        // Stamp the filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "_")
        let filename = "\(encounter.id)_flightpath_\(timestamp).kml"
        
        // Create a temporary file URL to share it
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        // Write KML data to the file
        do {
            try kmlData.write(to: fileURL)
        } catch {
            print("Failed to write KML data to file: \(error)")
            return
        }
        
        // Create the activity item source for sharing
        let kmlDataItem = KMLDataItem(fileURL: fileURL, filename: filename)
        
        let activityVC = UIActivityViewController(
            activityItems: [kmlDataItem],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = window
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: window.bounds.midX,
                    y: window.bounds.midY,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }
            
            DispatchQueue.main.async {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
    
    // Workaround to prevent writing where we don't want to
    class KMLDataItem: NSObject, UIActivityItemSource {
        private let fileURL: URL
        private let filename: String
        
        init(fileURL: URL, filename: String) {
            self.fileURL = fileURL
            self.filename = filename
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return fileURL
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            return fileURL
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
            return "application/vnd.google-earth.kml+xml"
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            return filename
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, filenameForActivityType activityType: UIActivity.ActivityType?) -> String {
            return filename
        }
    }

}


// TODO: add a nice metadata section
//        private var metadataSection: some View {
//            VStack(alignment: .leading, spacing: 8) {
//                Text("METADATA")
//                    .font(.appHeadline)
//
//                ForEach(Array(encounter.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
//                    HStack {
//                        Text(key)
//                            .foregroundStyle(.secondary)
//                        Spacer()
//                        Text(value)
//                    }
//                    .font(.appCaption)
//                }
//            }
//            .padding()
//            .background(Color(UIColor.secondarySystemBackground))
//            .cornerRadius(12)
//        }

