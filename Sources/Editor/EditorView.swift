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

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
            textView = EditorTextView()
            textView.delegate = coordinator
            coordinator.textView = textView
            Self.textViews[tabID] = textView

            let gutter = LineNumberGutterView()
            gutter.textView = textView
            coordinator.gutterView = gutter
            Self.gutterViews[tabID] = gutter
            gutterView = gutter

            let wrapper = EditorScrollWrapper()
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
                let cursorPos = min(tab.cursorPosition, (tab.content as NSString).length)
                textView.selectedRange = NSRange(location: cursorPos, length: 0)
            }

            // Wire text changes to tab store (async to avoid publishing during view updates)
            textView.onTextChange = { [weak tabStore, weak coordinator] content in
                DispatchQueue.main.async {
                    tabStore?.updateContent(id: tabID, content: content)
                    coordinator?.pendingLocalEdits -= 1
                }
            }
            textView.onCursorChange = { [weak tabStore] position in
                tabStore?.updateCursorPosition(id: tabID, position: position)
            }

            // Add tap gesture for checkbox/link handling
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tapGesture.delegate = context.coordinator
            textView.addGestureRecognizer(tapGesture)

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
            if textView.text != tab.content && coordinator.pendingLocalEdits == 0 {
                textView.text = tab.content
                coordinator.rehighlight()
            }
        }

        // Store cursor reference
        context.coordinator.textView = textView
        context.coordinator.tabID = tabID
        context.coordinator.tabStore = tabStore
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var textView: EditorTextView?
        var tabID: UUID?
        weak var tabStore: TabStore?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let tv = textView else { return }
            let point = gesture.location(in: tv)
            if tv.handleTap(at: point) {
                return
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
