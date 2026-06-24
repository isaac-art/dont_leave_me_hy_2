import Foundation

/// Finds the `hysteria` executable. Checks a user-provided path first, then the
/// usual Homebrew / system locations, then asks the login shell for it via `which`.
enum BinaryLocator {
    static let commonPaths = [
        "/opt/homebrew/bin/hysteria",   // Apple Silicon Homebrew
        "/usr/local/bin/hysteria",      // Intel Homebrew
        "/opt/local/bin/hysteria",      // MacPorts
        "/usr/bin/hysteria",
    ]

    /// Returns an absolute path to a runnable hysteria binary, or nil.
    /// Order: explicit user path → Homebrew/system locations → bundled binary
    /// (fallback only) → login-shell PATH.
    static func locate(custom: String) -> String? {
        let fm = FileManager.default
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, fm.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        // Prefer a Homebrew/system install (kept up to date via `brew upgrade`).
        for path in commonPaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Bundled binary is only a fallback when nothing is installed.
        if let bundled = bundledPath() {
            return bundled
        }
        // Fall back to the user's login shell PATH (covers custom Homebrew prefixes).
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let result = Shell.run(shell, ["-l", "-c", "command -v hysteria"])
        let found = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !found.isEmpty, fm.isExecutableFile(atPath: found) {
            return found
        }
        return nil
    }

    /// Looks for a `hysteria` executable bundled inside the .app. Checks the common
    /// embed locations: Resources/, Contents/Helpers/, and Contents/MacOS/.
    static func bundledPath() -> String? {
        let fm = FileManager.default
        if let url = Bundle.main.url(forResource: "hysteria", withExtension: nil),
           fm.isExecutableFile(atPath: url.path) {
            return url.path
        }
        var candidates: [URL] = []
        if let helpers = Bundle.main.builtInPlugInsURL?.deletingLastPathComponent()
            .appendingPathComponent("Helpers/hysteria") {
            candidates.append(helpers)
        }
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exeDir.appendingPathComponent("hysteria"))          // Contents/MacOS
            candidates.append(exeDir.deletingLastPathComponent()
                .appendingPathComponent("Helpers/hysteria"))                       // Contents/Helpers
        }
        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url.path
        }
        return nil
    }

    /// True when a hysteria binary is bundled in the app.
    static var hasBundledBinary: Bool { bundledPath() != nil }

    /// Reads the installed hysteria version string, if available.
    static func version(at path: String) -> String? {
        let result = Shell.run(path, ["version"])
        let text = result.stdout.isEmpty ? result.stderr : result.stdout
        // Pull the first "vX.Y.Z" looking token.
        for line in text.split(separator: "\n") {
            if line.lowercased().contains("version") {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return text.split(separator: "\n").first.map(String.init)
    }
}
