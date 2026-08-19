import SwiftUI
import UIKit

struct BackgroundDiagnosticsView: View {
    @ObservedObject private var diag = BackgroundDiagnostics.shared
    @State private var filter: BackgroundDiagnostics.Kind?

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm:ss"
        return f
    }()

    var body: some View {
        List {
            Section("Live State") {
                row("Listening", Settings.shared.isListening ? "yes" : "no")
                row("Background detection", Settings.shared.enableBackgroundDetection ? "enabled" : "disabled")
                row("Connection mode", "\(Settings.shared.connectionMode)")
                row("Audio keepalive", SilentAudioKeepAlive.shared.isRunning ? "engine running" : "engine STOPPED")
                row("Drain loop", BackgroundManager.shared.isBackgroundModeActive ? "active" : "idle")
                row("Background time", BackgroundDiagnostics.format(BackgroundDiagnostics.currentBackgroundTimeRemaining()))
                if let since = diag.secondsSinceLastPacket() {
                    row("Last packet", "\(Int(since))s ago")
                } else {
                    row("Last packet", "none received")
                }
                if diag.lastGapSeconds > 0 {
                    row("Last execution gap", "\(Int(diag.lastGapSeconds))s")
                }
            }

            if let off = diag.lastOffAirEvent {
                Section("Last Off-Air Event") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(off.event)
                            .font(.appHeadline)
                            .foregroundColor(.red)
                        Text(off.detail)
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                        Text("\(Self.stamp.string(from: off.t)) · \(relative(off.t)) · state=\(off.appState)")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Picker("Filter", selection: $filter) {
                    Text("All").tag(BackgroundDiagnostics.Kind?.none)
                    ForEach(BackgroundDiagnostics.Kind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(BackgroundDiagnostics.Kind?.some(kind))
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Event Log (\(visible.count))") {
                if visible.isEmpty {
                    Text("No events recorded yet")
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(visible) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: entry.kind.symbol)
                                .foregroundColor(color(entry.kind))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.event)
                                    .font(.appSubheadline)
                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.appCaption)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(Self.stamp.string(from: entry.t)) · \(entry.appState) · bg=\(BackgroundDiagnostics.format(entry.bgTimeRemaining))")
                                    .font(.appCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Background Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = diag.exportText()
                    } label: {
                        Label("Copy Log", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        diag.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var visible: [BackgroundDiagnostics.Entry] {
        guard let filter else { return diag.entries }
        return diag.entries.filter { $0.kind == filter }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.appSubheadline)
            Spacer()
            Text(value)
                .font(.appCaption)
                .foregroundColor(.secondary)
        }
    }

    private func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func color(_ kind: BackgroundDiagnostics.Kind) -> Color {
        switch kind {
        case .lifecycle: return .blue
        case .audio:     return .purple
        case .bgtask:    return .orange
        case .socket:    return .green
        case .memory:    return .yellow
        case .drop:      return .red
        case .heartbeat: return .gray
        case .gap:       return .red
        }
    }
}
