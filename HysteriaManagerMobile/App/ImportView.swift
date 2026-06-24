import SwiftUI
import UIKit

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var preview: [Connection] = []

    let onImport: ([Connection]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Paste one or more hysteria2:// / hy2:// links (one per line).")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .frame(height: 160)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: text) { _, newValue in
                            preview = URIParser.parseMany(newValue)
                        }
                    Button {
                        if let clip = UIPasteboard.general.string {
                            text = clip
                            preview = URIParser.parseMany(clip)
                        }
                    } label: { Label("Paste from Clipboard", systemImage: "doc.on.clipboard") }
                }
                if !text.isEmpty {
                    Section("Detected") {
                        if preview.isEmpty {
                            Text("No valid links found").foregroundStyle(.red)
                        }
                        ForEach(preview) { c in
                            VStack(alignment: .leading) {
                                Text(c.name)
                                Text(c.host).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { onImport(preview); dismiss() }
                        .disabled(preview.isEmpty)
                }
            }
        }
    }
}
