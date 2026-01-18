//
//  ServiceManagementView.swift
//  WarDragon
//
//  Created by Luke on 1/10/25.
//
// NOTE: This file is currently disabled because ServiceViewModel and ServiceControl
// were removed from the project. If you need service management functionality,
// you'll need to re-implement these classes with proper ZMQ port separation.

/*

import SwiftUI

struct ServiceManagementView: View {
    @ObservedObject var viewModel: ServiceViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedService: ServiceControl?
    @State private var showingActionSheet = false
    @State private var pendingAction: ServiceAction?
    
    init(viewModel: ServiceViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }
    
    enum ServiceAction: Identifiable {
        case toggle
        case restart
        
        var id: String {
            switch self {
            case .toggle: return "toggle"
            case .restart: return "restart"
            }
        }
        
        var title: String {
            switch self {
            case .toggle: return "Toggle Service"
            case .restart: return "Restart Service"
            }
        }
        
        var message: String {
            switch self {
            case .toggle: return "Are you sure you want to toggle this service?"
            case .restart: return "Are you sure you want to restart this service?"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            healthStatusBar
            
            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.criticalServices().isEmpty {
                        criticalServicesSection
                    }
                    
                    ForEach(Array(viewModel.servicesByCategory().keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { category in
                        if let services = viewModel.servicesByCategory()[category] {
                            serviceSection(category: category, services: services)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            //            viewModel.startMonitoring()
        }
        .onDisappear {
            //            viewModel.stopMonitoring()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .confirmationDialog(
            selectedService?.description ?? "",
            isPresented: $showingActionSheet,
            presenting: pendingAction
        ) { action in
            Button(action.title, role: .destructive) {
                if let service = selectedService {
                    switch action {
                    case .toggle:
                        viewModel.toggleService(service)
                    case .restart:
                        viewModel.restartService(service)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
    }
    
    private var healthStatusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.healthReport?.statusColor ?? .gray)
                .frame(width: 12, height: 12)
            
            Text(viewModel.healthReport?.overallHealth.uppercased() ?? "NO CONNECTION")
                .font(.appHeadline)
            
            Spacer()
            
            Text(viewModel.healthReport?.timestamp.formatted(date: .omitted, time: .standard) ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(colorScheme == .dark ? Color.black : Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    private var criticalServicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CRITICAL SERVICES")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.red)
                .padding(.horizontal, 4)
            
            ForEach(viewModel.criticalServices()) { service in
                ServiceRowView(
                    service: service,
                    viewModel: viewModel,
                    selectedService: $selectedService,
                    showingActionSheet: $showingActionSheet,
                    pendingAction: $pendingAction
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func serviceSection(category: ServiceControl.ServiceCategory, services: [ServiceControl]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                Text(category.rawValue.uppercased())
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundColor(category.color)
            .padding(.horizontal, 4)
            
            ForEach(services) { service in
                ServiceRowView(
                    service: service,
                    viewModel: viewModel,
                    selectedService: $selectedService,
                    showingActionSheet: $showingActionSheet,
                    pendingAction: $pendingAction
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(category.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(category.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ServiceRowView: View {
    let service: ServiceControl
    @ObservedObject var viewModel: ServiceViewModel
    @Binding var selectedService: ServiceControl?
    @Binding var showingActionSheet: Bool
    @Binding var pendingAction: ServiceManagementView.ServiceAction?
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: 4) {
            Button(action: { showDetails.toggle() }) {
                HStack {
                    // Status indicator
                    Circle()
                        .fill(service.status.healthStatus.color)
                        .frame(width: 8, height: 8)
                    
                    // Service name and description
                    VStack(alignment: .leading) {
                        Text(service.description)
                            .font(.system(.body, design: .monospaced))
                        if !service.status.statusText.isEmpty {
                            Text(service.status.statusText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Resource usage if available
                    if let resources = service.resources {
                        HStack(spacing: 8) {
                            ResourceIndicator(
                                value: resources.cpuPercent,
                                icon: "cpu",
                                color: resourceColor(percent: resources.cpuPercent)
                            )
                            ResourceIndicator(
                                value: resources.memoryPercent,
                                icon: "memorychip",
                                color: resourceColor(percent: resources.memoryPercent)
                            )
                        }
                    }
                    
                    // Active/Inactive toggle
                    Button {
                        selectedService = service
                        pendingAction = .toggle
                        showingActionSheet = true
                    } label: {
                        Image(systemName: service.status.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(service.status.isActive ? .green : .gray)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if showDetails {
                serviceDetails
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    struct ResourceIndicator: View {
        let value: Double
        let icon: String
        let color: Color
        
        var body: some View {
            Label(
                String(format: "%.0f%%", value),
                systemImage: icon
            )
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(color)
        }
    }

    private func resourceColor(percent: Double) -> Color {
        switch percent {
        case 0..<60: return .green
        case 60..<80: return .yellow
        default: return .red
        }
    }
    
    private var serviceDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                detailRow("Service:", service.service)
                detailRow("Status:", service.status.statusText)
                if !service.dependencies.isEmpty {
                    detailRow("Dependencies:", service.dependencies.joined(separator: ", "))
                }
            }
            .font(.system(.caption, design: .monospaced))
            
            if !service.issues.isEmpty {
                Divider()
                Text("ISSUES")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.red)
                
                ForEach(service.issues) { issue in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(issue.severity.color)
                            .frame(width: 6, height: 6)
                        Text(issue.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack {
                Spacer()
                Button {
                    selectedService = service
                    pendingAction = .restart
                    showingActionSheet = true
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.system(.caption, design: .monospaced))
                }
                .disabled(viewModel.isLoading)
            }
        }
        .padding(.top, 8)
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
        }
    }
}
*/

