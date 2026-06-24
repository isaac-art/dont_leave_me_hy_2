import Foundation

/// Small helpers for running short-lived command-line tools and capturing output.
enum Shell {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Run a tool to completion and capture its output. Blocks the calling thread,
    /// so always invoke from a background queue / detached Task.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], environment: [String: String]? = nil) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        if let environment { proc.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "failed to launch \(launchPath): \(error.localizedDescription)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        return Result(
            status: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Run an AppleScript snippet via osascript, returning its stdout (or nil on error).
    /// Used for `do shell script ... with administrator privileges`, which surfaces the
    /// standard macOS auth prompt without us shipping a privileged helper.
    @discardableResult
    static func runAppleScript(_ source: String) -> Result {
        run("/usr/bin/osascript", ["-e", source])
    }
}
