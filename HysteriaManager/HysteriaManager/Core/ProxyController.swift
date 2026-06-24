import Foundation

/// Toggles the macOS system proxy across every network service.
///
/// Setting proxies needs root. Two paths:
///  1. **Passwordless (preferred):** if a one-time `sudoers` rule is installed
///     (`installPasswordlessRule()`), each `networksetup` call runs via `sudo -n`
///     with NO prompt.
///  2. **Fallback:** batch the calls into one `osascript … with administrator
///     privileges`, which shows the standard auth prompt.
///
/// So the user authorizes ONCE (to install the rule) and is never prompted again.
enum ProxyController {

    private static let sudoersPath = "/etc/sudoers.d/hysteriamanager"
    private static let networksetup = "/usr/sbin/networksetup"

    // MARK: - Enable / disable

    static func enable(socksPort: Int, httpPort: Int) -> Result<Void, ProxyError> {
        let services = networkServices()
        guard !services.isEmpty else { return .failure(.noServices) }
        var cmds: [[String]] = []
        for svc in services {
            cmds.append(["-setsocksfirewallproxy", svc, "127.0.0.1", "\(socksPort)"])
            cmds.append(["-setsocksfirewallproxystate", svc, "on"])
            cmds.append(["-setwebproxy", svc, "127.0.0.1", "\(httpPort)"])
            cmds.append(["-setwebproxystate", svc, "on"])
            cmds.append(["-setsecurewebproxy", svc, "127.0.0.1", "\(httpPort)"])
            cmds.append(["-setsecurewebproxystate", svc, "on"])
        }
        return run(cmds)
    }

    static func disable() -> Result<Void, ProxyError> {
        let services = networkServices()
        guard !services.isEmpty else { return .success(()) }
        var cmds: [[String]] = []
        for svc in services {
            cmds.append(["-setsocksfirewallproxystate", svc, "off"])
            cmds.append(["-setwebproxystate", svc, "off"])
            cmds.append(["-setsecurewebproxystate", svc, "off"])
        }
        return run(cmds)
    }

    // MARK: - Passwordless setup (one-time)

    /// True when the sudoers rule is installed and `networksetup` can run without a prompt.
    static var isPasswordlessEnabled: Bool {
        let r = Shell.run("/usr/bin/sudo", ["-n", "-l", networksetup])
        return r.status == 0
    }

    /// Installs a sudoers rule allowing the current user to run `networksetup`
    /// without a password. Shows ONE admin prompt. Returns success/failure.
    static func installPasswordlessRule() -> Result<Void, ProxyError> {
        let user = NSUserName()
        let rule = "# Added by HysteriaManager — passwordless system-proxy switching\\n\(user) ALL=(root) NOPASSWD: \(networksetup)\\n"
        // Write atomically to a temp file, validate with visudo, then move into place.
        let shell = """
        umask 226; \
        printf '%b' "\(rule)" > /tmp/.hm_sudoers && \
        visudo -cf /tmp/.hm_sudoers && \
        install -m 0440 -o root -g wheel /tmp/.hm_sudoers \(sudoersPath) && \
        rm -f /tmp/.hm_sudoers
        """
        return runAdmin(shell)
    }

    /// Removes the sudoers rule (one admin prompt).
    static func removePasswordlessRule() -> Result<Void, ProxyError> {
        runAdmin("rm -f \(sudoersPath)")
    }

    // MARK: - Errors

    enum ProxyError: LocalizedError {
        case noServices
        case authFailed(String)
        var errorDescription: String? {
            switch self {
            case .noServices: return "No active network services were found."
            case .authFailed(let m): return "System proxy update failed: \(m)"
            }
        }
    }

    // MARK: - Internals

    private static func run(_ cmds: [[String]]) -> Result<Void, ProxyError> {
        if isPasswordlessEnabled {
            for args in cmds {
                let r = Shell.run("/usr/bin/sudo", ["-n", networksetup] + args)
                if r.status != 0 {
                    return .failure(.authFailed(r.stderr.isEmpty ? "exit \(r.status)" : r.stderr))
                }
            }
            return .success(())
        }
        // Fallback: one admin prompt for the whole batch.
        let script = cmds
            .map { args in ([networksetup] + args).map(shellQuote).joined(separator: " ") }
            .joined(separator: " && ")
        return runAdmin(script)
    }

    private static func runAdmin(_ shellScript: String) -> Result<Void, ProxyError> {
        let escaped = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges"
        let r = Shell.runAppleScript(apple)
        if r.status == 0 { return .success(()) }
        return .failure(.authFailed(r.stderr.isEmpty ? "exit \(r.status)" : r.stderr))
    }

    /// All enabled network services (skips the `*`-prefixed disabled ones).
    private static func networkServices() -> [String] {
        let result = Shell.run(networksetup, ["-listallnetworkservices"])
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.lowercased().contains("an asterisk") }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
