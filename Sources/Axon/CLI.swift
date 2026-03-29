import ArgumentParser
import AxonCore
import CoreGraphics
import Foundation

let axonVersion = "0.1.0"

@main
struct AxonCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axon",
        abstract: "macOS computer use — desktop automation CLI",
        version: axonVersion,
        subcommands: [
            Serve.self, Run.self, Permissions.self,
            Apps.self, Launch.self, Activate.self, QuitApp.self,
            Type.self, Key.self,
            Click.self, DoubleClick.self, RightClick.self, Move.self, Scroll.self, Drag.self,
            Screenshot.self, ScreenInfoCmd.self, CursorPos.self,
            UITree.self, Find.self, Wait.self, Text.self, Perform.self,
            ClipboardGet.self, ClipboardSet.self,
            ActiveWindow.self, MoveWindow.self, ResizeWindow.self,
            Script.self, JXA.self,
        ],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Shared Query Options

struct QueryOptions: ParsableArguments {
    @Option(name: .long, help: "AX role (e.g. AXButton, AXTextField)")
    var role: String?

    @Option(name: .long, help: "Element title")
    var title: String?

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element value")
    var value: String?

    @Option(name: .long, help: "Match mode: exact, contains, prefix, regex")
    var match: String?

    @Option(name: .long, help: "Element index when multiple matches")
    var index: Int?

    func toQuery() -> ElementQuery {
        ElementQuery(
            role: role, title: title, identifier: identifier, value: value,
            index: index, matchMode: match.flatMap { MatchMode(rawValue: $0) }
        )
    }

    var hasAnyField: Bool {
        role != nil || title != nil || identifier != nil || value != nil
    }
}

// MARK: - Output Helpers

/// Check if JSON output is requested via --json flag or AXON_OUTPUT=json env var.
/// This makes all commands agent-friendly without needing --json on every subcommand.
func isJsonOutput(_ flagValue: Bool = false) -> Bool {
    flagValue || ProcessInfo.processInfo.environment["AXON_OUTPUT"]?.lowercased() == "json"
}

func printResult(_ result: ActionResult, jsonOutput: Bool = false) throws {
    if isJsonOutput(jsonOutput) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
        return
    }

    guard result.success else {
        printError(result.error ?? "Unknown error")
        return
    }

    guard let data = result.data else {
        print("OK")
        return
    }

    switch data {
    case .apps(let apps):
        if apps.isEmpty {
            print("No running apps")
        } else {
            let maxName = max(apps.map { $0.name.count }.max() ?? 4, 4)
            print("NAME".padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
                  + "BUNDLE ID".padding(toLength: 40, withPad: " ", startingAt: 0)
                  + "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
                  + "ACTIVE")
            for app in apps {
                print(app.name.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
                      + app.bundleId.padding(toLength: 40, withPad: " ", startingAt: 0)
                      + String(app.pid).padding(toLength: 8, withPad: " ", startingAt: 0)
                      + (app.isActive ? "✓" : ""))
            }
        }

    case .tree(let node):
        printTree(node, indent: 0)

    case .element(let node):
        printElement(node)

    case .screenshot(let base64, let width, let height):
        // Save to file
        let filename = "axon-screenshot-\(Int(Date().timeIntervalSince1970)).jpg"
        let path = FileManager.default.currentDirectoryPath + "/" + filename
        if let data = Data(base64Encoded: base64) {
            try data.write(to: URL(fileURLWithPath: path))
            print("Screenshot saved: \(filename) (\(width)x\(height))")
        }

    case .scriptOutput(let output):
        print(output)

    case .text(let text):
        print(text)

    case .none:
        print("OK")

    case .cursorPosition(let x, let y):
        print("(\(Int(x)), \(Int(y)))")

    case .screenInfo(let info):
        print("Displays: \(info.displayCount)")
        for d in info.displays {
            print("  [\(d.index)] \(d.width)x\(d.height)\(d.isMain ? " (main)" : "")")
        }

    case .windowInfo(let info):
        print("App:    \(info.appName) (\(info.bundleId))")
        if let t = info.windowTitle { print("Window: \(t)") }
        print("PID:    \(info.pid)")
        if let pos = info.position { print("Pos:    (\(Int(pos.x)), \(Int(pos.y)))") }
        if let size = info.size { print("Size:   \(Int(size.width))x\(Int(size.height))") }
    }
}

func printError(_ message: String) {
    FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
}

func printTree(_ node: AXNode, indent: Int) {
    let pad = String(repeating: "  ", count: indent)
    var line = "\(pad)[\(node.role)]"
    if let t = node.title, !t.isEmpty { line += " \"\(t)\"" }
    if let v = node.value, !v.isEmpty { line += " value=\"\(v)\"" }
    if let id = node.identifier, !id.isEmpty { line += " id=\(id)" }
    if let pos = node.position, let size = node.size {
        line += " (\(Int(pos.x)),\(Int(pos.y)) \(Int(size.width))x\(Int(size.height)))"
    }
    if !node.actions.isEmpty {
        line += " actions=[\(node.actions.joined(separator: ","))]"
    }
    print(line)
    if let children = node.children {
        for child in children {
            printTree(child, indent: indent + 1)
        }
    }
}

func printElement(_ node: AXNode) {
    print("Role:       \(node.role)")
    if let t = node.title { print("Title:      \(t)") }
    if let v = node.value { print("Value:      \(v)") }
    if let id = node.identifier { print("Identifier: \(id)") }
    if let sr = node.subrole { print("Subrole:    \(sr)") }
    if let d = node.description { print("Description:\(d)") }
    if let pos = node.position, let size = node.size {
        print("Position:   (\(Int(pos.x)), \(Int(pos.y)))")
        print("Size:       \(Int(size.width))x\(Int(size.height))")
    }
    if let e = node.enabled { print("Enabled:    \(e)") }
    if let f = node.focused { print("Focused:    \(f)") }
    if !node.actions.isEmpty { print("Actions:    \(node.actions.joined(separator: ", "))") }
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

// MARK: - Run (raw JSON)

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Execute a single action from JSON")

    @Argument(help: "Action JSON string")
    var actionJson: String

    func run() async throws {
        let controller = AxonController()
        let action = try JSONDecoder().decode(ComputerAction.self, from: actionJson.data(using: .utf8)!)
        let result = await controller.execute(action)
        try printResult(result, jsonOutput: true)
    }
}

// MARK: - Permissions

struct Permissions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check and request macOS permissions")

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let ax = AXEngine()
        let hasAX = ax.checkAccessibilityPermission()

        // Test Screen Recording by trying to list windows
        let hasScreenRecording = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, kCGNullWindowID) != nil

        if isJsonOutput(json) {
            let status: [String: Any] = [
                "accessibility": hasAX,
                "screenRecording": hasScreenRecording,
                "allGranted": hasAX && hasScreenRecording,
            ]
            let data = try JSONSerialization.data(withJSONObject: status, options: .prettyPrinted)
            print(String(data: data, encoding: .utf8)!)
            return
        }

        print("macOS Permissions Status:")
        print("  Accessibility:    \(hasAX ? "✓ Granted" : "✗ Not granted")")
        print("  Screen Recording: \(hasScreenRecording ? "✓ Granted" : "✗ Not granted")")
        print("")

        if hasAX && hasScreenRecording {
            print("All permissions granted. Ready to use.")
        } else {
            print("Required permissions:")
            if !hasAX {
                print("  • Accessibility — System Settings > Privacy & Security > Accessibility")
                print("    (needed for: UI element control, keyboard/mouse simulation)")
            }
            if !hasScreenRecording {
                print("  • Screen Recording — System Settings > Privacy & Security > Screen Recording")
                print("    (needed for: screenshots)")
            }
            print("")
            if !hasAX {
                print("Requesting Accessibility permission...")
                ax.requestAccessibilityPermission()
            }
        }
    }
}

// MARK: - Apps

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List running GUI applications")

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.listApps)
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Launch

struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch an application by bundle ID")

    @Argument(help: "Bundle ID (e.g. com.netease.163music)")
    var bundleId: String

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.launchApp(bundleId: bundleId))
        if result.success {
            print("Launched \(bundleId)")
        } else {
            printError(result.error ?? "Failed to launch")
        }
    }
}

// MARK: - Activate

struct Activate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Bring an application to front")

    @Argument(help: "Bundle ID")
    var bundleId: String

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.activateApp(bundleId: bundleId))
        if result.success {
            print("Activated \(bundleId)")
        } else {
            printError(result.error ?? "Failed to activate")
        }
    }
}

// MARK: - Quit

struct QuitApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quit",
        abstract: "Quit an application"
    )

    @Argument(help: "Bundle ID")
    var bundleId: String

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.quitApp(bundleId: bundleId))
        if result.success {
            print("Quit \(bundleId)")
        } else {
            printError(result.error ?? "Failed to quit")
        }
    }
}

// MARK: - Type

struct Type: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Type text (supports Chinese/CJK). Optionally target a specific UI element."
    )

    @Argument(help: "Text to type (Chinese, English, etc.)")
    var text: String

    @Option(name: .long, help: "Target app bundle ID (for typing into a specific element)")
    var app: String?

    @OptionGroup var query: QueryOptions

    func run() async throws {
        let controller = AxonController()
        let action: ComputerAction
        if let bundleId = app, query.hasAnyField {
            action = .typeIntoElement(bundleId: bundleId, query: query.toQuery(), text: text)
        } else {
            action = .typeText(text: text)
        }
        let result = await controller.execute(action)
        if result.success {
            print("Typed: \(text)")
        } else {
            printError(result.error ?? "Failed to type")
        }
    }
}

// MARK: - Key

struct Key: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Press a key combination")

    @Argument(help: "Key name (e.g. return, tab, space, a, f5)")
    var key: String

    @Option(name: .shortAndLong, help: "Modifier keys, comma-separated (e.g. command,shift)")
    var modifiers: String?

    func run() async throws {
        let controller = AxonController()
        let mods = modifiers?.split(separator: ",").map(String.init)
        let result = await controller.execute(.pressKey(key: key, modifiers: mods))
        if result.success {
            var desc = key
            if let m = modifiers { desc = "\(m)+\(key)" }
            print("Pressed: \(desc)")
        } else {
            printError(result.error ?? "Failed to press key")
        }
    }
}

// MARK: - Click

struct Click: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Click at coordinates or on a UI element"
    )

    @Argument(help: "X coordinate (when clicking at position)")
    var x: Double?

    @Argument(help: "Y coordinate (when clicking at position)")
    var y: Double?

    @Option(name: .long, help: "Target app bundle ID (for clicking a UI element)")
    var app: String?

    @OptionGroup var query: QueryOptions

    func run() async throws {
        let controller = AxonController()
        let action: ComputerAction
        if let bundleId = app, query.hasAnyField {
            action = .clickElement(bundleId: bundleId, query: query.toQuery())
        } else if let x, let y {
            action = .clickAt(x: x, y: y)
        } else {
            printError("Provide (x y) coordinates or (--app with --role/--title)")
            return
        }
        let result = await controller.execute(action)
        if !result.success {
            printError(result.error ?? "Click failed")
        } else {
            print("OK")
        }
    }
}

// MARK: - DoubleClick

struct DoubleClick: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "double-click",
        abstract: "Double-click at coordinates"
    )

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.doubleClickAt(x: x, y: y))
        if !result.success { printError(result.error ?? "Failed") }
        else { print("OK") }
    }
}

// MARK: - RightClick

struct RightClick: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "right-click",
        abstract: "Right-click at coordinates"
    )

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.rightClickAt(x: x, y: y))
        if !result.success { printError(result.error ?? "Failed") }
        else { print("OK") }
    }
}

// MARK: - Move

struct Move: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Move mouse to coordinates")

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.moveMouse(x: x, y: y))
        if !result.success { printError(result.error ?? "Failed") }
        else { print("OK") }
    }
}

// MARK: - Scroll

struct Scroll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Scroll at a position")

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    @Argument(help: "Direction: up, down, left, right")
    var direction: String

    @Option(name: .shortAndLong, help: "Scroll amount (default: 3)")
    var amount: Int = 3

    func run() async throws {
        guard let dir = ScrollDirection(rawValue: direction) else {
            printError("Invalid direction: \(direction). Use: up, down, left, right")
            return
        }
        let controller = AxonController()
        let result = await controller.execute(.scroll(x: x, y: y, direction: dir, amount: amount))
        if !result.success { printError(result.error ?? "Failed") }
        else { print("OK") }
    }
}

// MARK: - Screenshot

struct Screenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture screenshot of display or window")

    @Option(name: .long, help: "Display index (default: main display)")
    var display: Int?

    @Option(name: .long, help: "Capture specific app window by bundle ID")
    var app: String?

    @Option(name: .long, help: "Window title filter (used with --app)")
    var title: String?

    @Option(name: .shortAndLong, help: "Output file path (default: auto-generated in current dir)")
    var output: String?

    @Option(name: .long, help: "Capture region: x,y,width,height (e.g. 0,0,800,600)")
    var region: String?

    @Flag(name: .long, help: "Output base64 to stdout instead of saving file")
    var base64: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let controller = AxonController()
        let action: ComputerAction
        if let regionStr = region {
            let parts = regionStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else {
                printError("Region format: x,y,width,height (e.g. 0,0,800,600)")
                return
            }
            action = .regionScreenshot(x: parts[0], y: parts[1], width: parts[2], height: parts[3], displayId: display)
        } else if let bundleId = app {
            action = .windowScreenshot(bundleId: bundleId, title: title)
        } else {
            action = .screenshot(displayId: display)
        }

        let result = await controller.execute(action)

        if json {
            try printResult(result, jsonOutput: true)
            return
        }

        guard result.success, case .screenshot(let b64, let width, let height) = result.data else {
            printError(result.error ?? "Screenshot failed")
            return
        }

        if base64 {
            print(b64)
            return
        }

        // Save to file
        guard let imageData = Data(base64Encoded: b64) else {
            printError("Failed to decode image data")
            return
        }
        let filePath: String
        if let output {
            filePath = output
        } else {
            let filename = "axon-screenshot-\(Int(Date().timeIntervalSince1970)).jpg"
            filePath = FileManager.default.currentDirectoryPath + "/" + filename
        }
        try imageData.write(to: URL(fileURLWithPath: filePath))
        print("Screenshot saved: \(filePath) (\(width)x\(height))")
    }
}

// MARK: - UI Tree

struct UITree: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui-tree",
        abstract: "Get the accessibility UI tree of an application"
    )

    @Argument(help: "Bundle ID")
    var bundleId: String

    @Option(name: .shortAndLong, help: "Max depth (default: 4)")
    var depth: Int = 4

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.getUITree(bundleId: bundleId, maxDepth: depth))
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Find

struct Find: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Find a UI element in an application")

    @Argument(help: "Bundle ID")
    var bundleId: String

    @OptionGroup var query: QueryOptions

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        guard query.hasAnyField else {
            printError("Provide at least one query field: --role, --title, --identifier, --value")
            return
        }
        let controller = AxonController()
        let result = await controller.execute(.findElement(bundleId: bundleId, query: query.toQuery()))
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Wait

struct Wait: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for a UI element to appear")

    @Argument(help: "Bundle ID")
    var bundleId: String

    @OptionGroup var query: QueryOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds (default: 10)")
    var timeout: Double = 10.0

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        guard query.hasAnyField else {
            printError("Provide at least one query field: --role, --title, --identifier, --value")
            return
        }
        let controller = AxonController()
        let result = await controller.execute(
            .waitForElement(bundleId: bundleId, query: query.toQuery(), timeout: timeout)
        )
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Text (get element text)

struct Text: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Get text content of a UI element")

    @Argument(help: "Bundle ID")
    var bundleId: String

    @OptionGroup var query: QueryOptions

    func run() async throws {
        guard query.hasAnyField else {
            printError("Provide at least one query field: --role, --title, --identifier, --value")
            return
        }
        let controller = AxonController()
        let result = await controller.execute(
            .getElementText(bundleId: bundleId, query: query.toQuery())
        )
        try printResult(result)
    }
}

// MARK: - Perform (AX action)

struct Perform: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Perform an accessibility action on an element")

    @Argument(help: "Bundle ID")
    var bundleId: String

    @Argument(help: "AX action name (e.g. AXPress, AXShowMenu)")
    var action: String

    @OptionGroup var query: QueryOptions

    func run() async throws {
        guard query.hasAnyField else {
            printError("Provide at least one query field: --role, --title, --identifier, --value")
            return
        }
        let controller = AxonController()
        let result = await controller.execute(
            .performAction(bundleId: bundleId, query: query.toQuery(), action: action)
        )
        if result.success {
            print("OK")
        } else {
            printError(result.error ?? "Action failed")
        }
    }
}

// MARK: - Script

struct Script: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run an AppleScript")

    @Argument(help: "AppleScript code")
    var code: String

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.runAppleScript(script: code))
        try printResult(result)
    }
}

// MARK: - JXA

struct JXA: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jxa",
        abstract: "Run JavaScript for Automation (JXA)"
    )

    @Argument(help: "JXA code")
    var code: String

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.runJXA(script: code))
        try printResult(result)
    }
}

// MARK: - Drag

struct Drag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Drag from one position to another")

    @Argument(help: "Start X")
    var fromX: Double

    @Argument(help: "Start Y")
    var fromY: Double

    @Argument(help: "End X")
    var toX: Double

    @Argument(help: "End Y")
    var toY: Double

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY))
        if !result.success { printError(result.error ?? "Failed") }
        else { print("OK") }
    }
}

// MARK: - Cursor Position

struct CursorPos: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cursor-pos",
        abstract: "Get current cursor position"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.getCursorPosition)
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Screen Info

struct ScreenInfoCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screen-info",
        abstract: "Get display information (resolution, count)"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.getScreenInfo)
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Clipboard

struct ClipboardGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipboard-get",
        abstract: "Read text from clipboard"
    )

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.clipboardRead)
        try printResult(result)
    }
}

struct ClipboardSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipboard-set",
        abstract: "Write text to clipboard"
    )

    @Argument(help: "Text to write to clipboard")
    var text: String

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.clipboardWrite(text: text))
        if result.success { print("OK") }
        else { printError(result.error ?? "Failed") }
    }
}

// MARK: - Active Window

struct ActiveWindow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "active-window",
        abstract: "Get information about the currently active window"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.getActiveWindow)
        try printResult(result, jsonOutput: json)
    }
}

// MARK: - Move Window

struct MoveWindow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move-window",
        abstract: "Move a window to a position"
    )

    @Argument(help: "Bundle ID")
    var bundleId: String

    @Argument(help: "X position")
    var x: Double

    @Argument(help: "Y position")
    var y: Double

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.moveWindow(bundleId: bundleId, x: x, y: y))
        if result.success { print("OK") }
        else { printError(result.error ?? "Failed") }
    }
}

// MARK: - Resize Window

struct ResizeWindow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize-window",
        abstract: "Resize a window"
    )

    @Argument(help: "Bundle ID")
    var bundleId: String

    @Argument(help: "Width")
    var width: Double

    @Argument(help: "Height")
    var height: Double

    func run() async throws {
        let controller = AxonController()
        let result = await controller.execute(.resizeWindow(bundleId: bundleId, width: width, height: height))
        if result.success { print("OK") }
        else { printError(result.error ?? "Failed") }
    }
}
