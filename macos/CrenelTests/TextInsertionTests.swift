import XCTest
@testable import Crenel

@MainActor
final class TextInsertionTests: XCTestCase {
    private var elements: FakeFocusedElementProvider!
    private var pasteboard: FakePasteboard!
    private var keystrokes: FakeKeystrokes!
    private var service: TextInsertionService!

    override func setUp() async throws {
        elements = FakeFocusedElementProvider()
        pasteboard = FakePasteboard()
        keystrokes = FakeKeystrokes()
        service = TextInsertionService(
            elements: elements,
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            restoreDelay: .milliseconds(400),
            sleep: { _ in }
        )
    }

    func testAccessibilityInsertionUsesSelectedTextAttribute() async {
        let field = FakeTextElement(role: "AXTextArea", value: "Merhaba ")
        elements.element = field

        let result = await service.insert("dünya")

        XCTAssertEqual(result, .insertedViaAccessibility)
        XCTAssertEqual(field.value, "Merhaba dünya")
        XCTAssertEqual(keystrokes.pasteCount, 0)
        XCTAssertEqual(pasteboard.writeCount, 0)
    }

    func testUnverifiedAccessibilityWriteFallsBackToPasteAndRestoresPasteboard() async {
        let field = FakeTextElement(role: "AXTextField", value: "abc")
        field.ignoresWrites = true
        elements.element = field
        let original = PasteboardSnapshot(items: [
            ["public.utf8-plain-text": Data("eski".utf8), "public.rtf": Data("{\\rtf1}".utf8)],
            ["public.png": Data([0x89, 0x50])]
        ])
        pasteboard.contents = original

        let result = await service.insert("yeni")

        XCTAssertEqual(result, .insertedViaPaste)
        XCTAssertEqual(keystrokes.pasteCount, 1)
        XCTAssertEqual(pasteboard.lastWrittenText, "yeni")
        XCTAssertEqual(pasteboard.lastWriteWasTransient, true)
        XCTAssertEqual(pasteboard.contents, original, "All items and types must be restored")
    }

    func testPasteboardIsNotRestoredWhenChangedDuringDelay() async {
        elements.element = FakeTextElement(role: "AXTextField", value: "x", selectedTextSettable: false)
        pasteboard.contents = PasteboardSnapshot(items: [["public.utf8-plain-text": Data("eski".utf8)]])
        let userCopy = PasteboardSnapshot(items: [["public.utf8-plain-text": Data("kullanıcı".utf8)]])
        service = TextInsertionService(
            elements: elements,
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            sleep: { [pasteboard] _ in
                await MainActor.run { pasteboard!.simulateExternalCopy(userCopy) }
            }
        )

        let result = await service.insert("dikte")

        XCTAssertEqual(result, .insertedViaPaste)
        XCTAssertEqual(pasteboard.contents, userCopy)
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func testSecureTextFieldIsRefusedWithoutTouchingPasteboard() async {
        elements.element = FakeTextElement(role: "AXTextField", subrole: "AXSecureTextField", value: "")

        let result = await service.insert("parola")

        XCTAssertEqual(result, .refusedSecureField)
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(keystrokes.pasteCount, 0)
    }

    func testSecureInputActiveIsRefusedInAnyApp() async {
        elements.app = ("com.google.Chrome", "Google Chrome")
        elements.isSecureInputActive = true

        for trusted in [false, true] {
            elements.isAccessibilityTrusted = trusted
            XCTAssertTrue(service.currentContext().isSecureTarget)
            let result = await service.insert("parola")
            XCTAssertEqual(result, .refusedSecureField)
            XCTAssertEqual(pasteboard.writeCount, 0)
        }
    }

    func testAppWithoutFocusedElementGetsPaste() async {
        elements.app = ("com.tinyspeck.slackmacgap", "Slack")
        elements.element = nil

        let result = await service.insert("selam ekip")

        XCTAssertEqual(result, .insertedViaPaste)
        XCTAssertEqual(keystrokes.pasteCount, 1)
    }

    func testUnreadableValueSkipsAccessibilityWriteAndPastes() async {
        let field = FakeTextElement(role: "AXTextArea", value: nil)
        elements.app = ("com.googlecode.iterm2", "iTerm2")
        elements.element = field

        let result = await service.insert("ls -la")

        XCTAssertEqual(result, .insertedViaPaste)
        XCTAssertEqual(field.setCount, 0, "An unverifiable write must not run, or text could appear twice")
    }

    func testNoFrontmostAppAndNoElementCopiesToClipboard() async {
        elements.app = (nil, nil)
        elements.element = nil

        let result = await service.insert("panoya")

        XCTAssertEqual(result, .copiedToClipboard(.noFocusedTextField))
        XCTAssertEqual(pasteboard.lastWrittenText, "panoya")
        XCTAssertEqual(pasteboard.lastWriteWasTransient, false)
        XCTAssertEqual(keystrokes.pasteCount, 0)
    }

    func testNonEditableFocusedElementGetsPaste() async {
        elements.element = FakeTextElement(role: "AXGroup", value: nil, selectedTextSettable: false)

        let result = await service.insert("web alanı")

        XCTAssertEqual(result, .insertedViaPaste)
    }

    func testMissingAccessibilityPermissionCopiesToClipboard() async {
        elements.isAccessibilityTrusted = false
        elements.element = FakeTextElement(role: "AXTextArea", value: "")

        let result = await service.insert("izin yok")

        XCTAssertEqual(result, .copiedToClipboard(.accessibilityPermissionMissing))
        XCTAssertEqual(pasteboard.lastWrittenText, "izin yok")
    }

    func testPasteKeystrokeFailureLeavesTextOnClipboard() async {
        elements.app = ("com.google.Chrome", "Chrome")
        keystrokes.succeeds = false
        pasteboard.contents = PasteboardSnapshot(items: [["public.utf8-plain-text": Data("eski".utf8)]])

        let result = await service.insert("kalmalı")

        XCTAssertEqual(result, .copiedToClipboard(.pasteFailed))
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(pasteboard.lastWrittenText, "kalmalı")
    }

    // MARK: Undo

    func testUndoRestoresAccessibilityInsertionAndSelection() async {
        let field = FakeTextElement(role: "AXTextArea", value: "Merhaba  nasılsın",
                                    selectedRange: NSRange(location: 8, length: 0))
        elements.element = field

        _ = await service.insert("dünya")
        XCTAssertEqual(field.value, "Merhaba dünya nasılsın")
        XCTAssertTrue(service.canUndoLastInsertion)

        let undone = await service.undoLastInsertion()

        XCTAssertTrue(undone)
        XCTAssertEqual(field.value, "Merhaba  nasılsın")
        XCTAssertEqual(field.selectedRange, NSRange(location: 8, length: 0))
        XCTAssertEqual(field.setValueCount, 0, "The range path keeps the field's formatting")
        XCTAssertFalse(service.canUndoLastInsertion)
    }

    func testUndoPutsBackTheReplacedSelection() async {
        let field = FakeTextElement(role: "AXTextArea", value: "selam ekip", selectedText: "selam",
                                    selectedRange: NSRange(location: 0, length: 5))
        elements.element = field

        _ = await service.insert("Merhabalar")
        XCTAssertEqual(field.value, "Merhabalar ekip")
        let undone = await service.undoLastInsertion()

        XCTAssertTrue(undone)
        XCTAssertEqual(field.value, "selam ekip")
        XCTAssertEqual(field.selectedRange, NSRange(location: 0, length: 5))
    }

    func testUndoFallsBackToTheWholeValueWithoutARange() async {
        let field = FakeTextElement(role: "AXTextField", value: "abc")
        elements.element = field

        _ = await service.insert("def")
        let undone = await service.undoLastInsertion()

        XCTAssertTrue(undone)
        XCTAssertEqual(field.value, "abc")
        XCTAssertEqual(field.setValueCount, 1)
    }

    func testUndoRefusesWhenTheFieldChangedSince() async {
        let field = FakeTextElement(role: "AXTextArea", value: "a", selectedRange: NSRange(location: 1, length: 0))
        elements.element = field

        _ = await service.insert("b")
        field.value = "ab and more typing"
        let undone = await service.undoLastInsertion()

        XCTAssertFalse(undone)
        XCTAssertEqual(field.value, "ab and more typing")
    }

    func testUndoRefusesWhenAnotherFieldIsFocused() async {
        let field = FakeTextElement(role: "AXTextArea", value: "a", selectedRange: NSRange(location: 1, length: 0))
        elements.element = field

        _ = await service.insert("b")
        let other = FakeTextElement(role: "AXTextArea", value: "ab", selectedRange: NSRange(location: 2, length: 0))
        elements.element = other
        let undone = await service.undoLastInsertion()

        XCTAssertFalse(undone)
        XCTAssertEqual(field.value, "ab")
        XCTAssertEqual(other.value, "ab")
    }

    func testUndoAfterPasteSendsCommandZToTheSameReadableField() async {
        elements.app = ("com.tinyspeck.slackmacgap", "Slack")
        let field = FakeTextElement(role: "AXTextField", value: "", selectedTextSettable: false)
        elements.element = field
        keystrokes.onPaste = { field.value = "selam ekip" }

        _ = await service.insert("selam ekip")
        XCTAssertTrue(service.canUndoLastInsertion)
        let undone = await service.undoLastInsertion()

        XCTAssertTrue(undone)
        XCTAssertEqual(keystrokes.undoCount, 1)
    }

    func testUndoAfterPasteRefusesUnidentifiableAndUnreadableOrChangedFields() async {
        for scenario in ["missing", "unreadable", "different"] {
            let field = FakeTextElement(role: "AXTextArea", value: "", selectedTextSettable: false)
            elements.element = scenario == "missing" ? nil : field
            keystrokes.onPaste = { field.value = "text" }
            _ = await service.insert("text")
            elements.element = FakeTextElement(role: "AXTextArea", value: scenario == "unreadable" ? nil : "text")
            let undone = await service.undoLastInsertion()
            XCTAssertFalse(undone)
            XCTAssertEqual(keystrokes.undoCount, 0)
        }
    }

    func testUndoAfterPasteIsRefusedInAnotherApp() async {
        elements.app = ("com.tinyspeck.slackmacgap", "Slack")
        elements.element = nil

        _ = await service.insert("selam ekip")
        elements.app = ("com.apple.Safari", "Safari")
        let undone = await service.undoLastInsertion()

        XCTAssertFalse(undone)
        XCTAssertEqual(keystrokes.undoCount, 0)
    }

    func testUndoAfterPasteIsRefusedWhenTheReadableFieldChanged() async {
        let field = FakeTextElement(role: "AXGroup", value: "x", selectedTextSettable: false)
        elements.element = field

        _ = await service.insert("web")
        field.value = "x and the user kept typing"
        let undone = await service.undoLastInsertion()

        XCTAssertFalse(undone)
        XCTAssertEqual(keystrokes.undoCount, 0)
    }

    func testNothingToUndoAfterClipboardFallback() async {
        elements.isAccessibilityTrusted = false

        _ = await service.insert("izin yok")

        XCTAssertFalse(service.canUndoLastInsertion)
        let undone = await service.undoLastInsertion()
        XCTAssertFalse(undone)
    }

    func testReplacementRequiresOriginalAppFieldRangeAndText() async {
        func field() -> FakeTextElement {
            FakeTextElement(role: "AXTextArea", value: "cat cat", selectedText: "cat",
                            selectedRange: NSRange(location: 0, length: 3))
        }
        for change in ["field", "application", "range", "text", "unchanged"] {
            elements.app = ("notes", "Notes")
            let original = field()
            elements.element = original
            let target = service.currentContext()
            switch change {
            case "field": elements.element = field()
            case "application": elements.app = ("mail", "Mail")
            case "range": original.selectedRange = NSRange(location: 4, length: 3)
            case "text": original.selectedText = "new"
            default: break
            }
            let result = await service.insert("dog", replacing: target)
            if change == "unchanged" {
                XCTAssertEqual(result, .insertedViaAccessibility)
                XCTAssertEqual(original.value, "dog cat")
            } else {
                XCTAssertEqual(result, .copiedToClipboard(.targetChanged))
                XCTAssertEqual(original.setCount, 0)
                XCTAssertEqual(pasteboard.lastWriteWasTransient, true)
                XCTAssertEqual(keystrokes.pasteCount, 0)
            }
        }
    }

    func testCurrentContextReadsSelectionButNotFromSecureFields() {
        elements.app = ("com.apple.Notes", "Notlar")
        elements.element = FakeTextElement(role: "AXTextArea", value: "abc", selectedText: "b")
        XCTAssertEqual(service.currentContext().bundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(service.currentContext().appName, "Notlar")
        XCTAssertEqual(service.currentContext().selectedText, "b")

        elements.element = FakeTextElement(role: "AXSecureTextField", value: "", selectedText: "gizli")
        XCTAssertNil(service.currentContext().selectedText)
    }
}

// MARK: - Fakes

@MainActor
final class FakeTextElement: FocusedTextElement {
    let role: String?
    let subrole: String?
    var value: String?
    var selectedText: String?
    let isSelectedTextSettable: Bool
    var isValueSettable: Bool { isSelectedTextSettable }
    var ignoresWrites = false
    /// nil: the element reports no range and writes land at the end of the value.
    var selectedRange: NSRange?
    var rangeSettable = true
    private(set) var setCount = 0
    private(set) var setValueCount = 0

    init(
        role: String?,
        subrole: String? = nil,
        value: String?,
        selectedText: String? = nil,
        selectedTextSettable: Bool = true,
        selectedRange: NSRange? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.value = value
        self.selectedText = selectedText
        self.isSelectedTextSettable = selectedTextSettable
        self.selectedRange = selectedRange
    }

    func setSelectedText(_ text: String) -> Bool {
        setCount += 1
        guard isSelectedTextSettable else { return false }
        if !ignoresWrites {
            let current = (value ?? "") as NSString
            let range = selectedRange ?? NSRange(location: current.length, length: 0)
            value = current.replacingCharacters(in: range, with: text)
            if selectedRange != nil {
                selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
            }
            selectedText = nil
        }
        return true
    }

    func setSelectedRange(_ range: NSRange) -> Bool {
        guard rangeSettable, selectedRange != nil else { return false }
        let current = (value ?? "") as NSString
        guard NSMaxRange(range) <= current.length else { return false }
        selectedRange = range
        selectedText = current.substring(with: range)
        return true
    }

    func setValue(_ value: String) -> Bool {
        setValueCount += 1
        guard isValueSettable, !ignoresWrites else { return false }
        self.value = value
        return true
    }

    func isSame(as other: any FocusedTextElement) -> Bool {
        self === other
    }
}

@MainActor
final class FakeFocusedElementProvider: FocusedElementProviding {
    var isAccessibilityTrusted = true
    var isSecureInputActive = false
    var app: (bundleIdentifier: String?, name: String?) = ("com.apple.TextEdit", "TextEdit")
    var element: (any FocusedTextElement)?

    func frontmostApplication() -> (bundleIdentifier: String?, name: String?) { app }
    func focusedElement() -> (any FocusedTextElement)? { element }
}

@MainActor
final class FakePasteboard: DictationPasteboard {
    var contents = PasteboardSnapshot(items: [])
    private(set) var changeCount = 0
    private(set) var writeCount = 0
    private(set) var restoreCount = 0
    private(set) var lastWrittenText: String?
    private(set) var lastWriteWasTransient: Bool?

    func snapshot() -> PasteboardSnapshot { contents }

    func restore(_ snapshot: PasteboardSnapshot) {
        restoreCount += 1
        contents = snapshot
        changeCount += 1
    }

    func write(text: String, transient: Bool) -> Int {
        writeCount += 1
        lastWrittenText = text
        lastWriteWasTransient = transient
        contents = PasteboardSnapshot(items: [["public.utf8-plain-text": Data(text.utf8)]])
        changeCount += 1
        return changeCount
    }

    func simulateExternalCopy(_ snapshot: PasteboardSnapshot) {
        contents = snapshot
        changeCount += 1
    }
}

@MainActor
final class FakeKeystrokes: PasteKeystrokeSending {
    var onPaste: (() -> Void)?
    var succeeds = true
    private(set) var pasteCount = 0
    private(set) var undoCount = 0

    func sendPaste() -> Bool {
        guard succeeds else { return false }
        pasteCount += 1
        onPaste?()
        return true
    }

    func sendUndo() -> Bool {
        guard succeeds else { return false }
        undoCount += 1
        return true
    }
}
