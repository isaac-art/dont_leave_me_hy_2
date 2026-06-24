import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case uri = "Share Links"
        case yaml = "Raw YAML"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .uri
    @State private var text = ""
    @State private var yamlName = "Imported Connection"
    @State private var showFileImporter = false
    @State private var preview: [Connection] = []

    /// Called with the connections to add.
    let onImport: ([Connection]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Connections").font(.title3.weight(.semibold))

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .uri:
                Text("Paste one or more hysteria2:// / hy2:// links (one per line).")
                    .font(.caption).foregroundStyle(.secondary)
            case .yaml:
                Text("Paste a full hysteria client YAML config. It will be used verbatim.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Name", text: $yamlName)
            }

            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 480, height: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .onChange(of: text) { _, _ in updatePreview() }
                .onChange(of: mode) { _, _ in updatePreview() }

            if mode == .uri, !text.isEmpty {
                Text("\(preview.count) connection(s) detected")
                    .font(.caption).foregroundStyle(preview.isEmpty ? .red : .green)
            }

            HStack {
                Button("Open File…") { showFileImporter = true }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") { performImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "yaml") ?? .data, .text, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let contents = try? String(contentsOf: url, encoding: .utf8) {
                        text = contents
                        if contents.contains("server:") { mode = .yaml }
                        yamlName = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
        }
    }

    private var canImport: Bool {
        switch mode {
        case .uri:  return !preview.isEmpty
        case .yaml: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func updatePreview() {
        if mode == .uri { preview = URIParser.parseMany(text) }
    }

    private func performImport() {
        switch mode {
        case .uri:
            onImport(URIParser.parseMany(text))
        case .yaml:
            var c = Connection()
            c.name = yamlName.isEmpty ? "Imported Connection" : yamlName
            c.rawConfigOverride = text
            // Light parse for display fields.
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("server:") {
                    c.server = t.replacingOccurrences(of: "server:", with: "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                } else if t.hasPrefix("auth:") {
                    c.auth = t.replacingOccurrences(of: "auth:", with: "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
            onImport([c])
        }
        dismiss()
    }
}
