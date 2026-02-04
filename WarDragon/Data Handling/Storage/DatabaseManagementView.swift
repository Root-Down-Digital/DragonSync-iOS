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
    @State private var showRestoreConfirmation = false
    @State private var fileToRestore: URL?
    @State private var backupVerificationResults: [BackupVerificationResult] = []
    @State private var showVerificationResults = false
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
                    AircraftCountRow(count: stats.aircraftCount)
                    
                    // Show compact button if database is large but records are minimal
                    if stats.databaseSizeBytes > 10_000_000 && stats.encounterCount == 0 {
                        Button {
                            Task {
                                await compactDatabase()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.orange)
                                Text("Compact Database")
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading database stats...")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Database Statistics", systemImage: "chart.bar.fill")
            } footer: {
                if let stats = stats, stats.databaseSizeBytes > 10_000_000 && stats.encounterCount == 0 {
                    Text("Database file is large despite having no records. Use 'Compact Database' to reclaim disk space. SQLite reserves space for performance, but you can shrink it when needed.")
                        .font(.appCaption)
                } else {
                    Text("Database size shows disk space used. After deleting records, the file size remains the same as SQLite reserves space for performance.")
                        .font(.appCaption)
                }
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
                .disabled(isLoading || stats?.encounterCount == 0)
                
            } header: {
                Label("Backup & Export", systemImage: "externaldrive.fill")
            } footer: {
                if stats?.encounterCount == 0 {
                    Text("No encounters to export. The database is empty.")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Creates a JSON backup of all drone encounters. You can share this file to back up your data.")
                        .font(.appCaption)
                }
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
                        let verificationResult = backupVerificationResults.first { $0.url == fileURL }
                        BackupFileRow(
                            fileURL: fileURL,
                            verificationResult: verificationResult,
                            onDelete: {
                                fileToDelete = fileURL
                                showDeleteConfirmation = true
                            },
                            onRestore: {
                                fileToRestore = fileURL
                                showRestoreConfirmation = true
                            }
                        )
                    }
                    
                    // Verify backups button
                    Button {
                        verifyBackups()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.green)
                            Text("Verify All Backups")
                        }
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
                Text("Tap a file to view options. Backups are stored in the app's Documents directory. Use 'Verify All Backups' to check for corrupted files.")
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
                Text("This will permanently delete all drone encounters, aircraft encounters, flight paths, and signatures. This action cannot be undone. Create a backup first!")
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
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Processing...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
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
        .alert("Delete Backup File?", isPresented: $showDeleteConfirmation, presenting: fileToDelete) { fileURL in
            Button("Delete", role: .destructive) {
                deleteBackupFile(fileURL)
            }
            Button("Cancel", role: .cancel) { }
        } message: { fileURL in
            Text("Are you sure you want to delete \(fileURL.lastPathComponent)?")
        }
        .alert("Delete All Data?", isPresented: $showResetConfirmation) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await deleteAllData()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let droneCount = stats?.encounterCount ?? 0
            let aircraftCount = stats?.aircraftCount ?? 0
            let total = droneCount + aircraftCount
            
            if droneCount > 0 && aircraftCount > 0 {
                Text("This will permanently delete \(droneCount) drone encounter\(droneCount == 1 ? "" : "s") and \(aircraftCount) aircraft encounter\(aircraftCount == 1 ? "" : "s") (\(total) total) and cannot be undone. Make sure you have a backup!")
            } else if droneCount > 0 {
                Text("This will permanently delete all \(droneCount) drone encounter\(droneCount == 1 ? "" : "s") and cannot be undone. Make sure you have a backup!")
            } else if aircraftCount > 0 {
                Text("This will permanently delete all \(aircraftCount) aircraft encounter\(aircraftCount == 1 ? "" : "s") and cannot be undone. Make sure you have a backup!")
            } else {
                Text("This will permanently delete all data and cannot be undone.")
            }
        }
        .alert("Restore from Backup?", isPresented: $showRestoreConfirmation, presenting: fileToRestore) { fileURL in
            Button("Restore", role: .destructive) {
                Task {
                    await restoreFromBackup(fileURL: fileURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { fileURL in
            if let result = backupVerificationResults.first(where: { $0.url == fileURL }) {
                Text("This will import \(result.encounterCount) encounter\(result.encounterCount == 1 ? "" : "s") from '\(fileURL.lastPathComponent)' into your database. Existing encounters with the same ID will not be duplicated.")
            } else {
                Text("This will import encounters from '\(fileURL.lastPathComponent)' into your database. Existing encounters with the same ID will not be duplicated.")
            }
        }
        .sheet(isPresented: $showExportShare) {
            // Clean up on dismissal
            exportedFileURL = nil
        } content: {
            if let url = exportedFileURL {
                ShareSheetView(url: url)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
            loadBackupFiles()
            
            // Wait a moment for UI to settle before showing share sheet
            try? await Task.sleep(for: .milliseconds(200))
            
            await MainActor.run {
                exportedFileURL = url
                showExportShare = true
            }
            
        } catch {
            errorMessage = "Failed to create backup: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func restoreFromBackup(fileURL: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get encounter count before restore
            let statsBefore = try? migrationManager.getDatabaseStats(modelContext: modelContext)
            let encountersBefore = statsBefore?.encounterCount ?? 0
            
            // Perform restore
            try migrationManager.restoreFromBackup(backupURL: fileURL, modelContext: modelContext)
            
            // Get new stats
            await loadStats()
            let encountersAfter = stats?.encounterCount ?? 0
            let encountersAdded = encountersAfter - encountersBefore
            
            // Build success message
            var message = "Backup restored successfully!\n\n"
            message += "File: \(fileURL.lastPathComponent)\n"
            if encountersAdded > 0 {
                message += "Added: \(encountersAdded) new encounter\(encountersAdded == 1 ? "" : "s")\n"
            }
            message += "Total encounters: \(encountersAfter)"
            
            successMessage = message
            showSuccess = true
            
            // Refresh backup list in case verification status changed
            loadBackupFiles()
        } catch {
            errorMessage = "Failed to restore backup:\n\(error.localizedDescription)"
            showError = true
        }
    }
    
    private func deleteBackupFile(_ fileURL: URL) {
        do {
            // Ensure we have access to the file before trying to delete
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                errorMessage = "File not found: \(fileURL.lastPathComponent)"
                showError = true
                return
            }
            
            try migrationManager.deleteBackup(at: fileURL)
            
            // Refresh the list
            loadBackupFiles()
            
            // Clear any verification results for this file
            backupVerificationResults.removeAll { $0.url == fileURL }
            
            successMessage = "Backup file deleted: \(fileURL.lastPathComponent)"
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
            
            await loadStats()
            
            var message = "All records deleted successfully\n\n"
            
            if let stats = stats {
                message += "Drone encounters: \(stats.encounterCount)\n"
                message += "Aircraft encounters: \(stats.aircraftCount)\n"
                message += "Flight points: \(stats.flightPointCount)\n"
                message += "Signatures: \(stats.signatureCount)\n\n"
                
                if stats.flightPointCount > 0 || stats.signatureCount > 0 {
                    message += "Warning: Found orphaned records that weren't properly deleted. "
                    message += "This shouldn't happen - cascade delete may have failed.\n\n"
                }
            }
            
            message += "Note: Database file size will not change immediately. "
            message += "SQLite reserves the space for future records to improve performance. "
            message += "Use 'Compact Database' to reclaim disk space."
            
            successMessage = message
            showSuccess = true
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
    
    private func verifyBackups() {
        backupVerificationResults = migrationManager.verifyAllBackups()
        
        let validCount = backupVerificationResults.filter { $0.status == .valid }.count
        let emptyCount = backupVerificationResults.filter { $0.status == .empty }.count
        let corruptedCount = backupVerificationResults.filter { $0.status == .corrupted }.count
        
        var message = "Backup Verification Complete:\n"
        message += "\(validCount) valid backup\(validCount == 1 ? "" : "s")\n"
        if emptyCount > 0 {
            message += "\(emptyCount) empty backup\(emptyCount == 1 ? "" : "s")\n"
        }
        if corruptedCount > 0 {
            message += "\(corruptedCount) corrupted backup\(corruptedCount == 1 ? "" : "s")"
        }
        
        successMessage = message
        showSuccess = true
    }
    
    private func compactDatabase() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let statsBefore = stats
            let sizeBefore = statsBefore?.databaseSizeBytes ?? 0
            
            try migrationManager.compactDatabase(modelContext: modelContext)
            
            await loadStats()
            
            let sizeAfter = stats?.databaseSizeBytes ?? 0
            let bytesReclaimed = sizeBefore - sizeAfter
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let reclaimedString = formatter.string(fromByteCount: bytesReclaimed)
            
            var message = "Database compacted successfully\n\n"
            message += "Space reclaimed: \(reclaimedString)\n"
            message += "New size: \(stats?.formattedSize ?? "Unknown")"
            
            successMessage = message
            showSuccess = true
        } catch {
            errorMessage = "Failed to compact database: \(error.localizedDescription)"
            showError = true
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

struct AircraftCountRow: View {
    let count: Int
    
    var body: some View {
        HStack {
            Image(systemName: "airplane")
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("Aircraft (ADS-B)")
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
    let verificationResult: BackupVerificationResult?
    let onDelete: () -> Void
    let onRestore: () -> Void
    
    @State private var fileSize: String = "..."
    @State private var creationDate: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForFile)
                    .foregroundColor(colorForFile)
                Text(fileURL.lastPathComponent)
                    .font(.appCaption)
                    .lineLimit(1)
                
                if let result = verificationResult {
                    Text(result.statusEmoji)
                        .font(.caption)
                }
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
                
                if let result = verificationResult, result.encounterCount > 0 {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(result.encounterCount) encounters")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Show error if corrupted
            if let result = verificationResult, result.status == .corrupted, let error = result.error {
                Text("\(error)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            HStack(spacing: 16) {
                Button {
                    onRestore()
                } label: {
                    Label("Restore", systemImage: "arrow.counterclockwise")
                        .font(.appCaption)
                }
                .buttonStyle(.bordered)
                .disabled(verificationResult?.status == .corrupted)
                
                // Share button using custom action
                Button {
                    shareFile()
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
    
    private var iconForFile: String {
        if let result = verificationResult {
            switch result.status {
            case .valid:
                return "checkmark.circle.fill"
            case .empty:
                return "doc.fill"
            case .corrupted:
                return "xmark.circle.fill"
            }
        } else {
            return "doc.fill"
        }
    }
    
    private var colorForFile: Color {
        if let result = verificationResult {
            switch result.status {
            case .valid:
                return .green
            case .empty:
                return .orange
            case .corrupted:
                return .red
            }
        } else {
            return .blue
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
    
    private func shareFile() {
        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        // Read the file data and share it directly as Data with proper type identifier
        guard let data = try? Data(contentsOf: fileURL) else {
            print("Could not read file data")
            return
        }
        
        // Create a temporary item provider
        let itemProvider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.json.identifier)
        itemProvider.suggestedName = fileURL.lastPathComponent
        
        // Create activity view controller with the data
        let activityVC = UIActivityViewController(
            activityItems: [itemProvider],
            applicationActivities: nil
        )
        
        // Exclude incompatible activities
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact
        ]
        
        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, 
                                       y: rootViewController.view.bounds.midY, 
                                       width: 0, 
                                       height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Present
        rootViewController.present(activityVC, animated: true)
    }
}

// MARK: - Share Sheet View

struct ShareSheetView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showingActivityVC = false
    @State private var shareCompleted = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: shareCompleted ? "checkmark.circle.fill" : "doc.badge.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundColor(shareCompleted ? .green : .blue)
                    .animation(.spring(), value: shareCompleted)
                
                Text(shareCompleted ? "Backup Shared" : "Backup Created")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if !shareCompleted {
                    // Use native ShareLink which handles file URLs better
                    ShareLink(item: url) {
                        Label("Share Backup File", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .simultaneousGesture(TapGesture().onEnded {
                        // Mark as completed when tapped
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            shareCompleted = true
                        }
                    })
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingActivityVC) {
                // Ensure the file URL is accessible
                if FileManager.default.fileExists(atPath: url.path) {
                    ActivityViewController(
                        activityItems: [url],
                        onComplete: {
                            shareCompleted = true
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    Text("Error: File not found")
                        .padding()
                }
            }
        }
    }
}

// MARK: - Activity View Controller (Fallback)

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    var onComplete: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Prepare the file URL for sharing
        var itemsToShare: [Any] = []
        
        for item in activityItems {
            if let url = item as? URL {
                // Ensure file URL is accessible
                if url.startAccessingSecurityScopedResource() {
                    // Will stop accessing when done
                }
                itemsToShare.append(url)
            } else {
                itemsToShare.append(item)
            }
        }
        
        let controller = UIActivityViewController(
            activityItems: itemsToShare,
            applicationActivities: applicationActivities
        )
        
        // Exclude activities that might not work well with JSON files
        controller.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .postToFlickr,
            .postToVimeo,
            .postToWeibo,
            .postToTencentWeibo
        ]
        
        // Completion handler to clean up and prevent crashes
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            // Stop accessing security-scoped resources
            for item in activityItems {
                if let url = item as? URL {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if let error = error {
                print("Share error: \(error.localizedDescription)")
            }
            
            // Call completion handler
            onComplete?()
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

// MARK: - File Item Source for Sharing

class FileItemSource: NSObject, UIActivityItemSource {
    let fileURL: URL
    let filename: String
    
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
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "WarDragon Backup - \(filename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.json"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DatabaseManagementView()
            .modelContainer(for: [StoredDroneEncounter.self, StoredADSBEncounter.self])
    }
}
