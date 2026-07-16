import XCTest
@testable import ItsypadCore

final class EditorCoordinatorTests: XCTestCase {
    private var coordinator: EditorCoordinator!
    private var textView: EditorTextView!

    override func setUp() {
        super.setUp()
        coordinator = EditorCoordinator()
        textView = EditorTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.language = "plain"
    }

    override func tearDown() {
        textView.delegate = nil
        coordinator.textView = nil
        coordinator = nil
        textView = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitialLanguageIsPlain() {
        let c = EditorCoordinator()
        XCTAssertEqual(c.language, "plain")
    }

    func testInitialPendingLocalEditsIsZero() {
        XCTAssertEqual(coordinator.pendingLocalEdits, 0)
    }

    func testInitialAppliedWordWrapIsTrue() {
        XCTAssertTrue(coordinator.appliedWordWrap)
    }

    func testInitialAppliedShowLineNumbersIsFalse() {
        XCTAssertFalse(coordinator.appliedShowLineNumbers)
    }

    func testLinkURLKeyValue() {
        XCTAssertEqual(
            EditorCoordinator.linkURLKey,
            NSAttributedString.Key("ItsypadLinkURL")
        )
    }

    // MARK: - Newline: auto-indent

    func testNewlinePreservesLeadingSpaces() {
        textView.text = "    hello"
        textView.selectedRange = NSRange(location: 9, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 9, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "    hello\n    ")
    }

    func testNewlinePreservesLeadingTab() {
        textView.text = "\thello"
        textView.selectedRange = NSRange(location: 6, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 6, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "\thello\n\t")
    }

    func testNewlineWithNoIndentReturnsTrue() {
        textView.text = "hello"
        textView.selectedRange = NSRange(location: 5, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 5, length: 0),
            replacementText: "\n"
        )

        XCTAssertTrue(result)
    }

    // MARK: - Newline: list continuation

    func testNewlineContinuesBulletList() {
        textView.text = "- item one"
        textView.selectedRange = NSRange(location: 10, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 10, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "- item one\n- ")
    }

    func testNewlineContinuesNumberedList() {
        textView.text = "1. first"
        textView.selectedRange = NSRange(location: 8, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 8, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "1. first\n2. ")
    }

    func testNewlineContinuesChecklistUnchecked() {
        textView.text = "- [ ] task"
        textView.selectedRange = NSRange(location: 10, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 10, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "- [ ] task\n- [ ] ")
    }

    func testNewlineAfterCheckedContinuesWithUnchecked() {
        textView.text = "- [x] done"
        textView.selectedRange = NSRange(location: 10, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 10, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "- [x] done\n- [ ] ")
    }

    func testNewlineContinuesIndentedBulletList() {
        textView.text = "    - nested"
        textView.selectedRange = NSRange(location: 12, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 12, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "    - nested\n    - ")
    }

    // MARK: - Newline: empty list item removal

    func testNewlineOnEmptyBulletRemovesPrefix() {
        textView.text = "- "
        textView.selectedRange = NSRange(location: 2, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 2, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "")
    }

    func testNewlineOnEmptyNumberedRemovesPrefix() {
        textView.text = "1. "
        textView.selectedRange = NSRange(location: 3, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "")
    }

    func testNewlineOnEmptyChecklistRemovesPrefix() {
        textView.text = "- [ ] "
        textView.selectedRange = NSRange(location: 6, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 6, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "")
    }

    // MARK: - Tab: insert spaces

    func testTabInsertsSpacesOnPlainText() {
        textView.text = "hello"
        textView.selectedRange = NSRange(location: 5, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 5, length: 0),
            replacementText: "\t"
        )

        XCTAssertFalse(result)
        let tabWidth = SettingsStore.shared.tabWidth
        let expected = "hello" + String(repeating: " ", count: tabWidth)
        XCTAssertEqual(textView.text, expected)
    }

    // MARK: - Tab: indent list item

    func testTabIndentsListItem() {
        textView.text = "- item"
        textView.selectedRange = NSRange(location: 6, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 6, length: 0),
            replacementText: "\t"
        )

        XCTAssertFalse(result)
        let indent = SettingsStore.shared.indentString
        XCTAssertEqual(textView.text, indent + "- item")
    }

    // MARK: - Backspace at list prefix boundary

    func testBackspaceAtBulletPrefixRemovesPrefix() {
        textView.text = "- content"
        textView.selectedRange = NSRange(location: 2, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 1, length: 1),
            replacementText: ""
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "content")
    }

    func testBackspaceAtChecklistPrefixRemovesPrefix() {
        textView.text = "- [ ] content"
        textView.selectedRange = NSRange(location: 6, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 5, length: 1),
            replacementText: ""
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "content")
    }

    func testBackspaceAtIndentedBulletKeepsIndent() {
        textView.text = "    - content"
        textView.selectedRange = NSRange(location: 6, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 5, length: 1),
            replacementText: ""
        )

        XCTAssertFalse(result)
        XCTAssertEqual(textView.text, "    content")
    }

    // MARK: - textViewDidChange increments pendingLocalEdits

    func testTextViewDidChangeIncrementsPendingLocalEdits() {
        XCTAssertEqual(coordinator.pendingLocalEdits, 0)
        coordinator.textViewDidChange(textView)
        XCTAssertEqual(coordinator.pendingLocalEdits, 1)
        coordinator.textViewDidChange(textView)
        XCTAssertEqual(coordinator.pendingLocalEdits, 2)
    }

    // MARK: - indentLines

    func testIndentLinesSingleLine() {
        textView.text = "hello"
        textView.selectedRange = NSRange(location: 0, length: 0)

        coordinator.indentLines(tv: textView)

        let indent = SettingsStore.shared.indentString
        XCTAssertEqual(textView.text, indent + "hello")
    }

    func testIndentLinesMultipleLines() {
        textView.text = "line one\nline two"
        textView.selectedRange = NSRange(location: 0, length: 17)

        coordinator.indentLines(tv: textView)

        let indent = SettingsStore.shared.indentString
        XCTAssertEqual(textView.text, "\(indent)line one\n\(indent)line two")
    }

    // MARK: - outdentLines

    func testOutdentLinesRemovesIndent() {
        let indent = SettingsStore.shared.indentString
        textView.text = "\(indent)hello"
        textView.selectedRange = NSRange(location: 0, length: 0)

        coordinator.outdentLines(tv: textView)

        XCTAssertEqual(textView.text, "hello")
    }

    func testOutdentLinesNoIndentIsNoop() {
        textView.text = "hello"
        textView.selectedRange = NSRange(location: 0, length: 0)

        coordinator.outdentLines(tv: textView)

        XCTAssertEqual(textView.text, "hello")
    }

    func testOutdentMultipleLines() {
        let indent = SettingsStore.shared.indentString
        textView.text = "\(indent)line one\n\(indent)line two"
        textView.selectedRange = NSRange(location: 0, length: textView.text.count)

        coordinator.outdentLines(tv: textView)

        XCTAssertEqual(textView.text, "line one\nline two")
    }

    // MARK: - Language

    func testLanguageCanBeChanged() {
        coordinator.language = "swift"
        XCTAssertEqual(coordinator.language, "swift")
    }

    func testNewlineInCodeLanguageDoesNotContinueList() {
        coordinator.language = "swift"
        textView.text = "- item"
        textView.selectedRange = NSRange(location: 6, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 6, length: 0),
            replacementText: "\n"
        )

        XCTAssertTrue(result)
    }

    // MARK: - Keyboard avoidance on window attach

    func testKeyboardOverlapGeometry() {
        // Exercised directly – notification/static-driven variants race the
        // host app's real keyboard during test runs
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let tv = EditorTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.addSubview(tv)

        // Keyboard covering the bottom 300pt
        tv.applyKeyboardOverlap(CGRect(x: 0, y: 500, width: 400, height: 300))
        XCTAssertEqual(tv.contentInset.bottom, 300)

        // Keyboard hidden (below the screen)
        tv.applyKeyboardOverlap(CGRect(x: 0, y: 800, width: 400, height: 300))
        XCTAssertEqual(tv.contentInset.bottom, 0)

        // Float noise must not count as a change (jitter guard)
        tv.applyKeyboardOverlap(CGRect(x: 0, y: 500, width: 400, height: 300))
        tv.applyKeyboardOverlap(CGRect(x: 0, y: 500.0000000000001, width: 400, height: 300))
        XCTAssertEqual(tv.contentInset.bottom, 300)
    }

    // MARK: - Interaction reset gating

    func testActivationWithoutBackgroundingDoesNotResetInteractions() {
        // didBecomeActive also fires when a system alert is dismissed (e.g.
        // the cross-app paste permission prompt) – the reset must stay off
        let tv = EditorTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertFalse(tv.needsInteractionReset)

        tv.appDidBecomeActive()

        XCTAssertFalse(tv.needsInteractionReset)
    }

    func testBackgroundingArmsInteractionResetAndActivationConsumesIt() {
        let tv = EditorTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        tv.appDidEnterBackground()
        XCTAssertTrue(tv.needsInteractionReset)

        tv.appDidBecomeActive()
        XCTAssertFalse(tv.needsInteractionReset)

        // A later activation (e.g. after a paste permission alert) must not
        // run the reset again without a new background transition
        tv.appDidBecomeActive()
        XCTAssertFalse(tv.needsInteractionReset)
    }

    // MARK: - UTF-16 correctness with emoji

    func testToggleChecklistWithEmojiKeepsCursorAtUTF16Position() {
        textView.text = "milk 🥛"          // 7 UTF-16 units
        textView.selectedRange = NSRange(location: 7, length: 0)

        textView.toggleChecklist()

        XCTAssertEqual(textView.text, "- [ ] milk 🥛")
        // Prefix adds 6 UTF-16 units; cursor must end up at 13, not clamped short
        XCTAssertEqual(textView.selectedRange.location, 13)
    }

    func testIndentSelectionWithEmojiSelectsWholeBlock() {
        textView.text = "🥛 a\n🥛 b"        // two lines, 4 UTF-16 units each + newline
        textView.selectedRange = NSRange(location: 0, length: (textView.text as NSString).length)

        coordinator.indentLines(tv: textView)

        let expected = (textView.text as NSString).length
        XCTAssertEqual(textView.selectedRange.length, expected)
    }

    func testOutdentSelectionWithEmojiSelectsWholeBlock() {
        textView.text = "    🥛 a\n    🥛 b"
        textView.selectedRange = NSRange(location: 0, length: (textView.text as NSString).length)

        coordinator.outdentLines(tv: textView)

        XCTAssertEqual(textView.text, "🥛 a\n🥛 b")
        XCTAssertEqual(textView.selectedRange.length, (textView.text as NSString).length)
    }

    // MARK: - Keyboard traits per language

    func testPlainLanguageEnablesKeyboardIntelligence() {
        XCTAssertEqual(textView.autocapitalizationType, .sentences)
        XCTAssertEqual(textView.autocorrectionType, .default)
        XCTAssertEqual(textView.spellCheckingType, .default)
    }

    func testCodeLanguageDisablesKeyboardIntelligence() {
        coordinator.language = "swift"
        XCTAssertEqual(textView.autocapitalizationType, .none)
        XCTAssertEqual(textView.autocorrectionType, .no)
        XCTAssertEqual(textView.spellCheckingType, .no)
    }

    func testSwitchingBackToMarkdownRestoresKeyboardIntelligence() {
        coordinator.language = "swift"
        coordinator.language = "markdown"
        XCTAssertEqual(textView.autocapitalizationType, .sentences)
        XCTAssertEqual(textView.autocorrectionType, .default)
        XCTAssertEqual(textView.spellCheckingType, .default)
    }

    // MARK: - Regular text input passes through

    func testRegularTextReturnsTrue() {
        textView.text = "hello"
        textView.selectedRange = NSRange(location: 5, length: 0)

        let result = coordinator.textView(
            textView, shouldChangeTextIn: NSRange(location: 5, length: 0),
            replacementText: " world"
        )

        XCTAssertTrue(result)
    }
}
