import AppKit
import CoreGraphics
import Foundation

/// Low-level mouse and keyboard simulation via CGEvent API.
/// All coordinates are in logical points (not Retina pixels).
public final class InputSimulator: Sendable {
    public init() {}

    // MARK: - Mouse

    public func click(at point: CGPoint, button: CGMouseButton = .left) {
        let (down, up) = mouseEventTypes(for: button)
        post(mouseEvent: down, at: point, button: button)
        usleep(50_000) // 50ms between down and up
        post(mouseEvent: up, at: point, button: button)
    }

    public func doubleClick(at point: CGPoint) {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: 2)
        up?.setIntegerValueField(.mouseEventClickState, value: 2)

        // First click
        post(mouseEvent: .leftMouseDown, at: point, button: .left)
        usleep(30_000)
        post(mouseEvent: .leftMouseUp, at: point, button: .left)
        usleep(30_000)
        // Second click (double)
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        up?.post(tap: .cghidEventTap)
    }

    public func rightClick(at point: CGPoint) {
        click(at: point, button: .right)
    }

    public func moveMouse(to point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    public func mouseDown(at point: CGPoint, button: CGMouseButton = .left) {
        let (down, _) = mouseEventTypes(for: button)
        post(mouseEvent: down, at: point, button: button)
    }

    public func mouseUp(at point: CGPoint, button: CGMouseButton = .left) {
        let (_, up) = mouseEventTypes(for: button)
        post(mouseEvent: up, at: point, button: button)
    }

    public func scroll(at point: CGPoint, direction: ScrollDirection, amount: Int = 3) {
        // Move mouse to position first
        moveMouse(to: point)
        usleep(20_000)

        let (dx, dy): (Int32, Int32) = switch direction {
        case .up: (0, Int32(amount))
        case .down: (0, Int32(-amount))
        case .left: (Int32(amount), 0)
        case .right: (Int32(-amount), 0)
        }

        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard

    /// Type a string by simulating key-down/key-up events for each character.
    /// Note: For non-ASCII text (Chinese, etc.), use `AxonController`'s typeText
    /// which routes through AppleScript clipboard paste instead.
    public func typeText(_ text: String) {
        for char in text {
            let str = String(char) as NSString
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { continue }
            event.keyboardSetUnicodeString(stringLength: str.length, unicodeString: Array(str as String).map { $0.utf16.first! })
            event.post(tap: .cghidEventTap)

            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            upEvent?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    /// Press a key combination (e.g., key="Return", modifiers=["command"]).
    public func pressKey(_ key: String, modifiers: [String] = []) {
        guard let keyCode = Self.keyCodeMap[key.lowercased()] else {
            // Try single character
            if key.count == 1 {
                typeText(key)
                return
            }
            return
        }

        var flags: CGEventFlags = []
        for mod in modifiers {
            if let flag = Self.modifierMap[mod.lowercased()] {
                flags.insert(flag)
            }
        }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)

        if !flags.isEmpty {
            down?.flags = flags
            up?.flags = flags
        }

        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    private func post(mouseEvent type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.post(tap: .cghidEventTap)
    }

    private func mouseEventTypes(for button: CGMouseButton) -> (CGEventType, CGEventType) {
        switch button {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    // MARK: - Key Code Maps

    nonisolated(unsafe) static let keyCodeMap: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "command": 55, "shift": 56, "capslock": 57, "option": 58, "alt": 58,
        "control": 59, "ctrl": 59,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
        "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25,
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
        ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    nonisolated(unsafe) static let modifierMap: [String: CGEventFlags] = [
        "command": .maskCommand, "cmd": .maskCommand,
        "shift": .maskShift,
        "option": .maskAlternate, "alt": .maskAlternate,
        "control": .maskControl, "ctrl": .maskControl,
    ]
}
