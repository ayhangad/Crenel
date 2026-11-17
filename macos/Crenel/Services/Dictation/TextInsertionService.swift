import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

// MARK: - Abstractions

/// Frontmost application and its focused text target, as seen at insertion time.
struct DictationTargetSnapshot: Equatable, Sendable {
    var bundleIdentifier: String?
    var appName: String?
    var selectedText: String?
}

/// A focused accessibility element, abstracted for testing.
@MainActor
protocol FocusedTextElement: AnyObject {
    var role: String? { get }
    var subrole: String? { get }
    var isSelectedTextSettable: Bool { get }
    var isValueSettable: Bool { get }
    var value: String? { get }
    var selectedText: String? { get }
    /// The selection in UTF-16 units; nil when the element does not report it.
    var selectedRange: NSRange? { get }
    /// Replaces the selection (or inserts at the caret when the selection is empty).
    func setSelectedText(_ text: String) -> Bool
    func setSelectedRange(_ range: NSRange) -> Bool
    func setValue(_ value: String) -> Bool
    /// True when both wrap the same UI element (the wrappers themselves are recreated).
    func isSame(as other: any FocusedTextElement) -> Bool
}

@MainActor
protocol FocusedElementProviding: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    /// True while any app has secure keyboard entry enabled (e.g. a password field is focused).
    var isSecureInputActive: Bool { get }
    func frontmostApplication() -> (bundleIdentifier: String?, name: String?)
    func focusedElement() -> (any FocusedTextElement)?
}

/// Full pasteboard contents: one dictionary of type → data per item.
struct PasteboardSnapshot: Equatable, Sendable {
    var items: [[String: Data]]
}

@MainActor
protocol DictationPasteboard: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    /// Writes plain text; `transient` marks it so clipboard managers can ignore it.
    @discardableResult func write(text: String, transient: Bool) -> Int
}

@MainActor
protocol PasteKeystrokeSending: AnyObject {
    func sendPaste() -> Bool
    /// ⌘Z to the frontmost app.
    func sendUndo() -> Bool
}

@MainActor
protocol DictationTextInserting: AnyObject {
    func currentContext() -> DictationTargetSnapshot
    func insert(_ text: String) async -> TextInsertionResult
    func copyToClipboard(_ text: String)
    /// Whether the last successful `insert` left enough behind to take it back.
    var canUndoLastInsertion: Bool { get }
    /// Takes back the last insertion if it is still exactly where it was put. Returns false
    /// (and changes nothing) when the field has moved on.
    func undoLastInsertion() async -> Bool
}

// MARK: - Policy

@MainActor
enum TextInsertionPolicy {
    static let secureRoles: Set<String> = ["AXSecureTextField"]
    static let secureSubroles: Set<String> = [kAXSecureTextFieldSubrole as String]
    static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField"
    ]

    static func isSecure(_ element: any FocusedTextElement) -> Bool {
        if let role = element.role, secureRoles.contains(role) { return true }
        if let subrole = element.subrole, secureSubroles.contains(subrole) { return true }
        return false
    }

    static func isEditable(_ element: any FocusedTextElement) -> Bool {
        if let role = element.role, editableRoles.contains(role) { return true }
        return element.isSelectedTextSettable || element.isValueSettable
    }
}

// MARK: - Service

/// Puts dictated text at the caret of the frontmost app.
///
/// No per-app lists: a direct Accessibility write is used only where it can be verified (the
/// field's value is readable and changes). Everything else — Chromium/Electron apps, terminals,
/// fields that report success without applying it — gets ⌘V with the pasteboard saved and
/// restored, so the user sees the same result either way. Secure fields are always refused.
@MainActor
final class TextInsertionService: DictationTextInserting {
    private let elements: any FocusedElementProviding
    private let pasteboard: any DictationPasteboard
    private let keystrokes: any PasteKeystrokeSending
    private let restoreDelay: Duration
    private let sleep: @Sendable (Duration) async -> Void
    /// What the last insertion changed, kept only until the next one.
    private var undoRecord: UndoRecord?

    private enum UndoRecord {
        /// The field's value before and after, and where the text went.
        case accessibility(
            element: any FocusedTextElement,
            valueBefore: String,
            valueAfter: String,
            selectionBefore: NSRange?,
            replacedText: String,
            insertedLength: Int
        )
        /// ⌘V went to this app; ⌘Z takes it back while the field still shows the paste.
        case paste(bundleIdentifier: String, valueAfter: String?)
    }

    init(
        elements: any FocusedElementProviding = SystemFocusedElementProvider(),
        pasteboard: any DictationPasteboard = SystemDictationPasteboard(),
        keystrokes: any PasteKeystrokeSending = SystemPasteKeystrokeSender(),
        restoreDelay: Duration = .milliseconds(400),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.elements = elements
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.restoreDelay = restoreDelay
        self.sleep = sleep
    }

    func currentContext() -> DictationTargetSnapshot {
        let app = elements.frontmostApplication()
        var snapshot = DictationTargetSnapshot(bundleIdentifier: app.bundleIdentifier, appName: app.name)
        guard elements.isAccessibilityTrusted,
              !elements.isSecureInputActive,
              let element = elements.focusedElement(),
              !TextInsertionPolicy.isSecure(element) else {
            return snapshot
        }
        if let selected = element.selectedText, !selected.isEmpty {
            snapshot.selectedText = selected
        }
        return snapshot
    }

    func copyToClipboard(_ text: String) {
        pasteboard.write(text: text, transient: false)
    }

    func insert(_ text: String) async -> TextInsertionResult {
        undoRecord = nil
        guard elements.isAccessibilityTrusted else {
            copyToClipboard(text)
            return .copiedToClipboard(.accessibilityPermissionMissing)
        }
        if elements.isSecureInputActive {
            return .refusedSecureField
        }

        let app = elements.frontmostApplication()
        let element = elements.focusedElement()
        if let element, TextInsertionPolicy.isSecure(element) {
            return .refusedSecureField
        }

        guard let element else {
            // Some Electron apps expose no focused element; ⌘V still lands in their text field.
            // Without a frontmost app there is nowhere to paste, so keep the text on the clipboard.
            guard app.bundleIdentifier != nil else {
                copyToClipboard(text)
                return .copiedToClipboard(.noFocusedTextField)
            }
            return await paste(text, into: app.bundleIdentifier)
        }

        if TextInsertionPolicy.isEditable(element),
           element.isSelectedTextSettable,
           await insertViaAccessibility(text, into: element) {
            return .insertedViaAccessibility
        }
        return await paste(text, into: app.bundleIdentifier)
    }

    var canUndoLastInsertion: Bool { undoRecord != nil }

    func undoLastInsertion() async -> Bool {
        guard let record = undoRecord else { return false }
        undoRecord = nil
        guard elements.isAccessibilityTrusted, !elements.isSecureInputActive else { return false }
        switch record {
        case let .accessibility(element, valueBefore, valueAfter, selectionBefore, replacedText, insertedLength):
            // Only the same field, untouched since: anything else would undo the user's own edits.
            guard let focused = elements.focusedElement(), focused.isSame(as: element),
                  focused.value == valueAfter else { return false }
            // Select what was inserted and put back what it replaced, so formatting survives.
            if let selectionBefore,
               focused.setSelectedRange(NSRange(location: selectionBefore.location, length: insertedLength)),
               focused.setSelectedText(replacedText),
               focused.value == valueBefore {
                _ = focused.setSelectedRange(selectionBefore)
                return true
            }
            // Otherwise the whole value goes back.
            guard focused.isValueSettable, focused.setValue(valueBefore), focused.value == valueBefore else {
                return false
            }
            if let selectionBefore { _ = focused.setSelectedRange(selectionBefore) }
            return true

        case let .paste(bundleIdentifier, valueAfter):
            guard elements.frontmostApplication().bundleIdentifier == bundleIdentifier else { return false }
            // When the field is readable it must still show what the paste left there.
            if let valueAfter, let current = elements.focusedElement()?.value, current != valueAfter {
                return false
            }
            return keystrokes.sendUndo()
        }
    }

    /// Writes through Accessibility only when the result can be checked; an unreadable value
    /// means the write cannot be verified, so paste is used instead. Apps that apply the write
    /// asynchronously get one short re-check, so a late update is not pasted a second time.
    private func insertViaAccessibility(_ text: String, into element: any FocusedTextElement) async -> Bool {
        guard let before = element.value else { return false }
        let selectedBefore = element.selectedText
        let rangeBefore = element.selectedRange
        guard element.setSelectedText(text) else { return false }
        // Replacing a selection with identical text legitimately leaves the value unchanged.
        if selectedBefore == text { return true }
        var after = element.value
        if after == nil || after == before {
            await sleep(.milliseconds(80))
            after = element.value
        }
        guard let after, after != before else { return false }
        undoRecord = .accessibility(
            element: element,
            valueBefore: before,
            valueAfter: after,
            selectionBefore: rangeBefore,
            replacedText: selectedBefore ?? "",
            insertedLength: (text as NSString).length
        )
        return true
    }

    private func paste(_ text: String, into bundleIdentifier: String?) async -> TextInsertionResult {
        let saved = pasteboard.snapshot()
        let writtenChangeCount = pasteboard.write(text: text, transient: true)
        guard keystrokes.sendPaste() else {
            // Leave the text available rather than silently restoring.
            return .copiedToClipboard(.pasteFailed)
        }
        await sleep(restoreDelay)
        if pasteboard.changeCount == writtenChangeCount {
            pasteboard.restore(saved)
        }
        if let bundleIdentifier {
            undoRecord = .paste(bundleIdentifier: bundleIdentifier, valueAfter: elements.focusedElement()?.value)
        }
        return .insertedViaPaste
    }
}

// MARK: - System implementations

@MainActor
final class SystemFocusedElementProvider: FocusedElementProviding {
    private let messagingTimeout: Float

    nonisolated init(messagingTimeout: Float = 0.25) {
        self.messagingTimeout = messagingTimeout
    }

    var isAccessibilityTrusted: Bool {
        SystemAccessibilityAuthorizer().isTrusted(prompt: false)
    }

    var isSecureInputActive: Bool {
        IsSecureEventInputEnabled()
    }

    func frontmostApplication() -> (bundleIdentifier: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    func focusedElement() -> (any FocusedTextElement)? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
            let focused,
            CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focused as! AXUIElement // swiftlint:disable:this force_cast
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AXFocusedTextElement(element: element)
    }
}

@MainActor
final class AXFocusedTextElement: FocusedTextElement {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    var role: String? { stringAttribute(kAXRoleAttribute) }
    var subrole: String? { stringAttribute(kAXSubroleAttribute) }
    var value: String? { stringAttribute(kAXValueAttribute) }
    var selectedText: String? { stringAttribute(kAXSelectedTextAttribute) }
    var isSelectedTextSettable: Bool { isSettable(kAXSelectedTextAttribute) }
    var isValueSettable: Bool { isSettable(kAXValueAttribute) }

    var selectedRange: NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        let axValue = value as! AXValue // swiftlint:disable:this force_cast
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    func setSelectedText(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }

    func setSelectedRange(_ range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    func setValue(_ value: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) == .success
    }

    func isSame(as other: any FocusedTextElement) -> Bool {
        guard let other = other as? AXFocusedTextElement else { return false }
        return CFEqual(element, other.element)
    }

    private func stringAttribute(_ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }
}

@MainActor
final class SystemDictationPasteboard: DictationPasteboard {
    private static let transientTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    ]
    nonisolated(unsafe) private let pasteboard: NSPasteboard

    nonisolated init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type.rawValue] = data
                }
            }
            return values
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    @discardableResult
    func write(text: String, transient: Bool) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient {
            for type in Self.transientTypes {
                item.setData(Data(), forType: type)
            }
        }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}

@MainActor
final class SystemPasteKeystrokeSender: PasteKeystrokeSending {
    nonisolated init() {}

    func sendPaste() -> Bool {
        sendCommand(CGKeyCode(kVK_ANSI_V))
    }

    func sendUndo() -> Bool {
        sendCommand(CGKeyCode(kVK_ANSI_Z))
    }

    /// The key with ⌘ and nothing else.
    private func sendCommand(_ keyCode: CGKeyCode) -> Bool {
        // Private state so physically held modifiers (e.g. the trigger key) don't leak into ⌘V.
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
