import Foundation
import Testing
@testable import AxonCore

@Test func elementQueryCodable() throws {
    let query = ElementQuery(role: "AXButton", title: "Play", matchMode: .contains)
    let data = try JSONEncoder().encode(query)
    let decoded = try JSONDecoder().decode(ElementQuery.self, from: data)
    #expect(decoded.role == "AXButton")
    #expect(decoded.title == "Play")
    #expect(decoded.matchMode == .contains)
}

@Test func elementQueryWithNewFields() throws {
    let query = ElementQuery(role: "AXButton", subrole: "AXCloseButton", description: "Close window")
    let data = try JSONEncoder().encode(query)
    let decoded = try JSONDecoder().decode(ElementQuery.self, from: data)
    #expect(decoded.subrole == "AXCloseButton")
    #expect(decoded.description == "Close window")
}

@Test func actionResultCodable() throws {
    let result = ActionResult.ok(.scriptOutput("hello"))
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
    #expect(decoded.success == true)
}

@Test func actionResultTextCodable() throws {
    let result = ActionResult.ok(.text("some text"))
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
    #expect(decoded.success == true)
    if case .text(let t) = decoded.data {
        #expect(t == "some text")
    } else {
        Issue.record("Expected .text data")
    }
}

@Test func securityConfigDefaults() {
    let config = SecurityConfig()
    #expect(config.maxActionsPerMinute == 30)
    #expect(config.maxConsecutiveFailures == 5)
    #expect(config.confirmDestructiveActions == true)
    #expect(config.deniedAXRoles.contains("AXSecureTextField"))
    #expect(config.authToken == nil)
    #expect(config.scriptSandboxEnabled == true)
    #expect(config.readOnlyMode == false)
}

@Test func computerActionName() {
    let action = ComputerAction.launchApp(bundleId: "com.test.app")
    #expect(action.name == "launch_app")
    #expect(action.targetBundleId == "com.test.app")
}

@Test func computerActionScreenshot() {
    let action = ComputerAction.screenshot(displayId: nil)
    #expect(action.name == "screenshot")
    #expect(action.targetBundleId == nil)
}

@Test func newActionNames() {
    #expect(ComputerAction.waitForElement(bundleId: "x", query: ElementQuery(), timeout: nil).name == "wait_for_element")
    #expect(ComputerAction.quitApp(bundleId: "x").name == "quit_app")
    #expect(ComputerAction.windowScreenshot(bundleId: "x", title: nil).name == "window_screenshot")
    #expect(ComputerAction.getElementText(bundleId: "x", query: ElementQuery()).name == "get_element_text")
    #expect(ComputerAction.performAction(bundleId: "x", query: ElementQuery(), action: "AXPress").name == "perform_action")
}

@Test func newActionTargetBundleIds() {
    #expect(ComputerAction.waitForElement(bundleId: "a", query: ElementQuery(), timeout: nil).targetBundleId == "a")
    #expect(ComputerAction.quitApp(bundleId: "b").targetBundleId == "b")
    #expect(ComputerAction.windowScreenshot(bundleId: "c", title: nil).targetBundleId == "c")
    #expect(ComputerAction.getElementText(bundleId: "d", query: ElementQuery()).targetBundleId == "d")
    #expect(ComputerAction.performAction(bundleId: "e", query: ElementQuery(), action: "AXPress").targetBundleId == "e")
}

@Test func actionIsReadOnly() {
    // Read-only actions
    #expect(ComputerAction.listApps.isReadOnly == true)
    #expect(ComputerAction.getUITree(bundleId: "x", maxDepth: nil).isReadOnly == true)
    #expect(ComputerAction.findElement(bundleId: "x", query: ElementQuery()).isReadOnly == true)
    #expect(ComputerAction.screenshot(displayId: nil).isReadOnly == true)
    #expect(ComputerAction.windowScreenshot(bundleId: "x", title: nil).isReadOnly == true)
    #expect(ComputerAction.waitForElement(bundleId: "x", query: ElementQuery(), timeout: nil).isReadOnly == true)
    #expect(ComputerAction.getElementText(bundleId: "x", query: ElementQuery()).isReadOnly == true)

    // Mutation actions
    #expect(ComputerAction.launchApp(bundleId: "x").isReadOnly == false)
    #expect(ComputerAction.clickAt(x: 0, y: 0).isReadOnly == false)
    #expect(ComputerAction.typeText(text: "x").isReadOnly == false)
    #expect(ComputerAction.quitApp(bundleId: "x").isReadOnly == false)
    #expect(ComputerAction.runAppleScript(script: "x").isReadOnly == false)
}

@Test func computerActionCodableRoundTrip() throws {
    let actions: [ComputerAction] = [
        .waitForElement(bundleId: "com.test", query: ElementQuery(role: "AXButton"), timeout: 5.0),
        .quitApp(bundleId: "com.test"),
        .windowScreenshot(bundleId: "com.test", title: "My Window"),
        .getElementText(bundleId: "com.test", query: ElementQuery(title: "label")),
        .performAction(bundleId: "com.test", query: ElementQuery(role: "AXButton"), action: "AXPress"),
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for action in actions {
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(ComputerAction.self, from: data)
        #expect(decoded.name == action.name)
        #expect(decoded.targetBundleId == action.targetBundleId)
    }
}

@Test func axNodeWithNewFields() throws {
    let node = AXNode(
        role: "AXButton",
        title: "OK",
        subrole: "AXCloseButton",
        description: "Close",
        enabled: true,
        focused: false,
        selected: nil
    )
    let data = try JSONEncoder().encode(node)
    let decoded = try JSONDecoder().decode(AXNode.self, from: data)
    #expect(decoded.subrole == "AXCloseButton")
    #expect(decoded.description == "Close")
    #expect(decoded.enabled == true)
    #expect(decoded.focused == false)
    #expect(decoded.selected == nil)
}

@Test func securityConfigLoadDefault() {
    let config = SecurityConfig.load(from: URL(fileURLWithPath: "/nonexistent"))
    #expect(config.maxActionsPerMinute == 30)
    #expect(config.allowedApps.isEmpty)
}

@Test func securityConfigCodableWithNewFields() throws {
    var config = SecurityConfig()
    config.authToken = "test-token"
    config.scriptSandboxEnabled = false
    config.readOnlyMode = true
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(SecurityConfig.self, from: data)
    #expect(decoded.authToken == "test-token")
    #expect(decoded.scriptSandboxEnabled == false)
    #expect(decoded.readOnlyMode == true)
}

// MARK: - New Capability Tests

@Test func dragActionProperties() {
    let action = ComputerAction.drag(fromX: 10, fromY: 20, toX: 100, toY: 200)
    #expect(action.name == "drag")
    #expect(action.targetBundleId == nil)
    #expect(action.isReadOnly == false)
}

@Test func getCursorPositionActionProperties() {
    let action = ComputerAction.getCursorPosition
    #expect(action.name == "get_cursor_position")
    #expect(action.targetBundleId == nil)
    #expect(action.isReadOnly == true)
}

@Test func getScreenInfoActionProperties() {
    let action = ComputerAction.getScreenInfo
    #expect(action.name == "get_screen_info")
    #expect(action.targetBundleId == nil)
    #expect(action.isReadOnly == true)
}

@Test func regionScreenshotActionProperties() {
    let action = ComputerAction.regionScreenshot(x: 0, y: 0, width: 800, height: 600, displayId: nil)
    #expect(action.name == "region_screenshot")
    #expect(action.targetBundleId == nil)
    #expect(action.isReadOnly == true)
}

@Test func clipboardActionProperties() {
    let read = ComputerAction.clipboardRead
    #expect(read.name == "clipboard_read")
    #expect(read.isReadOnly == true)

    let write = ComputerAction.clipboardWrite(text: "hello")
    #expect(write.name == "clipboard_write")
    #expect(write.isReadOnly == false)
}

@Test func getActiveWindowActionProperties() {
    let action = ComputerAction.getActiveWindow
    #expect(action.name == "get_active_window")
    #expect(action.targetBundleId == nil)
    #expect(action.isReadOnly == true)
}

@Test func moveWindowActionProperties() {
    let action = ComputerAction.moveWindow(bundleId: "com.test.app", x: 100, y: 200)
    #expect(action.name == "move_window")
    #expect(action.targetBundleId == "com.test.app")
    #expect(action.isReadOnly == false)
}

@Test func resizeWindowActionProperties() {
    let action = ComputerAction.resizeWindow(bundleId: "com.test.app", width: 800, height: 600)
    #expect(action.name == "resize_window")
    #expect(action.targetBundleId == "com.test.app")
    #expect(action.isReadOnly == false)
}

@Test func newActionsCodableRoundTrip() throws {
    let actions: [ComputerAction] = [
        .drag(fromX: 10, fromY: 20, toX: 100, toY: 200),
        .getCursorPosition,
        .getScreenInfo,
        .regionScreenshot(x: 0, y: 0, width: 800, height: 600, displayId: 1),
        .clipboardRead,
        .clipboardWrite(text: "test text"),
        .getActiveWindow,
        .moveWindow(bundleId: "com.test", x: 50, y: 50),
        .resizeWindow(bundleId: "com.test", width: 1024, height: 768),
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for action in actions {
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(ComputerAction.self, from: data)
        #expect(decoded.name == action.name)
        #expect(decoded.targetBundleId == action.targetBundleId)
        #expect(decoded.isReadOnly == action.isReadOnly)
    }
}

@Test func cursorPositionDataCodable() throws {
    let result = ActionResult.ok(.cursorPosition(x: 123.5, y: 456.7))
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
    #expect(decoded.success == true)
    if case .cursorPosition(let x, let y) = decoded.data {
        #expect(x == 123.5)
        #expect(y == 456.7)
    } else {
        Issue.record("Expected .cursorPosition data")
    }
}

@Test func screenInfoCodable() throws {
    let info = ScreenInfo(displayCount: 2, displays: [
        DisplayInfo(index: 0, width: 1728, height: 1117, isMain: true),
        DisplayInfo(index: 1, width: 1920, height: 1080, isMain: false),
    ])
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(ScreenInfo.self, from: data)
    #expect(decoded.displayCount == 2)
    #expect(decoded.displays.count == 2)
    #expect(decoded.displays[0].width == 1728)
    #expect(decoded.displays[0].isMain == true)
    #expect(decoded.displays[1].width == 1920)
    #expect(decoded.displays[1].isMain == false)
}

@Test func screenInfoDataCodable() throws {
    let info = ScreenInfo(displayCount: 1, displays: [
        DisplayInfo(index: 0, width: 1728, height: 1117, isMain: true),
    ])
    let result = ActionResult.ok(.screenInfo(info))
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
    #expect(decoded.success == true)
    if case .screenInfo(let decodedInfo) = decoded.data {
        #expect(decodedInfo.displayCount == 1)
        #expect(decodedInfo.displays[0].width == 1728)
    } else {
        Issue.record("Expected .screenInfo data")
    }
}

@Test func windowInfoCodable() throws {
    let info = WindowInfo(
        appName: "Safari",
        bundleId: "com.apple.Safari",
        windowTitle: "Google",
        pid: 12345,
        position: CGPointCodable(CGPoint(x: 100, y: 200)),
        size: CGSizeCodable(CGSize(width: 800, height: 600))
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(WindowInfo.self, from: data)
    #expect(decoded.appName == "Safari")
    #expect(decoded.bundleId == "com.apple.Safari")
    #expect(decoded.windowTitle == "Google")
    #expect(decoded.pid == 12345)
    #expect(decoded.position?.x == 100)
    #expect(decoded.size?.width == 800)
}

@Test func windowInfoDataCodable() throws {
    let info = WindowInfo(appName: "Test", bundleId: "com.test", pid: 1)
    let result = ActionResult.ok(.windowInfo(info))
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
    #expect(decoded.success == true)
    if case .windowInfo(let decodedInfo) = decoded.data {
        #expect(decodedInfo.appName == "Test")
        #expect(decodedInfo.bundleId == "com.test")
    } else {
        Issue.record("Expected .windowInfo data")
    }
}

@Test func actionResultFailCodable() throws {
    let result = ActionResult.fail("something went wrong")
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
    #expect(decoded.success == false)
    #expect(decoded.error == "something went wrong")
    #expect(decoded.data == nil)
}

@Test func originalActionsCodableRoundTrip() throws {
    let actions: [ComputerAction] = [
        .launchApp(bundleId: "com.test"),
        .activateApp(bundleId: "com.test"),
        .listApps,
        .getUITree(bundleId: "com.test", maxDepth: 3),
        .findElement(bundleId: "com.test", query: ElementQuery(role: "AXButton")),
        .clickElement(bundleId: "com.test", query: ElementQuery(title: "OK")),
        .typeIntoElement(bundleId: "com.test", query: ElementQuery(role: "AXTextField"), text: "hello"),
        .clickAt(x: 100, y: 200),
        .doubleClickAt(x: 100, y: 200),
        .rightClickAt(x: 100, y: 200),
        .moveMouse(x: 300, y: 400),
        .scroll(x: 500, y: 500, direction: .down, amount: 3),
        .typeText(text: "hello world"),
        .pressKey(key: "return", modifiers: ["command"]),
        .screenshot(displayId: nil),
        .runAppleScript(script: "tell app \"Finder\" to activate"),
        .runJXA(script: "Application('Finder').name()"),
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for action in actions {
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(ComputerAction.self, from: data)
        #expect(decoded.name == action.name)
        #expect(decoded.targetBundleId == action.targetBundleId)
    }
}

@Test func allNewActionsReadOnlyClassification() {
    // Read-only new actions
    #expect(ComputerAction.getCursorPosition.isReadOnly == true)
    #expect(ComputerAction.getScreenInfo.isReadOnly == true)
    #expect(ComputerAction.regionScreenshot(x: 0, y: 0, width: 100, height: 100, displayId: nil).isReadOnly == true)
    #expect(ComputerAction.clipboardRead.isReadOnly == true)
    #expect(ComputerAction.getActiveWindow.isReadOnly == true)

    // Mutation new actions
    #expect(ComputerAction.drag(fromX: 0, fromY: 0, toX: 1, toY: 1).isReadOnly == false)
    #expect(ComputerAction.clipboardWrite(text: "x").isReadOnly == false)
    #expect(ComputerAction.moveWindow(bundleId: "x", x: 0, y: 0).isReadOnly == false)
    #expect(ComputerAction.resizeWindow(bundleId: "x", width: 100, height: 100).isReadOnly == false)
}
