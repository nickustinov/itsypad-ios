import SwiftUI

private class EditorScrollWrapper: UIScrollView {
    var onBoundsChange: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            onBoundsChange?()
        }
    }
}

struct EditorView: UIViewRepresentable {
    let tabID: UUID
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore

    // Shared per-tab views — preserves undo, cursor, scroll position per tab
    private static var textViews: [UUID: EditorTextView] = [:]
    private static var coordinators: [UUID: EditorCoordinator] = [:]
    private static var gutterViews: [UUID: LineNumberGutterView] = [:]
    private static var scrollWrappers: [UUID: EditorScrollWrapper] = [:]

    static func textView(for tabID: UUID) -> EditorTextView? {
        textViews[tabID]
    }

    static func cleanupRemovedTabs(activeIDs: Set<UUID>) {
        let staleKeys = Set(textViews.keys).subtracting(activeIDs)
        for key in staleKeys {
            textViews.removeValue(forKey: key)
            coordinators.removeValue(forKey: key)
            gutterViews.removeValue(forKey: key)
            scrollWrappers.removeValue(forKey: key)
        }
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // Clean up stale text views for removed tabs
        let activeIDs = Set(tabStore.tabs.map(\.id))
        Self.cleanupRemovedTabs(activeIDs: activeIDs)

        // Get or create coordinator for this tab
        let coordinator: EditorCoordinator
        if let existing = Self.coordinators[tabID] {
            coordinator = existing
        } else {
            coordinator = EditorCoordinator()
            Self.coordinators[tabID] = coordinator
        }

        // Get or create text view for this tab
        let textView: EditorTextView
        let gutterView: LineNumberGutterView
        let scrollWrapper: EditorScrollWrapper
        if let existing = Self.textViews[tabID],
           let existingGutter = Self.gutterViews[tabID],
           let existingWrapper = Self.scrollWrappers[tabID] {
            textView = existing
            gutterView = existingGutter
            scrollWrapper = existingWrapper
        } else {
            // Explicit TextKit 1 stack: the editor accesses layoutManager
            // throughout (gutter, checkbox taps, wrap control). Letting UIKit
            // lazily downgrade from TextKit 2 mid-setup leaves the content
            // size stale until the first edit – bottom content unreachable
            // under the keyboard until a key is pressed.
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            // Height must be unlimited: layout treats 0 as "no limit", but
            // UITextView's tap hit-testing (closestPosition) clamps the touch
            // point to the container size – with height 0 every tap resolves
            // to the first line. Width is managed via widthTracksTextView.
            let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = true
            layoutManager.addTextContainer(textContainer)
            textView = EditorTextView(frame: .zero, textContainer: textContainer)
            textView.ownedTextStorage = textStorage
            textView.delegate = coordinator
            coordinator.textView = textView
            Self.textViews[tabID] = textView

            let gutter = LineNumberGutterView()
            gutter.textView = textView
            coordinator.gutterView = gutter
            Self.gutterViews[tabID] = gutter
            gutterView = gutter

            let wrapper = EditorScrollWrapper()
            // Fully manually managed (updateHorizontalLayout). With .automatic,
            // UIKit applies vertical safe-area adjustment inside a Navigation-
            // Stack and shifts the wrapper's content – the whole text view –
            // a few points during sheet presentations, while the gutter
            // (outside the wrapper) stays put: line numbers visibly detach.
            wrapper.contentInsetAdjustmentBehavior = .never
            wrapper.showsHorizontalScrollIndicator = true
            wrapper.showsVerticalScrollIndicator = false
            wrapper.alwaysBounceHorizontal = false
            wrapper.alwaysBounceVertical = false
            wrapper.onBoundsChange = { [weak coordinator] in
                coordinator?.updateHorizontalLayout()
            }
            coordinator.scrollWrapper = wrapper
            Self.scrollWrappers[tabID] = wrapper
            scrollWrapper = wrapper

            // Initialize content from tab store
            if let tab = tabStore.tabs.first(where: { $0.id == tabID }) {
                textView.text = tab.content
                coordinator.language = tab.language
                let cursorPos = min(tabStore.cursorPosition(for: tab.id), (tab.content as NSString).length)
                textView.selectedRange = NSRange(location: cursorPos, length: 0)
            }

            // Wire text changes to tab store (async to avoid publishing during view updates)
            textView.onTextChange = { [weak tabStore, weak coordinator] content in
                DispatchQueue.main.async {
                    tabStore?.updateContent(id: tabID, content: content)
                    coordinator?.pendingLocalEdits -= 1
                }
            }
            // Safe to call synchronously: cursor positions live outside the
            // @Published tabs array, so this cannot publish mid-view-update
            textView.onCursorChange = { [weak tabStore] position in
                tabStore?.updateCursorPosition(id: tabID, position: position)
            }
            textView.onEdgeSwipe = { [weak tabStore] delta in
                tabStore?.selectNeighborTab(delta: delta)
            }
            for edgePan in textView.edgeGestures {
                wrapper.panGestureRecognizer.require(toFail: edgePan)
            }

            // Add tap gesture for checkbox/link handling. Target the text view
            // itself – the SwiftUI coordinator is recreated per EditorView
            // instance while the text view (and its gestures) are cached per tab.
            textView.installTapHandling()

            // Apply initial word wrap setting
            textView.wrapsLines = settings.wordWrap
            coordinator.appliedWordWrap = settings.wordWrap

            // Register for appearance changes and initial highlight
            textView.registerAppearanceTracking()
            coordinator.rehighlight()
        }

        // Only add the views if they're not already in this container
        if scrollWrapper.superview !== container {
            for subview in container.subviews {
                subview.removeFromSuperview()
            }
            gutterView.translatesAutoresizingMaskIntoConstraints = false
            scrollWrapper.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(gutterView)
            container.addSubview(scrollWrapper)

            // Text view uses frame-based layout inside the scroll wrapper
            textView.translatesAutoresizingMaskIntoConstraints = true
            scrollWrapper.addSubview(textView)

            let gutterWidthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 0)
            coordinator.gutterWidthConstraint = gutterWidthConstraint

            NSLayoutConstraint.activate([
                gutterView.topAnchor.constraint(equalTo: container.topAnchor),
                gutterView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                gutterView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                gutterWidthConstraint,

                scrollWrapper.topAnchor.constraint(equalTo: container.topAnchor),
                scrollWrapper.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                scrollWrapper.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
                scrollWrapper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])

            // Auto-focus after layout
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        // Update settings – only set textView.font when it actually changes
        // to avoid stripping attributed text on every SwiftUI update cycle
        let font = settings.editorFont
        coordinator.font = font
        if textView.font != font {
            textView.font = font
        }

        // Detect theme/appearance changes and re-apply
        if coordinator.appliedAppearance != settings.appearanceOverride
            || coordinator.appliedSyntaxTheme != settings.syntaxTheme {
            coordinator.updateTheme()
        }

        // Detect spacing changes and re-apply
        if coordinator.appliedLineSpacing != settings.lineSpacing
            || coordinator.appliedLetterSpacing != settings.letterSpacing {
            coordinator.rehighlight()
        }

        // Detect word wrap changes
        var needsLayoutUpdate = false
        if coordinator.appliedWordWrap != settings.wordWrap {
            coordinator.appliedWordWrap = settings.wordWrap
            textView.wrapsLines = settings.wordWrap
            coordinator.rehighlight()
            needsLayoutUpdate = true
        }

        // Detect line numbers changes
        let showLineNumbers = settings.showLineNumbers
        if coordinator.appliedShowLineNumbers != showLineNumbers {
            coordinator.appliedShowLineNumbers = showLineNumbers
            gutterView.showLineNumbers = showLineNumbers
            needsLayoutUpdate = true
        }

        // Update gutter appearance
        gutterView.lineFont = .monospacedDigitSystemFont(ofSize: CGFloat(settings.editorFontSize) * 0.85, weight: .regular)
        gutterView.lineColor = coordinator.theme.foreground.withAlphaComponent(0.4)
        gutterView.bgColor = coordinator.themeBackgroundColor

        // Update gutter width constraint
        if let gutterWidthConstraint = coordinator.gutterWidthConstraint {
            let lineCount = (textView.text as NSString).components(separatedBy: "\n").count
            let targetWidth: CGFloat = showLineNumbers
                ? LineNumberGutterView.calculateWidth(lineCount: lineCount, font: gutterView.lineFont)
                : 0
            if gutterWidthConstraint.constant != targetWidth {
                gutterWidthConstraint.constant = targetWidth
                needsLayoutUpdate = true
            }
        }
        gutterView.setNeedsDisplay()

        // Resolve constraint changes before sizing text view frame
        if needsLayoutUpdate {
            container.layoutIfNeeded()
        }
        coordinator.updateHorizontalLayout()

        container.backgroundColor = coordinator.themeBackgroundColor
        textView.backgroundColor = .clear
        textView.tintColor = coordinator.theme.insertionPointColor

        // Text insets
        let horizontalInset: CGFloat = showLineNumbers ? 6 : 20
        if textView.textContainerInset.left != horizontalInset {
            textView.textContainerInset.left = horizontalInset
        }
        if textView.textContainerInset.right != 20 {
            textView.textContainerInset.right = 20
        }

        // Sync language from tab store
        if let tab = tabStore.tabs.first(where: { $0.id == tabID }) {
            if coordinator.language != tab.language {
                coordinator.language = tab.language
            }

            // Handle cloud sync updates — only reset text from the tab store
            // when there are no pending local edits.  During typing,
            // onCursorChange triggers updateUIView before the async
            // onTextChange has delivered the new content, so tab.content
            // is stale and resetting would strip all attributes.
            // markedTextRange guards active IME composition (e.g. CJK input) –
            // resetting the text mid-composition destroys the marked text.
            if textView.text != tab.content && coordinator.pendingLocalEdits == 0
                && textView.markedTextRange == nil {
                // Preserve the caret across the reset – setting .text moves it
                // to the end, which yanks the user's position whenever a cloud
                // change lands mid-reading (same clamping as the macOS merge)
                let selection = textView.selectedRange
                textView.text = tab.content
                let length = (tab.content as NSString).length
                let location = min(selection.location, length)
                textView.selectedRange = NSRange(
                    location: location,
                    length: min(selection.length, length - location)
                )
                coordinator.rehighlight()
            }
        }

    }
}
