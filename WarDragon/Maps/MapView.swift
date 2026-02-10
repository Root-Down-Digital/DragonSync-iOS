//
//  MapView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import MapKit

struct MapView: View {
    let message: CoTViewModel.CoTMessage
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var region: MKCoordinateRegion
    @State private var selectedMapStyle: MapStyleOption = .standard
    
    enum MapStyleOption {
        case standard
        case hybrid
        case satellite
        
        var mapStyle: MapStyle {
            switch self {
            case .standard: return .standard
            case .hybrid: return .hybrid
            case .satellite: return .imagery
            }
        }
    }
    
    init(message: CoTViewModel.CoTMessage, cotViewModel: CoTViewModel) {
        self.message = message
        self.cotViewModel = cotViewModel
        
        let lat = Double(message.lat) ?? 0
        let lon = Double(message.lon) ?? 0
        
        let defaultRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        _region = State(initialValue: defaultRegion)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map {
                // Show marker only if coordinates are not 0,0
                if let coordinate = message.coordinate,
                   coordinate.latitude != 0 || coordinate.longitude != 0 {
    //                Marker(message.uid, coordinate: coordinate)
                    Annotation(message.uid, coordinate: coordinate) {
                        Image(systemName: "airplane")
                               .resizable()
                               .frame(width: 20, height: 20)
                               .rotationEffect(.degrees(message.headingDeg - 90))
                               .animation(.easeInOut(duration: 0.15), value: message.headingDeg)
                               .foregroundStyle(.blue)
                       }
                }
                
                // Now safely access cotViewModel since we're in the body
                if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }),
                   Double(message.lat) ?? 0 == 0 && Double(message.lon) ?? 0 == 0 {
                    MapCircle(center: ring.centerCoordinate, radius: ring.radius)
                        .foregroundStyle(.yellow.opacity(0.1))
                        .stroke(.yellow, lineWidth: 2)
                    
                    Marker("\(Int(ring.radius))m", coordinate: ring.centerCoordinate)
                        .tint(.yellow)
                }
            }
            .mapStyle(selectedMapStyle.mapStyle)
            .frame(height: 200)
            .onAppear {
                // Update the region if there's an alert ring
                if let ring = cotViewModel.alertRings.first(where: { $0.droneId == message.uid }),
                   Double(message.lat) ?? 0 == 0 && Double(message.lon) ?? 0 == 0 {
                    let newRegion = MKCoordinateRegion(
                        center: ring.centerCoordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: max(ring.radius / 1000 * 2, 0.01),
                            longitudeDelta: max(ring.radius / 1000 * 2, 0.01)
                        )
                    )
                    DispatchQueue.main.async {
                        region = newRegion
                    }
                }
            }
            
            // Map Style Picker Button
            Menu {
                Button {
                    selectedMapStyle = .standard
                } label: {
                    Label("Standard", systemImage: selectedMapStyle == .standard ? "checkmark" : "map")
                }
                
                Button {
                    selectedMapStyle = .hybrid
                } label: {
                    Label("Hybrid", systemImage: selectedMapStyle == .hybrid ? "checkmark" : "map.fill")
                }
                
                Button {
                    selectedMapStyle = .satellite
                } label: {
                    Label("Satellite", systemImage: selectedMapStyle == .satellite ? "checkmark" : "globe.americas.fill")
                }
            } label: {
                Image(systemName: "map")
                    .foregroundStyle(.white)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(8)
        }
    }
}
