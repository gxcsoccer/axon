import Foundation

/// Main orchestrator that ties all engines together and routes actions
/// through the security layer.
public actor AxonController {
    public let axEngine: AXEngine
    public let input: InputSimulator
    public let screenCapture: ScreenCapture
    public let appManager: AppManager
    public let scriptEngine: ScriptEngine
    public let security: SecurityGate

    public init(config: SecurityConfig = SecurityConfig(), auditDir: URL? = nil) {
        self.axEngine = AXEngine()
        self.input = InputSimulator()
        self.screenCapture = ScreenCapture()
        self.appManager = AppManager()
        self.scriptEngine = ScriptEngine()
        self.security = SecurityGate(config: config, auditDir: auditDir)
    }

    /// Execute a ComputerAction with security checks.
    public func execute(_ action: ComputerAction) async -> ActionResult {
        let bundleId = action.targetBundleId

        // Read-only mode check
        if await security.getConfig().readOnlyMode && !action.isReadOnly {
            let reason = "Read-only mode: '\(action.name)' is a mutation action"
            await security.recordAction(action: action.name, targetApp: bundleId, details: reason, success: false)
            return .fail(reason)
        }

        // Security gate
        if let reason = await security.authorize(action: action.name, bundleId: bundleId) {
            await security.recordAction(action: action.name, targetApp: bundleId, details: reason, success: false)
            return .fail(reason)
        }

        do {
            let result = try await performAction(action)
            await security.recordAction(action: action.name, targetApp: bundleId, details: nil, success: true)
            return result
        } catch {
            let msg = error.localizedDescription
            await security.recordAction(action: action.name, targetApp: bundleId, details: msg, success: false)
            return .fail(msg)
        }
    }

    // MARK: - Action Dispatch

    private func performAction(_ action: ComputerAction) async throws -> ActionResult {
        switch action {
        case .launchApp(let bundleId):
            let info = try await appManager.launchApp(bundleId: bundleId)
            return .ok(.apps([info]))

        case .activateApp(let bundleId):
            try appManager.activateApp(bundleId: bundleId)
            return .ok(.none)

        case .listApps:
            let apps = appManager.listRunningApps()
            return .ok(.apps(apps))

        case .getUITree(let bundleId, let maxDepth):
            guard let tree = axEngine.getUITree(bundleId: bundleId, maxDepth: maxDepth ?? 4) else {
                return .fail("Could not read UI tree for \(bundleId)")
            }
            return .ok(.tree(tree))

        case .findElement(let bundleId, let query):
            guard let element = axEngine.findElement(bundleId: bundleId, query: query) else {
                throw AxonError.elementNotFound
            }
            let node = axEngine.elementToNode(element)
            // Check AX role security
            if let reason = await security.authorizeAXRole(node.role) {
                return .fail(reason)
            }
            return .ok(.element(node))

        case .clickElement(let bundleId, let query):
            guard let element = axEngine.findElement(bundleId: bundleId, query: query) else {
                throw AxonError.elementNotFound
            }
            let node = axEngine.elementToNode(element)
            if let reason = await security.authorizeAXRole(node.role) {
                return .fail(reason)
            }
            if !axEngine.clickElement(element: element) {
                // Fallback: click at element's center position
                if let pos = node.position, let size = node.size {
                    let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                    input.click(at: center)
                } else {
                    throw AxonError.actionFailed("Could not click element")
                }
            }
            return .ok(.none)

        case .typeIntoElement(let bundleId, let query, let text):
            guard let element = axEngine.findElement(bundleId: bundleId, query: query) else {
                throw AxonError.elementNotFound
            }
            let node = axEngine.elementToNode(element)
            if let reason = await security.authorizeAXRole(node.role) {
                return .fail(reason)
            }
            // Focus then type
            _ = axEngine.focusElement(element)
            // Try setting value directly first, fall back to typing
            if !axEngine.setValue(text, on: element) {
                let isASCII = text.allSatisfy { $0.isASCII }
                if isASCII {
                    input.typeText(text)
                } else {
                    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    _ = try await scriptEngine.runAppleScript("""
                        set the clipboard to "\(escaped)"
                        delay 0.1
                        tell application "System Events" to keystroke "v" using command down
                        """)
                }
            }
            return .ok(.none)

        case .clickAt(let x, let y):
            input.click(at: CGPoint(x: x, y: y))
            return .ok(.none)

        case .doubleClickAt(let x, let y):
            input.doubleClick(at: CGPoint(x: x, y: y))
            return .ok(.none)

        case .rightClickAt(let x, let y):
            input.rightClick(at: CGPoint(x: x, y: y))
            return .ok(.none)

        case .moveMouse(let x, let y):
            input.moveMouse(to: CGPoint(x: x, y: y))
            return .ok(.none)

        case .scroll(let x, let y, let direction, let amount):
            input.scroll(at: CGPoint(x: x, y: y), direction: direction, amount: amount)
            return .ok(.none)

        case .typeText(let text):
            let isASCII = text.allSatisfy { $0.isASCII }
            if isASCII {
                input.typeText(text)
            } else {
                // Non-ASCII (Chinese, etc.): use AppleScript to set clipboard and paste.
                // This avoids input method interference that garbles CGEvent unicode input.
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                    set the clipboard to "\(escaped)"
                    delay 0.1
                    tell application "System Events" to keystroke "v" using command down
                    """
                _ = try await scriptEngine.runAppleScript(script)
            }
            return .ok(.none)

        case .pressKey(let key, let modifiers):
            input.pressKey(key, modifiers: modifiers ?? [])
            return .ok(.none)

        case .screenshot(let displayId):
            let result: (base64: String, width: Int, height: Int)
            if let displayId {
                result = try await screenCapture.captureDisplay(index: displayId)
            } else {
                result = try await screenCapture.captureMainDisplay()
            }
            return .ok(.screenshot(base64: result.base64, width: result.width, height: result.height))

        case .runAppleScript(let script):
            if await security.getConfig().scriptSandboxEnabled {
                if let violation = ScriptEngine.validateScript(script) {
                    return .fail("Script sandbox: \(violation)")
                }
            }
            let output = try await scriptEngine.runAppleScript(script)
            return .ok(.scriptOutput(output))

        case .runJXA(let script):
            if await security.getConfig().scriptSandboxEnabled {
                if let violation = ScriptEngine.validateScript(script) {
                    return .fail("Script sandbox: \(violation)")
                }
            }
            let output = try await scriptEngine.runJXA(script)
            return .ok(.scriptOutput(output))

        case .waitForElement(let bundleId, let query, let timeout):
            let timeoutSecs = timeout ?? 10.0
            let interval: UInt64 = 250_000_000 // 250ms in nanoseconds
            let deadline = Date().addingTimeInterval(timeoutSecs)
            while Date() < deadline {
                if let element = axEngine.findElement(bundleId: bundleId, query: query) {
                    let node = axEngine.elementToNode(element)
                    if let reason = await security.authorizeAXRole(node.role) {
                        return .fail(reason)
                    }
                    return .ok(.element(node))
                }
                try await Task.sleep(nanoseconds: interval)
            }
            return .fail("Timeout waiting for element after \(timeoutSecs)s")

        case .quitApp(let bundleId):
            try appManager.quitApp(bundleId: bundleId)
            return .ok(.none)

        case .windowScreenshot(let bundleId, let title):
            let result = try await screenCapture.captureWindow(bundleId: bundleId, title: title)
            return .ok(.screenshot(base64: result.base64, width: result.width, height: result.height))

        case .getElementText(let bundleId, let query):
            guard let element = axEngine.findElement(bundleId: bundleId, query: query) else {
                throw AxonError.elementNotFound
            }
            let node = axEngine.elementToNode(element)
            if let reason = await security.authorizeAXRole(node.role) {
                return .fail(reason)
            }
            let text = node.value ?? node.title ?? node.description ?? ""
            return .ok(.text(text))

        case .performAction(let bundleId, let query, let actionName):
            guard let element = axEngine.findElement(bundleId: bundleId, query: query) else {
                throw AxonError.elementNotFound
            }
            let node = axEngine.elementToNode(element)
            if let reason = await security.authorizeAXRole(node.role) {
                return .fail(reason)
            }
            guard axEngine.performAction(element: element, action: actionName) else {
                throw AxonError.actionFailed("AX action '\(actionName)' failed")
            }
            return .ok(.none)
        }
    }
}

// MARK: - Action Helpers

extension ComputerAction {
    var name: String {
        switch self {
        case .launchApp: "launch_app"
        case .activateApp: "activate_app"
        case .listApps: "list_apps"
        case .getUITree: "get_ui_tree"
        case .findElement: "find_element"
        case .clickElement: "click_element"
        case .typeIntoElement: "type_into_element"
        case .clickAt: "click_at"
        case .doubleClickAt: "double_click_at"
        case .rightClickAt: "right_click_at"
        case .moveMouse: "move_mouse"
        case .scroll: "scroll"
        case .typeText: "type_text"
        case .pressKey: "press_key"
        case .screenshot: "screenshot"
        case .runAppleScript: "run_applescript"
        case .runJXA: "run_jxa"
        case .waitForElement: "wait_for_element"
        case .quitApp: "quit_app"
        case .windowScreenshot: "window_screenshot"
        case .getElementText: "get_element_text"
        case .performAction: "perform_action"
        }
    }

    var targetBundleId: String? {
        switch self {
        case .launchApp(let id), .activateApp(let id): id
        case .getUITree(let id, _), .findElement(let id, _): id
        case .clickElement(let id, _), .typeIntoElement(let id, _, _): id
        case .waitForElement(let id, _, _): id
        case .quitApp(let id): id
        case .windowScreenshot(let id, _): id
        case .getElementText(let id, _): id
        case .performAction(let id, _, _): id
        default: nil
        }
    }

    /// Whether this action is read-only (does not mutate UI state).
    public var isReadOnly: Bool {
        switch self {
        case .listApps, .getUITree, .findElement, .screenshot, .windowScreenshot,
             .waitForElement, .getElementText:
            return true
        default:
            return false
        }
    }
}
