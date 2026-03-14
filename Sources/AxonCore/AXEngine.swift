import ApplicationServices
import AppKit
import Foundation

/// AX Engine — Layer 2 automation via macOS Accessibility API.
/// Provides structured UI tree traversal, element querying, and action execution.
public final class AXEngine: Sendable {
    public init() {}

    // MARK: - Permission Check

    public func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - UI Tree

    /// Get the UI tree for an app by its PID, up to `maxDepth` levels deep.
    public func getUITree(pid: pid_t, maxDepth: Int = 4) -> AXNode? {
        let appElement = AXUIElementCreateApplication(pid)
        return buildNode(from: appElement, depth: 0, maxDepth: maxDepth)
    }

    /// Get the UI tree for an app by its bundle ID.
    public func getUITree(bundleId: String, maxDepth: Int = 4) -> AXNode? {
        guard let pid = pidForBundleId(bundleId) else { return nil }
        return getUITree(pid: pid, maxDepth: maxDepth)
    }

    // MARK: - Element Finding

    /// Find elements matching a query within an app's UI tree.
    public func findElements(bundleId: String, query: ElementQuery) -> [AXUIElement] {
        guard let pid = pidForBundleId(bundleId) else { return [] }
        let appElement = AXUIElementCreateApplication(pid)
        var results: [AXUIElement] = []
        searchElements(in: appElement, query: query, results: &results, depth: 0, maxDepth: 20)
        return results
    }

    /// Find a single element matching a query, optionally by index.
    public func findElement(bundleId: String, query: ElementQuery) -> AXUIElement? {
        let elements = findElements(bundleId: bundleId, query: query)
        let index = query.index ?? 0
        guard index < elements.count else { return nil }
        return elements[index]
    }

    // MARK: - Actions

    /// Click an element (perform AXPress action).
    public func clickElement(element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Set value on an element (e.g., type into a text field).
    public func setValue(_ value: String, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
    }

    /// Set focus on an element.
    public func focusElement(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
    }

    /// Get element info as an AXNode.
    public func elementToNode(_ element: AXUIElement) -> AXNode {
        buildNodeShallow(from: element)
    }

    /// Get the available actions for an element.
    public func getActions(of element: AXUIElement) -> [String] {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String] else { return [] }
        return actions
    }

    // MARK: - Internal

    private func buildNode(from element: AXUIElement, depth: Int, maxDepth: Int) -> AXNode {
        var node = buildNodeShallow(from: element)
        if depth < maxDepth {
            let children = getChildren(of: element)
            if !children.isEmpty {
                node.children = children.map { buildNode(from: $0, depth: depth + 1, maxDepth: maxDepth) }
            }
        }
        return node
    }

    private func buildNodeShallow(from element: AXUIElement) -> AXNode {
        AXNode(
            role: getStringAttribute(element, kAXRoleAttribute) ?? "Unknown",
            title: getStringAttribute(element, kAXTitleAttribute),
            value: getStringValue(element),
            identifier: getStringAttribute(element, kAXIdentifierAttribute),
            subrole: getStringAttribute(element, kAXSubroleAttribute),
            description: getStringAttribute(element, kAXDescriptionAttribute),
            enabled: getBoolAttribute(element, kAXEnabledAttribute),
            focused: getBoolAttribute(element, kAXFocusedAttribute),
            selected: getBoolAttribute(element, kAXSelectedAttribute),
            position: getPosition(of: element),
            size: getSize(of: element),
            actions: getActions(of: element)
        )
    }

    private func searchElements(
        in element: AXUIElement,
        query: ElementQuery,
        results: inout [AXUIElement],
        depth: Int,
        maxDepth: Int
    ) {
        if matchesQuery(element, query: query) {
            results.append(element)
        }
        guard depth < maxDepth else { return }
        for child in getChildren(of: element) {
            searchElements(in: child, query: query, results: &results, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private func matchesQuery(_ element: AXUIElement, query: ElementQuery) -> Bool {
        let mode = query.matchMode ?? .contains

        if let role = query.role {
            let elementRole = getStringAttribute(element, kAXRoleAttribute) ?? ""
            if !stringMatches(elementRole, pattern: role, mode: mode) { return false }
        }
        if let title = query.title {
            let elementTitle = getStringAttribute(element, kAXTitleAttribute) ?? ""
            if !stringMatches(elementTitle, pattern: title, mode: mode) { return false }
        }
        if let identifier = query.identifier {
            let elementId = getStringAttribute(element, kAXIdentifierAttribute) ?? ""
            if !stringMatches(elementId, pattern: identifier, mode: mode) { return false }
        }
        if let value = query.value {
            let elementValue = getStringValue(element) ?? ""
            if !stringMatches(elementValue, pattern: value, mode: mode) { return false }
        }
        if let subrole = query.subrole {
            let elementSubrole = getStringAttribute(element, kAXSubroleAttribute) ?? ""
            if !stringMatches(elementSubrole, pattern: subrole, mode: mode) { return false }
        }
        if let description = query.description {
            let elementDesc = getStringAttribute(element, kAXDescriptionAttribute) ?? ""
            if !stringMatches(elementDesc, pattern: description, mode: mode) { return false }
        }
        return true
    }

    private func stringMatches(_ string: String, pattern: String, mode: MatchMode) -> Bool {
        switch mode {
        case .exact:
            return string == pattern
        case .contains:
            return string.localizedCaseInsensitiveContains(pattern)
        case .prefix:
            return string.lowercased().hasPrefix(pattern.lowercased())
        case .regex:
            return (try? string.range(of: pattern, options: .regularExpression)) != nil
        }
    }

    /// Perform a named action on an AX element (e.g., "AXPress", "AXShowMenu").
    public func performAction(element: AXUIElement, action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    // MARK: - AX Attribute Helpers

    private func getBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let boolVal = value as? Bool { return boolVal }
        if let numVal = value as? NSNumber { return numVal.boolValue }
        return nil
    }

    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func getStringValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private func getChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }
        return children
    }

    private func getPosition(of element: AXUIElement) -> CGPointCodable? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return CGPointCodable(point)
    }

    private func getSize(of element: AXUIElement) -> CGSizeCodable? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return CGSizeCodable(size)
    }

    private func pidForBundleId(_ bundleId: String) -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleId }?
            .processIdentifier
    }
}
