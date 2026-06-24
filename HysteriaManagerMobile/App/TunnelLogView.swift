import SwiftUI
import UIKit

/// Shows the sing-box tunnel log (stderr) written by the extension into the App Group.
/// This is where the *real* reason for "connected but no traffic" shows up.
struct TunnelLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var timer: Timer?

    private var boxLog: URL { AppGroup.cacheURL.appendingPathComponent("box.log") }
    private var stderrLog: URL { AppGroup.cacheURL.appendingPathComponent("stderr.log") }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "No log yet.\nConnect, then check back here." : text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Tunnel Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { load() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button(role: .destructive) { clear() } label: { Label("Clear", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear {
                load()
                timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in load() }
            }
            .onDisappear { timer?.invalidate(); timer = nil }
        }
    }

    private func load() {
        let box = (try? String(contentsOf: boxLog, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: stderrLog, encoding: .utf8)) ?? ""
        var combined = box
        if !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            combined += "\n----- stderr (crashes / panics) -----\n" + err
        }
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        text = lines.count > 500 ? lines.suffix(500).joined(separator: "\n") : combined
    }

    private func clear() {
        try? Data().write(to: boxLog)
        try? Data().write(to: stderrLog)
        text = ""
    }
}
