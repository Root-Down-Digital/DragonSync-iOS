//
//  AircraftListView.swift
//  WarDragon
//
//  List view for displaying tracked aircraft from ADS-B
//

import SwiftUI

struct AircraftListView: View {
    @ObservedObject var cotViewModel: CoTViewModel
    @State private var searchText = ""
    @State private var sortBy: SortOption = .distance
    @State private var showFilters = false
    
    enum SortOption: String, CaseIterable {
        case distance = "Distance"
        case altitude = "Altitude"
        case speed = "Speed"
        case callsign = "Callsign"
    }
    
    var filteredAircraft: [Aircraft] {
        var aircraft = cotViewModel.aircraftTracks
        
        // Apply search filter
        if !searchText.isEmpty {
            aircraft = aircraft.filter { ac in
                ac.displayName.localizedCaseInsensitiveContains(searchText) ||
                ac.hex.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        switch sortBy {
        case .distance:
            // Would need user location to sort by distance
            return aircraft.sorted { ($0.seen ?? 999) < ($1.seen ?? 999) }
        case .altitude:
            return aircraft.sorted { ($0.altitude ?? 0) > ($1.altitude ?? 0) }
        case .speed:
            return aircraft.sorted { ($0.groundSpeed ?? 0) > ($1.groundSpeed ?? 0) }
        case .callsign:
            return aircraft.sorted { $0.displayName < $1.displayName }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats header
            if !cotViewModel.aircraftTracks.isEmpty {
                aircraftStatsHeader
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
            }
            
            // Main list
            if cotViewModel.aircraftTracks.isEmpty {
                emptyStateView
            } else {
                List(filteredAircraft) { aircraft in
                    AircraftRow(aircraft: aircraft)
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search by callsign or ICAO")
                .refreshable {
                    // Refresh is handled automatically by the ADS-B polling
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Sort button with icon reflecting current sort
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Image(systemName: iconForSortOption(option))
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
                    Label("Sort", systemImage: sortIcon)
                        .labelStyle(.iconOnly)
                }
                .help("Sort aircraft")
                
                // Clear button
                Button(action: {
                    withAnimation {
                        cotViewModel.clearAircraftTracks()
                    }
                }) {
                    Label("Clear All", systemImage: "xmark.bin.fill")
                        .labelStyle(.iconOnly)
                }
                .help("Clear all aircraft")
                .disabled(cotViewModel.aircraftTracks.isEmpty)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var aircraftStatsHeader: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "airplane",
                value: "\(cotViewModel.aircraftTracks.count)",
                label: "Aircraft"
            )
            
            StatBadge(
                icon: "antenna.radiowaves.left.and.right",
                value: "\(activeAircraftCount)",
                label: "Active"
            )
            
            if let highest = highestAircraft {
                StatBadge(
                    icon: "arrow.up.circle.fill",
                    value: "\(highest)",
                    label: "Max Alt (ft)"
                )
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Aircraft Tracked")
                .font(.headline)
            
            Text("Enable ADS-B in Settings to track aircraft in your area")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var activeAircraftCount: Int {
        cotViewModel.aircraftTracks.filter { !$0.isStale }.count
    }
    
    private var highestAircraft: Int? {
        cotViewModel.aircraftTracks.compactMap { $0.altitudeFeet }.max()
    }
    
    /// Icon that reflects the current sort option
    private var sortIcon: String {
        switch sortBy {
        case .distance:
            return "arrow.up.and.down.circle"
        case .altitude:
            return "arrow.up.arrow.down.circle"
        case .speed:
            return "speedometer"
        case .callsign:
            return "textformat.abc"
        }
    }
    
    /// Get icon for a specific sort option (for menu items)
    private func iconForSortOption(_ option: SortOption) -> String {
        switch option {
        case .distance:
            return "location.circle"
        case .altitude:
            return "arrow.up.right"
        case .speed:
            return "gauge.with.needle"
        case .callsign:
            return "textformat.abc.dottedunderline"
        }
    }
}

// MARK: - Stat Badge Component

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(value)
                    .font(.headline)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        AircraftListView(cotViewModel: CoTViewModel(statusViewModel: StatusViewModel()))
            .navigationTitle("Aircraft")
    }
}
