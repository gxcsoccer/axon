import ArgumentParser
import AxonCore
import Foundation

@main
struct AxonCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axon",
        abstract: "macOS computer use automation server",
        subcommands: [Serve.self, Run.self, Permissions.self],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Serve

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start the HTTP API server")

    @Option(name: .shortAndLong, help: "Host to bind to")
    var host: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 29170

    @Option(name: .shortAndLong, help: "Path to security config JSON")
    var config: String?

    @Option(name: .long, help: "Bearer token for API auth (auto-generated if not set)")
    var token: String?

    @Flag(name: .long, help: "Disable bearer token authentication")
    var noAuth: Bool = false

    func run() async throws {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/axon")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        var secConfig: SecurityConfig
        if let configPath = config {
            secConfig = SecurityConfig.load(from: URL(fileURLWithPath: configPath))
        } else {
            let defaultPath = configDir.appendingPathComponent("security.json")
            secConfig = SecurityConfig.load(from: defaultPath)
        }

        // Resolve auth token
        let authToken: String?
        if noAuth {
            authToken = nil
            print("Warning: Authentication disabled")
        } else if let t = token {
            authToken = t
        } else if let configToken = secConfig.authToken {
            authToken = configToken
        } else {
            // Auto-generate and persist
            let generated = UUID().uuidString
            authToken = generated
            secConfig.authToken = generated
            let configPath = configDir.appendingPathComponent("security.json")
            try secConfig.save(to: configPath)
        }

        if let authToken {
            // Also write to a standalone file for easy scripting
            let tokenPath = configDir.appendingPathComponent("auth-token")
            try authToken.write(to: tokenPath, atomically: true, encoding: .utf8)
            print("Auth token: \(authToken)")
            print("Token saved to ~/.config/axon/auth-token")
        }

        // Check accessibility permission before starting
        let axCheck = AXEngine()
        if !axCheck.checkAccessibilityPermission() {
            print("⚠ Accessibility permission not granted.")
            print("  Go to System Settings > Privacy & Security > Accessibility")
            print("  and add this application.")
            print("  Requesting permission now...")
            axCheck.requestAccessibilityPermission()
        }

        let controller = AxonController(config: secConfig, auditDir: configDir)

        print("Axon server starting on http://\(host):\(port)")
        print("Press Ctrl+C to stop")

        let app = buildServer(controller: controller, hostname: host, port: port, authToken: authToken)
        try await app.run()
    }
}

// MARK: - Run (single action)

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Execute a single action")

    @Argument(help: "Action JSON string")
    var actionJson: String

    func run() async throws {
        let controller = AxonController()
        let action = try JSONDecoder().decode(ComputerAction.self, from: actionJson.data(using: .utf8)!)
        let result = await controller.execute(action)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
    }
}

// MARK: - Permissions

struct Permissions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check macOS permissions status")

    func run() async throws {
        let ax = AXEngine()
        let hasAX = ax.checkAccessibilityPermission()

        print("macOS Permissions Status:")
        print("  Accessibility: \(hasAX ? "✓ Granted" : "✗ Not granted")")
        print("")
        print("Required permissions:")
        print("  • Accessibility — for UI element control (System Settings > Privacy & Security > Accessibility)")
        print("  • Screen Recording — for screenshots (System Settings > Privacy & Security > Screen Recording)")
        print("  • Input Monitoring — for keyboard/mouse simulation (may be auto-granted with Accessibility)")

        if !hasAX {
            print("")
            print("Requesting Accessibility permission...")
            ax.requestAccessibilityPermission()
        }
    }
}
