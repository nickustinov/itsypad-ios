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
