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

        let result = await service.insert("parola")

        XCTAssertEqual(result, .refusedSecureField)
        XCTAssertEqual(pasteboard.writeCount, 0)
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

    func testCurrentContextReadsSelectionButNotFromSecureFields() {
        elements.app = ("com.apple.Notes", "Notlar")
        elements.element = FakeTextElement(role: "AXTextArea", value: "abc", selectedText: "b")
        XCTAssertEqual(
            service.currentContext(),
            DictationTargetSnapshot(bundleIdentifier: "com.apple.Notes", appName: "Notlar", selectedText: "b")
        )

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
    private(set) var setCount = 0

    init(
        role: String?,
        subrole: String? = nil,
        value: String?,
        selectedText: String? = nil,
        selectedTextSettable: Bool = true
    ) {
        self.role = role
        self.subrole = subrole
        self.value = value
        self.selectedText = selectedText
        self.isSelectedTextSettable = selectedTextSettable
    }

    func setSelectedText(_ text: String) -> Bool {
        setCount += 1
        guard isSelectedTextSettable else { return false }
        if !ignoresWrites {
            value = (value ?? "") + text
            selectedText = nil
        }
        return true
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
    var succeeds = true
    private(set) var pasteCount = 0

    func sendPaste() -> Bool {
        guard succeeds else { return false }
        pasteCount += 1
        return true
    }
}
