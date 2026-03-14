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
