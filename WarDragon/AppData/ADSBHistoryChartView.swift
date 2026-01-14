//
//  ADSBHistoryChartView.swift
//  WarDragon
//
//  Created by Luke on 1/5/26.
//

import SwiftUI
import SwiftData
import Charts

struct ADSBHistoryChartView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var adsbEncounters: [StoredADSBEncounter] = []
    @State private var sortOrder: SortOrder = .lastSeen
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    
    enum SortOrder {
        case lastSeen, firstSeen, totalSightings, maxAltitude
    }
    
    var sortedEncounters: [StoredADSBEncounter] {
        // Filter out any deleted objects that might still be in the array
        let validEncounters = adsbEncounters.filter { encounter in
            !encounter.isDeleted
        }
        
        let filtered = validEncounters.filter { encounter in
            searchText.isEmpty ||
            encounter.id.localizedCaseInsensitiveContains(searchText) ||
            encounter.callsign.localizedCaseInsensitiveContains(searchText)
        }
        
        return filtered.sorted { first, second in
            switch sortOrder {
            case .lastSeen: return first.lastSeen > second.lastSeen
            case .firstSeen: return first.firstSeen < second.firstSeen
            case .totalSightings: return first.totalSightings > second.totalSightings
            case .maxAltitude: return first.maxAltitude > second.maxAltitude
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary Stats Card
                summaryStatsCard
                
                // Chart Section
                if !sortedEncounters.isEmpty {
                    chartSection
                }
                
                // Aircraft List
                aircraftListSection
            }
            .padding()
        }
        .searchable(text: $searchText, prompt: "Search by ICAO or Callsign")
        .navigationTitle("Aircraft History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        Text("Last Seen").tag(SortOrder.lastSeen)
                        Text("First Seen").tag(SortOrder.firstSeen)
                        Text("Total Sightings").tag(SortOrder.totalSightings)
                        Text("Max Altitude").tag(SortOrder.maxAltitude)
                    }
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        })
        .alert("Delete All Aircraft History", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAllAircraft()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            loadAircraftData()
        }
        .onDisappear {
            // Clean up any deleted objects from local array
            adsbEncounters.removeAll { $0.isDeleted }
        }
        .onChange(of: sortOrder) {
            // Refresh when sort order changes
        }
    }
    
    // MARK: - Summary Stats Card
    
    private var summaryStatsCard: some View {
        VStack(spacing: 12) {
            Text("FLIGHT STATISTICS")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            if adsbEncounters.isEmpty {
                Text("No aircraft data recorded yet")
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatItem(title: "Total Aircraft", value: "\(adsbEncounters.count)")
                    StatItem(title: "Total Sightings", value: "\(totalSightings)")
                    StatItem(title: "Highest Alt", value: "\(Int(highestAltitude))ft")
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var totalSightings: Int {
        adsbEncounters.filter { !$0.isDeleted }.reduce(0) { $0 + $1.totalSightings }
    }
    
    private var highestAltitude: Double {
        adsbEncounters.filter { !$0.isDeleted }.map { $0.maxAltitude }.max() ?? 0
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOP 10 AIRCRAFT BY SIGHTINGS")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            let topAircraft = sortedEncounters
                .sorted { $0.totalSightings > $1.totalSightings }
                .prefix(10)
            
            Chart(Array(topAircraft)) { aircraft in
                BarMark(
                    x: .value("Sightings", aircraft.totalSightings),
                    y: .value("Aircraft", aircraft.displayName)
                )
                .foregroundStyle(Color.blue.gradient)
                .annotation(position: .trailing) {
                    Text("\(aircraft.totalSightings)")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.appCaption)
                        }
                    }
                }
            }
            .frame(height: max(300, CGFloat(topAircraft.count) * 30))
            
            // Altitude Distribution Chart
            Text("ALTITUDE DISTRIBUTION")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top)
            
            Chart(Array(topAircraft)) { aircraft in
                PointMark(
                    x: .value("Max Altitude", aircraft.maxAltitude),
                    y: .value("Min Altitude", aircraft.minAltitude)
                )
                .foregroundStyle(Color.orange)
                .symbolSize(100)
            }
            .chartXAxisLabel("Altitude (feet)", alignment: .center)
            .chartYAxisLabel("Min Altitude", alignment: .center)
            .frame(height: 250)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Aircraft List Section
    
    private var aircraftListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AIRCRAFT ENCOUNTERS")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            if sortedEncounters.isEmpty {
                Text("No aircraft found")
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(sortedEncounters, id: \.id) { aircraft in
                    AircraftHistoryRow(aircraft: aircraft)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Data Management
    
    private func loadAircraftData() {
        // Clear the existing array first to avoid stale references
        adsbEncounters.removeAll()
        
        let descriptor = FetchDescriptor<StoredADSBEncounter>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        
        do {
            adsbEncounters = try modelContext.fetch(descriptor)
            print("Loaded \(adsbEncounters.count) aircraft from SwiftData")
        } catch {
            print("❌ Failed to fetch ADSB encounters: \(error)")
            adsbEncounters = []
        }
    }
    
    private func deleteAllAircraft() {
        do {
            // Fetch all encounters fresh from context to ensure we have valid references
            let descriptor = FetchDescriptor<StoredADSBEncounter>()
            let allEncounters = try modelContext.fetch(descriptor)
            
            print("🗑️ Deleting \(allEncounters.count) aircraft encounters...")
            
            // Delete all ADSB encounters
            for encounter in allEncounters {
                modelContext.delete(encounter)
            }
            
            // Save the deletions
            try modelContext.save()
            
            // Clear local array after successful save
            adsbEncounters.removeAll()
            
            print("Successfully deleted all aircraft")
        } catch {
            print("❌ Failed to delete all aircraft: \(error)")
            
            // Even if save failed, try to reload to get fresh state
            loadAircraftData()
        }
    }
}

// MARK: - Aircraft History Row

struct AircraftHistoryRow: View {
    let aircraft: StoredADSBEncounter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(aircraft.displayName)
                        .font(.appHeadline)
                    
                    Text(aircraft.id.uppercased())
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "airplane")
                    .foregroundStyle(.blue)
                    .font(.title2)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sightings")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("\(aircraft.totalSightings)")
                        .font(.appSubheadline)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max Alt")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(aircraft.maxAltitude)) ft")
                        .font(.appSubheadline)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                    Text(aircraft.formattedDuration)
                        .font(.appSubheadline)
                }
                
                Spacer()
            }
            
            HStack {
                Text("First: \(formatDate(aircraft.firstSeen))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Last: \(formatDate(aircraft.lastSeen))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Stat Item (reused from StoredEncountersView)

private struct StatItem: View {
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

#Preview {
    NavigationStack {
        ADSBHistoryChartView()
            .modelContainer(for: [StoredADSBEncounter.self], inMemory: true)
    }
}
