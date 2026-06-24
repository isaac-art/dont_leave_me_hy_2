import SwiftUI
import AppKit

/// Always-available log console (hysteria stdout/stderr, proxy + connect errors).
/// Survives connect failures, so you can see *why* something failed.
struct LogView: View {
    @EnvironmentObject var manager: ProxyManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                Text("Hysteria Log").font(.headline)
                Spacer()
                Button {
                    manager.revealLog()
                } label: { Label("Reveal File", systemImage: "folder") }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(manager.logLines.joined(separator: "\n"), forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    manager.clearLog()
                } label: { Label("Clear", systemImage: "trash") }
            }
            .padding(10)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if manager.logLines.isEmpty {
                            Text("No log output yet. Try connecting — any error will appear here.")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            Text(manager.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: manager.logLines.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 580, minHeight: 380)
    }
}
