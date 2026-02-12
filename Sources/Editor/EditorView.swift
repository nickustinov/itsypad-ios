import SwiftUI

struct EditorView: UIViewRepresentable {
    let tabID: UUID
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore

    // Shared per-tab text views — preserves undo, cursor, scroll position per tab
    private static var textViews: [UUID: EditorTextView] = [:]
    private static var coordinators: [UUID: EditorCoordinator] = [:]

    static func cleanupRemovedTabs(activeIDs: Set<UUID>) {
        let staleKeys = Set(textViews.keys).subtracting(activeIDs)
        for key in staleKeys {
            textViews.removeValue(forKey: key)
            coordinators.removeValue(forKey: key)
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
        if let existing = Self.textViews[tabID] {
            textView = existing
        } else {
            textView = EditorTextView()
            textView.delegate = coordinator
            coordinator.textView = textView
            Self.textViews[tabID] = textView

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

            // Register for appearance changes and initial highlight
            textView.registerAppearanceTracking()
            coordinator.rehighlight()
        }

        // Only add the text view if it's not already in this container
        if textView.superview !== container {
            for subview in container.subviews {
                subview.removeFromSuperview()
            }
            textView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: container.topAnchor),
                textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
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

        textView.backgroundColor = coordinator.themeBackgroundColor
        textView.tintColor = coordinator.theme.insertionPointColor

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
                // Tap was handled (checkbox toggle or link open)
                return
            }
            // Let the text view handle the tap normally for cursor placement
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
