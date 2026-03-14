import Foundation
import Testing
@testable import AxonCore

// MARK: - SecurityGate Tests

@Test func securityGateAllowsBasicAction() async {
    let gate = SecurityGate()
    let result = await gate.authorize(action: "list_apps", bundleId: nil)
    #expect(result == nil) // nil means allowed
}

@Test func securityGateDeniesBlockedApp() async {
    let config = SecurityConfig(deniedApps: ["com.blocked.app"])
    let gate = SecurityGate(config: config)
    let result = await gate.authorize(action: "launch_app", bundleId: "com.blocked.app")
    #expect(result != nil)
    #expect(result!.contains("deny list"))
}

@Test func securityGateDeniesWildcardPattern() async {
    let config = SecurityConfig(deniedApps: ["com.blocked.*"])
    let gate = SecurityGate(config: config)
    let denied = await gate.authorize(action: "launch_app", bundleId: "com.blocked.anything")
    #expect(denied != nil)
    let allowed = await gate.authorize(action: "launch_app", bundleId: "com.other.app")
    #expect(allowed == nil)
}

@Test func securityGateRateLimit() async {
    let config = SecurityConfig(maxActionsPerMinute: 2)
    let gate = SecurityGate(config: config)
    // Record 2 actions
    await gate.recordAction(action: "click", targetApp: nil, details: nil, success: true)
    await gate.recordAction(action: "click", targetApp: nil, details: nil, success: true)
    // Third should be rate-limited
    let result = await gate.authorize(action: "click", bundleId: nil)
    #expect(result != nil)
    #expect(result!.contains("Rate limit"))
}

@Test func securityGateConsecutiveFailures() async {
    let config = SecurityConfig(maxConsecutiveFailures: 2)
    let gate = SecurityGate(config: config)
    await gate.recordAction(action: "click", targetApp: nil, details: "err", success: false)
    await gate.recordAction(action: "click", targetApp: nil, details: "err", success: false)
    let result = await gate.authorize(action: "click", bundleId: nil)
    #expect(result != nil)
    #expect(result!.contains("consecutive failures"))
}

@Test func securityGateConsecutiveFailuresReset() async {
    let config = SecurityConfig(maxConsecutiveFailures: 2)
    let gate = SecurityGate(config: config)
    await gate.recordAction(action: "click", targetApp: nil, details: "err", success: false)
    await gate.recordAction(action: "click", targetApp: nil, details: nil, success: true) // resets
    await gate.recordAction(action: "click", targetApp: nil, details: "err", success: false)
    let result = await gate.authorize(action: "click", bundleId: nil)
    #expect(result == nil) // only 1 consecutive failure, not 2
}

@Test func securityGateAXRoleDenied() async {
    let gate = SecurityGate()
    let result = await gate.authorizeAXRole("AXSecureTextField")
    #expect(result != nil)
    #expect(result!.contains("denied"))
}

@Test func securityGateAXRoleAllowed() async {
    let gate = SecurityGate()
    let result = await gate.authorizeAXRole("AXButton")
    #expect(result == nil)
}

@Test func securityGateAllowlistEnforced() async {
    let config = SecurityConfig(allowedApps: ["com.allowed.app": AppPermission(level: .auto)])
    let gate = SecurityGate(config: config)
    let allowed = await gate.authorize(action: "click", bundleId: "com.allowed.app")
    #expect(allowed == nil)
    let denied = await gate.authorize(action: "click", bundleId: "com.other.app")
    #expect(denied != nil)
    #expect(denied!.contains("not in allow list"))
}

@Test func securityGateAuditLog() async {
    let gate = SecurityGate()
    await gate.recordAction(action: "click", targetApp: "com.test", details: nil, success: true)
    await gate.recordAction(action: "type", targetApp: "com.test", details: nil, success: false)
    let log = await gate.getRecentAuditLog()
    #expect(log.count == 2)
    #expect(log[0].action == "click")
    #expect(log[0].success == true)
    #expect(log[1].action == "type")
    #expect(log[1].success == false)
}

// MARK: - Script Sandbox Tests

@Test func scriptSandboxBlocksShellScript() {
    let result = ScriptEngine.validateScript(#"do shell script "ls""#)
    #expect(result != nil)
    #expect(result!.contains("shell command"))
}

@Test func scriptSandboxBlocksSystem() {
    #expect(ScriptEngine.validateScript("system(\"ls\")") != nil)
}

@Test func scriptSandboxBlocksNSTask() {
    #expect(ScriptEngine.validateScript("let t = NSTask()") != nil)
}

@Test func scriptSandboxBlocksProcess() {
    #expect(ScriptEngine.validateScript("let p = Process()") != nil)
}

@Test func scriptSandboxBlocksBinPaths() {
    #expect(ScriptEngine.validateScript("run \"/bin/bash\"") != nil)
    #expect(ScriptEngine.validateScript("run \"/usr/bin/env\"") != nil)
}

@Test func scriptSandboxAllowsSafeScript() {
    let result = ScriptEngine.validateScript("""
        tell application "Finder"
            get name of every disk
        end tell
    """)
    #expect(result == nil)
}

@Test func scriptSandboxCaseInsensitive() {
    let result = ScriptEngine.validateScript(#"DO SHELL SCRIPT "ls""#)
    #expect(result != nil)
}

// MARK: - Read-Only Mode Tests

@Test func readOnlyModeBlocksMutations() async {
    let config = SecurityConfig(readOnlyMode: true)
    let controller = AxonController(config: config)
    let result = await controller.execute(.typeText(text: "hello"))
    #expect(result.success == false)
    #expect(result.error?.contains("Read-only mode") == true)
}

@Test func readOnlyModeAllowsReads() async {
    let config = SecurityConfig(readOnlyMode: true)
    let controller = AxonController(config: config)
    let result = await controller.execute(.listApps)
    #expect(result.success == true)
}
