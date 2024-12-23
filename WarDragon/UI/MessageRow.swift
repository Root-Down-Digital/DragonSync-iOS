//
//  MessageRow.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

// MessageRow.swift

import SwiftUI
import MapKit

struct MessageRow: View {
    let message: CoTViewModel.CoTMessage
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var showMap = false
    @State private var showLiveMap = false
    
    private var signature: DroneSignature? {
        cotViewModel.droneSignatures.first(where: { $0.primaryId.id == message.uid })
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: signature?.primaryId.uaType.icon ?? "airplane") // dynamic, default to airplane icon
                    .foregroundColor(.blue)
                Text("ID: \(message.id)")
                    .font(.headline)
                
                Spacer()
                
                // Add Live Map Button
                Button(action: { showLiveMap = true }) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Live")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            Text("Type: \(message.type)")
                .font(.subheadline)
            
            // Regular map view (tappable to open in Apple Maps)
            MapView(message: message)
                .frame(height: 150)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .onTapGesture {
                    if let lat = Double(message.lat),
                       let lon = Double(message.lon) {
                        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        mapItem.name = message.uid
                        mapItem.openInMaps()
                    }
                }
            
            Group {
                Text("Position: \(message.lat), \(message.lon)")
                Text("Altitude: \(message.alt)m AGL: \(message.height)m")
                Text("Speed: \(message.speed)m/s Vertical: \(message.vspeed)m/s")
                if !message.pilotLat.isEmpty {
                    Text("Pilot Location: \(message.pilotLat), \(message.pilotLon)")
                }
                if !message.description.isEmpty {
                    Text("Description: \(message.description)")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        // Live Map Sheet
        .sheet(isPresented: $showLiveMap) {
            NavigationView {
                LiveMapView(cotViewModel: cotViewModel, initialMessage: message)
                    .navigationTitle("Live Drone Map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showLiveMap = false
                            }
                        }
                    }
            }
        }
    }
}
