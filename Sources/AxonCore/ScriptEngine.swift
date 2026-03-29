import Foundation

/// Script execution engine for AppleScript and JXA (JavaScript for Automation).
/// Layer 1 automation — most reliable for apps with scripting dictionaries.
public final class ScriptEngine: Sendable {

    public init() {}

    /// Execute an AppleScript string, returning the output.
    public func runAppleScript(_ script: String) async throws -> String {
        try await runOsascript(language: "AppleScript", script: script)
    }

    /// Execute a JXA (JavaScript for Automation) string, returning the output.
    public func runJXA(_ script: String) async throws -> String {
        try await runOsascript(language: "JavaScript", script: script)
    }

    /// Execute a pre-built recipe by name with parameters.
    /// Recipes are common automation patterns (e.g., "open_url", "set_volume").
    public func runRecipe(_ name: String, params: [String: String] = [:]) async throws -> String {
        guard let script = Self.recipes[name] else {
            throw AxonError.scriptError("Unknown recipe: \(name)")
        }
        var expanded = script
        for (key, value) in params {
            // Escape for AppleScript string safety
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            expanded = expanded.replacingOccurrences(of: "{{\(key)}}", with: escaped)
        }
        return try await runAppleScript(expanded)
    }

    // MARK: - Script Sandbox

    /// Validate a script for shell escape patterns.
    /// Returns an error message if the script is rejected, or nil if it passes.
    public static func validateScript(_ script: String) -> String? {
        let denied: [(pattern: String, reason: String)] = [
            ("do shell script", "shell command execution via 'do shell script'"),
            ("system(", "shell command execution via 'system()'"),
            ("NSTask", "process spawning via NSTask"),
            ("Process(", "process spawning via Process"),
            ("NSAppleScript", "nested script execution via NSAppleScript"),
            ("run script", "nested script execution via 'run script'"),
            ("sh -c", "shell command via 'sh -c'"),
            ("/bin/", "direct binary execution"),
            ("/usr/bin/", "direct binary execution"),
        ]
        let lower = script.lowercased()
        for entry in denied {
            if lower.contains(entry.pattern.lowercased()) {
                return "Blocked: \(entry.reason)"
            }
        }
        return nil
    }

    // MARK: - Internal

    private func runOsascript(language: String, script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", language, "-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw AxonError.scriptError(errStr)
        }

        return String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Built-in Recipes

    private static let recipes: [String: String] = [
        "open_url": """
            tell application "Safari"
                open location "{{url}}"
                activate
            end tell
            """,
        "set_volume": """
            set volume output volume {{level}}
            """,
        "get_frontmost_app": """
            tell application "System Events"
                set frontApp to name of first application process whose frontmost is true
            end tell
            return frontApp
            """,
        "notification": """
            display notification "{{message}}" with title "{{title}}"
            """,
        "get_clipboard": """
            return the clipboard
            """,
        "set_clipboard": """
            set the clipboard to "{{text}}"
            """,
    ]
}
