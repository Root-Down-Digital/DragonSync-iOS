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
    @State private var showRestoreSheet = false
    @State private var showExportShare = false
    @State private var exportedFileURL: URL?
    @State private var backupVerificationResults: [BackupVerificationResult] = []
    @State private var showVerificationResults = false
    
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
                        BackupFileRow(
                            fileURL: fileURL,
                            verificationResult: backupVerificationResults.first { $0.url == fileURL },
                            onDelete: {
                                fileToDelete = fileURL
                                showDeleteConfirmation = true
                            },
                            onRestore: {
                                fileToRestore = fileURL
                                showRestoreConfirmation = true
                            },
                            onShare: {
                                exportedFileURL = fileURL
                                showExportShare = true
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
            Text("⚠️ This will permanently delete all \(stats?.encounterCount ?? 0) encounters and cannot be undone. Make sure you have a backup!")
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
            try? await Task.sleep(for: .milliseconds(100))
            
            // Show share sheet on main thread
            await MainActor.run {
                exportedFileURL = url
                showExportShare = true
            }
            
            successMessage = "Backup created successfully!\n\(url.lastPathComponent)"
            showSuccess = true
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
            var message = "✅ Backup restored successfully!\n\n"
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
    
    private func verifyBackups() {
        backupVerificationResults = migrationManager.verifyAllBackups()
        
        let validCount = backupVerificationResults.filter { $0.status == .valid }.count
        let emptyCount = backupVerificationResults.filter { $0.status == .empty }.count
        let corruptedCount = backupVerificationResults.filter { $0.status == .corrupted }.count
        
        var message = "Backup Verification Complete:\n"
        message += "\(validCount) valid backup\(validCount == 1 ? "" : "s")\n"
        if emptyCount > 0 {
            message += "⚠️ \(emptyCount) empty backup\(emptyCount == 1 ? "" : "s")\n"
        }
        if corruptedCount > 0 {
            message += "\(corruptedCount) corrupted backup\(corruptedCount == 1 ? "" : "s")"
        }
        
        successMessage = message
        showSuccess = true
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
    let verificationResult: BackupVerificationResult?
    let onDelete: () -> Void
    let onRestore: () -> Void
    let onShare: () -> Void
    
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
                Text("⚠️ \(error)")
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
                
                Button {
                    // Add small delay to ensure proper presentation
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        onShare()
                    }
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
}

// MARK: - Share Sheet View

struct ShareSheetView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showingActivityVC = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Backup Created")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button {
                    showingActivityVC = true
                } label: {
                    Label("Share Backup File", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
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
                ActivityViewController(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Activity View Controller (Fallback)

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        // Completion handler to prevent crashes
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Handle completion if needed
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DatabaseManagementView()
            .modelContainer(for: [StoredDroneEncounter.self])
    }
}
