import Foundation

// MARK: - Element Query

public struct ElementQuery: Codable, Sendable {
    public var role: String?
    public var title: String?
    public var identifier: String?
    public var value: String?
    public var subrole: String?
    public var description: String?
    public var index: Int?
    public var matchMode: MatchMode?

    public init(
        role: String? = nil,
        title: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        subrole: String? = nil,
        description: String? = nil,
        index: Int? = nil,
        matchMode: MatchMode? = nil
    ) {
        self.role = role
        self.title = title
        self.identifier = identifier
        self.value = value
        self.subrole = subrole
        self.description = description
        self.index = index
        self.matchMode = matchMode
    }
}

public enum MatchMode: String, Codable, Sendable {
    case exact
    case contains
    case prefix
    case regex
}

// MARK: - AX Node (UI Tree representation)

public struct AXNode: Codable, Sendable {
    public var role: String
    public var title: String?
    public var value: String?
    public var identifier: String?
    public var subrole: String?
    public var description: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var selected: Bool?
    public var position: CGPointCodable?
    public var size: CGSizeCodable?
    public var actions: [String]
    public var children: [AXNode]?

    public init(
        role: String,
        title: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        subrole: String? = nil,
        description: String? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        selected: Bool? = nil,
        position: CGPointCodable? = nil,
        size: CGSizeCodable? = nil,
        actions: [String] = [],
        children: [AXNode]? = nil
    ) {
        self.role = role
        self.title = title
        self.value = value
        self.identifier = identifier
        self.subrole = subrole
        self.description = description
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.position = position
        self.size = size
        self.actions = actions
        self.children = children
    }
}

public struct CGPointCodable: Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct CGSizeCodable: Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

// MARK: - App Info

public struct AppInfo: Codable, Sendable {
    public var name: String
    public var bundleId: String
    public var pid: Int32
    public var isActive: Bool

    public init(name: String, bundleId: String, pid: Int32, isActive: Bool) {
        self.name = name
        self.bundleId = bundleId
        self.pid = pid
        self.isActive = isActive
    }
}

// MARK: - Action Types

public enum ComputerAction: Codable, Sendable {
    case launchApp(bundleId: String)
    case activateApp(bundleId: String)
    case listApps
    case getUITree(bundleId: String, maxDepth: Int?)
    case findElement(bundleId: String, query: ElementQuery)
    case clickElement(bundleId: String, query: ElementQuery)
    case typeIntoElement(bundleId: String, query: ElementQuery, text: String)
    case clickAt(x: Double, y: Double)
    case doubleClickAt(x: Double, y: Double)
    case rightClickAt(x: Double, y: Double)
    case moveMouse(x: Double, y: Double)
    case scroll(x: Double, y: Double, direction: ScrollDirection, amount: Int)
    case typeText(text: String)
    case pressKey(key: String, modifiers: [String]?)
    case screenshot(displayId: Int?)
    case runAppleScript(script: String)
    case runJXA(script: String)
    case waitForElement(bundleId: String, query: ElementQuery, timeout: Double?)
    case quitApp(bundleId: String)
    case windowScreenshot(bundleId: String, title: String?)
    case getElementText(bundleId: String, query: ElementQuery)
    case performAction(bundleId: String, query: ElementQuery, action: String)
    // New capabilities
    case drag(fromX: Double, fromY: Double, toX: Double, toY: Double)
    case getCursorPosition
    case getScreenInfo
    case regionScreenshot(x: Int, y: Int, width: Int, height: Int, displayId: Int?)
    case clipboardRead
    case clipboardWrite(text: String)
    case getActiveWindow
    case moveWindow(bundleId: String, x: Double, y: Double)
    case resizeWindow(bundleId: String, width: Double, height: Double)
}

public enum ScrollDirection: String, Codable, Sendable {
    case up, down, left, right
}

// MARK: - Action Result

public struct ActionResult: Codable, Sendable {
    public var success: Bool
    public var data: ActionData?
    public var error: String?

    public init(success: Bool, data: ActionData? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }

    public static func ok(_ data: ActionData? = nil) -> ActionResult {
        ActionResult(success: true, data: data)
    }

    public static func fail(_ error: String) -> ActionResult {
        ActionResult(success: false, error: error)
    }
}

public enum ActionData: Codable, Sendable {
    case apps([AppInfo])
    case tree(AXNode)
    case element(AXNode)
    case screenshot(base64: String, width: Int, height: Int)
    case scriptOutput(String)
    case text(String)
    case none
    // New data types
    case cursorPosition(x: Double, y: Double)
    case screenInfo(ScreenInfo)
    case windowInfo(WindowInfo)
}

// MARK: - Screen Info

public struct ScreenInfo: Codable, Sendable {
    public var displayCount: Int
    public var displays: [DisplayInfo]

    public init(displayCount: Int, displays: [DisplayInfo]) {
        self.displayCount = displayCount
        self.displays = displays
    }
}

public struct DisplayInfo: Codable, Sendable {
    public var index: Int
    public var width: Int
    public var height: Int
    public var isMain: Bool

    public init(index: Int, width: Int, height: Int, isMain: Bool) {
        self.index = index
        self.width = width
        self.height = height
        self.isMain = isMain
    }
}

// MARK: - Window Info

public struct WindowInfo: Codable, Sendable {
    public var appName: String
    public var bundleId: String
    public var windowTitle: String?
    public var pid: Int32
    public var position: CGPointCodable?
    public var size: CGSizeCodable?

    public init(appName: String, bundleId: String, windowTitle: String? = nil, pid: Int32,
                position: CGPointCodable? = nil, size: CGSizeCodable? = nil) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.pid = pid
        self.position = position
        self.size = size
    }
}

// MARK: - Security Config

public struct SecurityConfig: Codable, Sendable {
    public var allowedApps: [String: AppPermission]
    public var deniedApps: [String]
    public var maxActionsPerMinute: Int
    public var maxConsecutiveFailures: Int
    public var confirmDestructiveActions: Bool
    public var deniedAXRoles: [String]
    public var authToken: String?
    public var scriptSandboxEnabled: Bool
    public var readOnlyMode: Bool

    public init(
        allowedApps: [String: AppPermission] = [:],
        deniedApps: [String] = [],
        maxActionsPerMinute: Int = 30,
        maxConsecutiveFailures: Int = 5,
        confirmDestructiveActions: Bool = true,
        deniedAXRoles: [String] = ["AXSecureTextField"],
        authToken: String? = nil,
        scriptSandboxEnabled: Bool = true,
        readOnlyMode: Bool = false
    ) {
        self.allowedApps = allowedApps
        self.deniedApps = deniedApps
        self.maxActionsPerMinute = maxActionsPerMinute
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.confirmDestructiveActions = confirmDestructiveActions
        self.deniedAXRoles = deniedAXRoles
        self.authToken = authToken
        self.scriptSandboxEnabled = scriptSandboxEnabled
        self.readOnlyMode = readOnlyMode
    }
}

public struct AppPermission: Codable, Sendable {
    public var level: PermissionLevel

    public init(level: PermissionLevel = .auto) {
        self.level = level
    }
}

public enum PermissionLevel: String, Codable, Sendable {
    case auto
    case confirm
    case deny
}

// MARK: - Audit Entry

public struct AuditEntry: Codable, Sendable {
    public var timestamp: Date
    public var action: String
    public var targetApp: String?
    public var details: String?
    public var success: Bool

    public init(action: String, targetApp: String? = nil, details: String? = nil, success: Bool) {
        self.timestamp = Date()
        self.action = action
        self.targetApp = targetApp
        self.details = details
        self.success = success
    }
}
