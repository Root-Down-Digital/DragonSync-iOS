//
//  DatabaseManagementView.swift
//  WarDragon
//
//  Database management and backup/restore functionality
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
struct DatabaseManagementView: View {
    @Environment(\.modelContext) private var modelContext
    private let migrationManager = DataMigrationManager.shared
    
    @State private var stats: DatabaseStats?
    @State private var backupFiles: [URL] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var fileToDelete: URL?
    @State private var showResetConfirmation = false
    @State private var showRestoreSheet = false
    @State private var showExportShare = false
    @State private var exportedFileURL: URL?
    
    var body: some View {
        Form {
            // Database Status Section
            Section {
                if let stats = stats {
                    DatabaseSizeRow(size: stats.formattedSize)
                    EncounterCountRow(count: stats.encounterCount)
                    FlightPointsRow(count: stats.flightPointCount)
                    SignaturesRow(count: stats.signatureCount)
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading database stats...")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Database Statistics", systemImage: "chart.bar.fill")
            }
            
            // Migration Status Section
            Section {
                HStack {
                    Image(systemName: migrationStatusIcon)
                        .foregroundColor(migrationStatusColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Migration Status")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                        Text(migrationManager.migrationStatus)
                            .font(.appHeadline)
                    }
                }
                
                Button {
                    Task {
                        await performForceMigration()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Force Re-Migration")
                    }
                }
                .disabled(isLoading)
                
            } header: {
                Label("Migration", systemImage: "arrow.left.arrow.right.circle.fill")
            } footer: {
                Text("Force re-migration will reset the migration flag and re-import data from UserDefaults backup on next app launch.")
                    .font(.appCaption)
            }
            
            // Backup & Export Section
            Section {
                Button {
                    Task {
                        await createBackup()
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.blue)
                        Text("Export Current Database")
                        Spacer()
                        if isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(isLoading)
                
            } header: {
                Label("Backup & Export", systemImage: "externaldrive.fill")
            } footer: {
                Text("Creates a JSON backup of all drone encounters. You can share this file to back up your data.")
                    .font(.appCaption)
            }
            
            // Backup Files Section
            Section {
                if backupFiles.isEmpty {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.secondary)
                        Text("No backup files found")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(backupFiles, id: \.self) { fileURL in
                        BackupFileRow(fileURL: fileURL, onDelete: {
                            fileToDelete = fileURL
                            showDeleteConfirmation = true
                        }, onRestore: {
                            Task {
                                await restoreFromBackup(fileURL: fileURL)
                            }
                        }, onShare: {
                            exportedFileURL = fileURL
                            showExportShare = true
                        })
                    }
                    
                    // Show cleanup button if there are multiple legacy backups
                    if backupFiles.filter({ $0.lastPathComponent.hasPrefix("wardragon_backup_") }).count > 1 {
                        Button {
                            cleanupDuplicateBackups()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.trash")
                                    .foregroundColor(.orange)
                                Text("Clean Up Duplicate Backups")
                            }
                        }
                    }
                }
                
                Button {
                    loadBackupFiles()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh List")
                    }
                }
            } header: {
                Label("Backup Files (\(backupFiles.count))", systemImage: "doc.on.doc.fill")
            } footer: {
                Text("Tap a file to view options. Backups are stored in the app's Documents directory.")
                    .font(.appCaption)
            }
            
            // Danger Zone Section
            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete All Data")
                    }
                }
                .disabled(isLoading)
                
            } header: {
                Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } footer: {
                Text("⚠️ This will permanently delete all drone encounters, flight paths, and signatures. This action cannot be undone. Create a backup first!")
                    .font(.appCaption)
                    .foregroundColor(.red)
            }
        }
        .navigationTitle("Database Management")
        .font(.appDefault)
        .task {
            await loadStats()
            loadBackupFiles()
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") { }
        } message: {
            Text(successMessage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Delete Backup File?", isPresented: $showDeleteConfirmation, presenting: fileToDelete) { fileURL in
            Button("Delete", role: .destructive) {
                deleteBackupFile(fileURL)
            }
            Button("Cancel", role: .cancel) { }
        } message: { fileURL in
            Text("Are you sure you want to delete \(fileURL.lastPathComponent)?")
        }
        .confirmationDialog("Delete All Data?", isPresented: $showResetConfirmation) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await deleteAllData()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("⚠️ This will permanently delete all \(stats?.encounterCount ?? 0) encounters and cannot be undone. Make sure you have a backup!")
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var migrationStatusIcon: String {
        let status = migrationManager.migrationStatus
        if status.contains("Completed") {
            return "checkmark.circle.fill"
        } else if status.contains("Not migrated") {
            return "clock.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var migrationStatusColor: Color {
        let status = migrationManager.migrationStatus
        if status.contains("Completed") {
            return .green
        } else if status.contains("Not migrated") {
            return .orange
        } else {
            return .red
        }
    }
    
    private func loadStats() async {
        do {
            stats = try migrationManager.getDatabaseStats(modelContext: modelContext)
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func loadBackupFiles() {
        do {
            backupFiles = try migrationManager.listBackupFiles()
        } catch {
            errorMessage = "Failed to load backup files: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func createBackup() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let url = try migrationManager.exportSwiftDataBackup(modelContext: modelContext)
            successMessage = "Backup created successfully!\n\(url.lastPathComponent)"
            showSuccess = true
            loadBackupFiles()
            
            // Show share sheet
            exportedFileURL = url
            showExportShare = true
        } catch {
            errorMessage = "Failed to create backup: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func restoreFromBackup(fileURL: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try migrationManager.restoreFromBackup(backupURL: fileURL, modelContext: modelContext)
            successMessage = "Successfully restored from backup!"
            showSuccess = true
            await loadStats()
        } catch {
            errorMessage = "Failed to restore: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func deleteBackupFile(_ fileURL: URL) {
        do {
            try migrationManager.deleteBackup(at: fileURL)
            loadBackupFiles()
            successMessage = "Backup file deleted"
            showSuccess = true
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func deleteAllData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try migrationManager.deleteAllSwiftData(modelContext: modelContext)
            successMessage = "All data deleted successfully"
            showSuccess = true
            await loadStats()
        } catch {
            errorMessage = "Failed to delete data: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func performForceMigration() async {
        isLoading = true
        defer { isLoading = false }
        
        migrationManager.rollback()
        successMessage = "Migration flag reset. App will re-migrate data on next launch."
        showSuccess = true
    }
    
    private func cleanupDuplicateBackups() {
        let legacyBackups = backupFiles.filter { $0.lastPathComponent.hasPrefix("wardragon_backup_") }
        
        guard legacyBackups.count > 1 else { return }
        
        // Keep the newest one, delete the rest
        let sortedBackups = legacyBackups.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
        
        let toDelete = sortedBackups.dropFirst() // Keep first (newest), delete rest
        var deletedCount = 0
        
        for fileURL in toDelete {
            do {
                try migrationManager.deleteBackup(at: fileURL)
                deletedCount += 1
            } catch {
                // Continue deleting others even if one fails
                continue
            }
        }
        
        loadBackupFiles()
        
        if deletedCount > 0 {
            successMessage = "Cleaned up \(deletedCount) duplicate backup\(deletedCount == 1 ? "" : "s"). Kept the most recent one."
            showSuccess = true
        }
    }
}

// MARK: - Database Stats Row Views

struct DatabaseSizeRow: View {
    let size: String
    
    var body: some View {
        HStack {
            Image(systemName: "cylinder.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Database Size")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text(size)
                    .font(.appHeadline)
            }
        }
    }
}

struct EncounterCountRow: View {
    let count: Int
    
    var body: some View {
        HStack {
            Image(systemName: "target")
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Drone Encounters")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text("\(count)")
                    .font(.appHeadline)
                    .monospacedDigit()
            }
        }
    }
}

struct FlightPointsRow: View {
    let count: Int
    
    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Flight Points")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text("\(count)")
                    .font(.appHeadline)
                    .monospacedDigit()
            }
        }
    }
}

struct SignaturesRow: View {
    let count: Int
    
    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("Signatures")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text("\(count)")
                    .font(.appHeadline)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Backup File Row

struct BackupFileRow: View {
    let fileURL: URL
    let onDelete: () -> Void
    let onRestore: () -> Void
    let onShare: () -> Void
    
    @State private var fileSize: String = "..."
    @State private var creationDate: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                Text(fileURL.lastPathComponent)
                    .font(.appCaption)
                    .lineLimit(1)
            }
            
            HStack {
                if let date = creationDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                }
                Text(fileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                Button {
                    onRestore()
                } label: {
                    Label("Restore", systemImage: "arrow.counterclockwise")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                
                Button {
                    onShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .task {
            loadFileInfo()
        }
    }
    
    private func loadFileInfo() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSize = formatter.string(fromByteCount: size)
            }
            creationDate = attributes[.creationDate] as? Date
        } catch {
            fileSize = "Unknown"
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DatabaseManagementView()
            .modelContainer(for: [StoredDroneEncounter.self])
    }
}
