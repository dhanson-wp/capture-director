import AppKit
import ApplicationServices
import CaptureDirectorKit

/// An element in another app's accessibility tree, read on demand.
struct AXNode: ElementNode {
    let element: AXUIElement
    /// The search root is the app, but its children are its windows only (sheets and
    /// popovers live inside them), so a label like "Edit" finds a control in the window
    /// rather than the menu bar item of the same name.
    private let isAppRoot: Bool

    init(app pid: pid_t) {
        element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 1)
        isAppRoot = true
    }

    init(_ element: AXUIElement) {
        self.element = element
        isAppRoot = false
    }

    var role: String? { AX.string(element, kAXRoleAttribute) }
    var identifier: String? { AX.string(element, kAXIdentifierAttribute) }
    var title: String? { AX.string(element, kAXTitleAttribute) }
    var label: String? { AX.string(element, kAXDescriptionAttribute) }
    var value: String? { AX.string(element, kAXValueAttribute) }
    var children: [AXNode] {
        AX.elements(element, isAppRoot ? kAXWindowsAttribute : kAXChildrenAttribute).map(AXNode.init)
    }

    /// Where the element is on screen, in global points with a top-left origin.
    var frame: CGRect? { AX.frame(element) }
}

/// Small wrappers over the Accessibility C API.
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let value = attribute(element, name), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID(),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Moves and sizes a window. Size goes first and again last, because some apps
    /// clamp a size that would push the window off screen at its old position.
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
    }

    /// The app's main window, or its first standard window while it has no main one yet.
    static func mainWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        if let main = element(app, kAXMainWindowAttribute) { return main }
        return elements(app, kAXWindowsAttribute).first { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
    }

    /// The window that has keyboard focus in the app, if any.
    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return element(app, kAXFocusedWindowAttribute)
    }

    /// Brings the app and the window to the front.
    static func raise(_ window: AXUIElement, of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

/// A key with its modifiers, parsed from a step like `cmd+o` or `Enter`.
struct KeyChord: Equatable {
    var modifiers: [CGKeyCode]
    var key: CGKeyCode

    init?(_ text: String) {
        let parts = text.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let last = parts.last, let key = Self.keys[last] ?? Self.characters[last] else { return nil }
        var modifiers: [CGKeyCode] = []
        for part in parts.dropLast() {
            guard let code = Self.modifierNames[part] else { return nil }
            modifiers.append(code)
        }
        self.modifiers = modifiers
        self.key = key
    }

    var flags: CGEventFlags {
        modifiers.reduce(into: []) { $0.insert(Self.flag(for: $1)) }
    }

    static func flag(for modifier: CGKeyCode) -> CGEventFlags {
        switch modifier {
        case 55: return .maskCommand
        case 56: return .maskShift
        case 58: return .maskAlternate
        default: return .maskControl
        }
    }

    private static let modifierNames: [String: CGKeyCode] = [
        "cmd": 55, "command": 55, "meta": 55,
        "shift": 56,
        "alt": 58, "option": 58, "opt": 58,
        "ctrl": 59, "control": 59,
    ]

    private static let keys: [String: CGKeyCode] = [
        "enter": 36, "return": 36, "tab": 48, "space": 49,
        "backspace": 51, "delete": 51, "forwarddelete": 117,
        "escape": 53, "esc": 53,
        "arrowleft": 123, "left": 123, "arrowright": 124, "right": 124,
        "arrowdown": 125, "down": 125, "arrowup": 126, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// US layout key codes for single characters.
    private static let characters: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
    ]
}

/// Posts real mouse, key, and scroll events, marked so the recorder can tell its own
/// events from the user's. Remembers what it holds down so it can always let go.
final class InputDriver {
    /// Stamped on every event this driver posts (`eventSourceUserData`).
    static let marker: Int64 = 0x43_44_52_45_43
    private let source: CGEventSource?
    private var lastPosition: CGPoint?
    private var buttonDown = false
    private var heldModifiers: [CGKeyCode] = []

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.userData = Self.marker
        // Synthetic events otherwise mute the real mouse for a moment, which would hide the user's moves from the cancel check.
        source?.localEventsSuppressionInterval = 0
    }

    /// True for events this driver posted: they carry the marker, or (if the system
    /// coalesced a mouse move and dropped it) they land exactly where the driver put the pointer.
    func posted(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return true }
        guard let last = lastPosition else { return false }
        return hypot(event.location.x - last.x, event.location.y - last.y) < 1
    }

    /// Moves the pointer to a screen point (global, top-left origin).
    func move(to point: CGPoint) {
        post(CGEvent(mouseEventSource: source, mouseType: buttonDown ? .leftMouseDragged : .mouseMoved,
                     mouseCursorPosition: point, mouseButton: .left))
        lastPosition = point
    }

    func mouseDown(at point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        buttonDown = true
        post(event)
    }

    func mouseUp(at point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        buttonDown = false
        post(event)
    }

    func keyDown(_ chord: KeyChord) {
        var flags: CGEventFlags = []
        for modifier in chord.modifiers {
            flags.insert(KeyChord.flag(for: modifier))
            postKey(modifier, down: true, flags: flags)
            heldModifiers.append(modifier)
        }
        postKey(chord.key, down: true, flags: chord.flags)
    }

    func keyUp(_ chord: KeyChord) {
        postKey(chord.key, down: false, flags: chord.flags)
        releaseModifiers()
    }

    /// Types one character as a Unicode key event, so the keyboard layout doesn't matter.
    func type(_ character: Character) {
        switch character {
        case "\n", "\r":
            postKey(36, down: true, flags: []); postKey(36, down: false, flags: [])
        case "\t":
            postKey(48, down: true, flags: []); postKey(48, down: false, flags: [])
        default:
            let units = Array(String(character).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.flags = []
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                post(event)
            }
        }
    }

    /// Scrolls by whole points; positive moves the content up (scrolls down).
    func scroll(down points: Int32) {
        post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: -points, wheel2: 0, wheel3: 0))
    }

    /// Lets go of the mouse button and any modifier keys still down.
    func releaseAll() {
        if buttonDown, let point = lastPosition ?? CGEvent(source: nil)?.location { mouseUp(at: point) }
        buttonDown = false
        releaseModifiers()
    }

    private func releaseModifiers() {
        var flags = heldModifiers.reduce(into: CGEventFlags()) { $0.insert(KeyChord.flag(for: $1)) }
        for modifier in heldModifiers.reversed() {
            flags.remove(KeyChord.flag(for: modifier))
            postKey(modifier, down: false, flags: flags)
        }
        heldModifiers = []
    }

    private func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        post(event)
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }
}
