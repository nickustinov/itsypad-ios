import XCTest
@testable import ItsypadCore

/// Reproduces tap-to-place-caret after pasting: the caret must land on the
/// tapped line, not collapse to the top line. Uses the same manually built
/// TextKit 1 stack as EditorView.
final class EditorTapHitTestTests: XCTestCase {
    private var window: UIWindow!
    private var textView: EditorTextView!
    private var coordinator: EditorCoordinator!

    private static let pastedText = (0..<40)
        .map { "line \($0) with some sample words" }
        .joined(separator: "\n")

    override func setUp() {
        super.setUp()

        // Mirror EditorView.updateUIView's stack exactly
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        textView = EditorTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), textContainer: textContainer)
        textView.ownedTextStorage = textStorage

        coordinator = EditorCoordinator()
        textView.font = coordinator.font // updateUIView applies this in production
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.language = "plain"

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(textView)
        window.makeKeyAndVisible()
        textView.layoutIfNeeded()
    }

    override func tearDown() {
        textView.delegate = nil
        coordinator.textView = nil
        coordinator = nil
        textView.removeFromSuperview()
        textView = nil
        window = nil
        super.tearDown()
    }

    private func lineNumber(atOffset offset: Int) -> Int {
        let prefix = (textView.text as NSString).substring(to: min(offset, (textView.text as NSString).length))
        return prefix.components(separatedBy: "\n").count - 1
    }

    private func pumpRunLoop(seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func assertHitTestMapsYToLines(_ context: String) {
        let font = coordinator.font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        // Tap in the middle of the view, well past the first line
        let point = CGPoint(x: 60, y: 300)
        guard let pos = textView.closestPosition(to: point) else {
            XCTFail("\(context): closestPosition returned nil")
            return
        }
        let offset = textView.offset(from: textView.beginningOfDocument, to: pos)
        let line = lineNumber(atOffset: offset)
        let expectedLine = Int((point.y - textView.textContainerInset.top) / lineHeight)

        NSLog("[TapDebug] \(context): point=\(point) -> offset=\(offset) line=\(line) expected≈\(expectedLine) containerSize=\(textView.textContainer.size) usedRect=\(textView.layoutManager.usedRect(for: textView.textContainer))")

        XCTAssertGreaterThan(line, 5, "\(context): caret collapsed to top (line \(line)) for tap at y=\(point.y)")
        XCTAssertLessThan(abs(line - expectedLine), 3, "\(context): caret on line \(line), expected ≈\(expectedLine)")
    }

    func testHitTestAfterSettingTextDirectly() {
        textView.text = Self.pastedText
        textView.layoutIfNeeded()
        assertHitTestMapsYToLines("plain text set")
    }

    func testHitTestAfterPasteViaTextInput() {
        // Simulate the real paste path: insert through UITextInput like
        // UIKit's paste: does, then let the delegate/highlight pipeline run
        textView.text = ""
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.insertText(Self.pastedText)
        coordinator.textViewDidChange(textView)
        textView.layoutIfNeeded()
        pumpRunLoop(seconds: 0.4) // let the debounced highlight apply
        assertHitTestMapsYToLines("after insertText + highlight")
    }

    func testHitTestAfterSystemPaste() {
        UIPasteboard.general.string = Self.pastedText
        textView.text = ""
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.paste(nil)
        textView.layoutIfNeeded()
        pumpRunLoop(seconds: 0.4)
        assertHitTestMapsYToLines("after system paste")
    }
}
