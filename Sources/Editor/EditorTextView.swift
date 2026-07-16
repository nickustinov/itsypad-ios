import UIKit

final class EditorTextView: UITextView {
    /// Owns the manually built TextKit 1 text storage. NSLayoutManager only
    /// references its storage unowned, so without a strong owner the storage
    /// deallocates and the view crashes on first layout.
    var ownedTextStorage: NSTextStorage?

    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((Int) -> Void)?
    var onEdgeSwipe: ((Int) -> Void)? // -1 = previous tab, +1 = next tab
    private(set) var edgeGestures: [UIScreenEdgePanGestureRecognizer] = []

    var wrapsLines: Bool = true {
        didSet {
            guard wrapsLines != oldValue else { return }
            if wrapsLines {
                textContainer.widthTracksTextView = true
                if bounds.width > 0 {
                    textContainer.size.width = bounds.width
                }
            } else {
                textContainer.widthTracksTextView = false
                textContainer.size.width = CGFloat.greatestFiniteMagnitude
            }
            layoutManager.ensureLayout(for: textContainer)
        }
    }

    var textContentWidth: CGFloat {
        let usedWidth = layoutManager.usedRect(for: textContainer).width
        return ceil(usedWidth) + textContainerInset.left + textContainerInset.right
    }

    override func layoutSubviews() {
        if !wrapsLines {
            textContainer.widthTracksTextView = false
            textContainer.size.width = CGFloat.greatestFiniteMagnitude
        }
        super.layoutSubviews()
    }

    private var listsAllowed: Bool {
        guard let coordinator = delegate as? EditorCoordinator else { return true }
        let lang = coordinator.language
        return lang == "plain" || lang == "markdown"
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        applyKeyboardTraits(forLanguage: "plain")
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        isFindInteractionEnabled = true

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeIndent(_:)))
        swipeRight.direction = .right
        addGestureRecognizer(swipeRight)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeOutdent(_:)))
        swipeLeft.direction = .left
        addGestureRecognizer(swipeLeft)

        // Edge swipes switch tabs; indent/outdent swipes and scrolling defer to them
        for edge in [UIRectEdge.left, .right] {
            let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
            edgePan.edges = edge
            addGestureRecognizer(edgePan)
            edgeGestures.append(edgePan)
            swipeRight.require(toFail: edgePan)
            swipeLeft.require(toFail: edgePan)
            panGestureRecognizer.require(toFail: edgePan)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Undo-safe programmatic edits

    /// Replace text through the UITextInput system so the edit is registered
    /// with the undo manager. Direct textStorage mutation shifts text under
    /// previously registered undo operations, making undo delete the wrong
    /// characters or crash.
    func replaceTextPreservingUndo(in range: NSRange, with string: String) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else {
            textStorage.replaceCharacters(in: range, with: string)
            return
        }
        replace(textRange, withText: string)
    }

    // MARK: - Keyboard traits

    func applyKeyboardTraits(forLanguage language: String) {
        let prose = language == "plain" || language == "markdown"
        autocapitalizationType = prose ? .sentences : .none
        autocorrectionType = prose ? .default : .no
        spellCheckingType = prose ? .default : .no
        if isFirstResponder {
            reloadInputViews()
        }
    }

    // MARK: - Foreground restore

    /// Armed when the app enters the background, consumed on the next
    /// activation. The isEditable cycle below must run ONLY after returning
    /// from the background: didBecomeActive also fires when a system alert
    /// is dismissed – notably the cross-app paste permission prompt – and
    /// cycling mid-editing-session breaks UITextInteraction's tap-to-place-
    /// caret (taps stop moving the cursor right after pasting). It must also
    /// not run during cold launch: the cycle interrupts the initial keyboard
    /// presentation – UIKit posts a keyboard-hide frame (zeroing the
    /// avoidance inset) and may skip the re-show notification when the
    /// keyboard never visually moved, leaving content stuck under the
    /// keyboard.
    private(set) var needsInteractionReset = false

    /// Internal (not private) so tests can exercise the gating directly –
    /// notification-driven tests race the host app's real lifecycle.
    @objc func appDidEnterBackground() {
        needsInteractionReset = true
    }

    @objc func appDidBecomeActive() {
        guard needsInteractionReset else { return }
        needsInteractionReset = false
        guard window != nil else { return }
        // Cycle isEditable to reset UITextInteraction gesture recognizers
        // that can get stuck after the app returns from background.
        // The cycle ends the editing session, so restore first responder –
        // otherwise the keyboard stays dismissed until the user taps around.
        let wasFirstResponder = isFirstResponder
        isEditable = false
        isEditable = true
        if wasFirstResponder {
            becomeFirstResponder()
        }
    }

    // MARK: - Keyboard avoidance

    /// Last known keyboard frame, shared across all editor text views. Cached
    /// per-tab text views are usually NOT in the window when the keyboard
    /// notification fires, so they must re-apply the overlap when they join
    /// the window (tab switch with the keyboard open) – see didMoveToWindow.
    private static var lastKeyboardFrame: CGRect = .zero

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        Self.lastKeyboardFrame = endFrame

        guard window != nil else { return }

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.applyKeyboardOverlap(endFrame)
        } completion: { _ in
            if self.contentInset.bottom > 0 {
                self.scrollRangeToVisible(self.selectedRange)
            }
        }
    }

    /// Internal (not private) so tests can exercise the geometry directly –
    /// notification-driven tests race the host app's real keyboard.
    func applyKeyboardOverlap(_ keyboardFrame: CGRect) {
        guard let window = self.window else { return }
        let viewFrame = convert(bounds, to: window)
        // Rounded with a tolerance: convert() carries float noise that would
        // otherwise read as a change and trigger redundant inset writes.
        let overlap = max(viewFrame.maxY - keyboardFrame.minY, 0).rounded()
        if abs(contentInset.bottom - overlap) >= 1 {
            contentInset.bottom = overlap
            verticalScrollIndicatorInsets.bottom = overlap
        }
    }

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        // Safe-area/inset adjustments move the text's rest position without
        // necessarily firing scrollViewDidScroll – redraw the gutter so the
        // line numbers follow
        (delegate as? EditorCoordinator)?.gutterView?.setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, Self.lastKeyboardFrame != .zero else { return }
        // Defer to the next runloop turn: at attach time this view's frames
        // are stale/zero, so the overlap must be computed after layout settles
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.applyKeyboardOverlap(Self.lastKeyboardFrame)
            if self.contentInset.bottom > 0 {
                self.scrollRangeToVisible(self.selectedRange)
            }
        }
    }

    // MARK: - Clipboard capture

    override func copy(_ sender: Any?) {
        let selected = (text as NSString).substring(with: selectedRange)
        super.copy(sender)
        ClipboardStore.shared.addEntry(text: selected)
    }

    override func cut(_ sender: Any?) {
        let selected = (text as NSString).substring(with: selectedRange)
        super.cut(sender)
        ClipboardStore.shared.addEntry(text: selected)
    }

    // MARK: - Hardware keyboard commands

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // Cmd+D — duplicate line
        commands.append(UIKeyCommand(
            action: #selector(duplicateLine),
            input: "d",
            modifierFlags: .command,
            discoverabilityTitle: "Duplicate line"
        ))

        // Cmd+Return — toggle checkbox
        if listsAllowed && SettingsStore.shared.checklistsEnabled {
            commands.append(UIKeyCommand(
                action: #selector(toggleCheckboxCommand),
                input: "\r",
                modifierFlags: .command,
                discoverabilityTitle: "Toggle checkbox"
            ))
        }

        // Cmd+Shift+L — toggle checklist
        if listsAllowed && SettingsStore.shared.checklistsEnabled {
            commands.append(UIKeyCommand(
                action: #selector(toggleChecklistCommand),
                input: "l",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: "Toggle checklist"
            ))
        }

        // Cmd+Shift+B — toggle bullet list
        if listsAllowed && SettingsStore.shared.bulletListsEnabled {
            commands.append(UIKeyCommand(
                action: #selector(toggleBulletCommand),
                input: "b",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: "Toggle bullet list"
            ))
        }

        // Cmd+Shift+N — toggle numbered list
        if listsAllowed && SettingsStore.shared.numberedListsEnabled {
            commands.append(UIKeyCommand(
                action: #selector(toggleNumberedCommand),
                input: "n",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: "Toggle numbered list"
            ))
        }

        // Shift+Tab — outdent
        commands.append(UIKeyCommand(
            action: #selector(handleShiftTab),
            input: "\t",
            modifierFlags: .shift,
            discoverabilityTitle: "Outdent"
        ))

        return commands
    }

    // MARK: - Checkbox tap detection

    /// Separate delegate object: the text view must NOT be the gesture
    /// delegate itself – UIScrollView is already the private delegate of its
    /// internal gestures, and overriding shouldRecognizeSimultaneously on the
    /// view hijacks the system's gesture arbitration (breaks tap-to-place-
    /// cursor and scrolling).
    private final class TapCoexistenceDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    private let tapDelegate = TapCoexistenceDelegate()

    func installTapHandling() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tap.delegate = tapDelegate
        addGestureRecognizer(tap)
    }

    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        _ = handleTap(at: gesture.location(in: self))
    }

    func handleTap(at point: CGPoint) -> Bool {
        if handleLinkTap(at: point) {
            return true
        }

        if listsAllowed, SettingsStore.shared.checklistsEnabled, handleCheckboxTap(at: point) {
            return true
        }

        return false
    }

    private func handleLinkTap(at point: CGPoint) -> Bool {
        guard SettingsStore.shared.clickableLinks else { return false }
        let layoutPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        let charIndex = layoutManager.characterIndex(
            for: layoutPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard charIndex < textStorage.length else { return false }

        guard let urlString = textStorage.attribute(EditorCoordinator.linkURLKey, at: charIndex, effectiveRange: nil) as? String,
              let url = URL(string: urlString) else { return false }

        UIApplication.shared.open(url)
        return true
    }

    private func handleCheckboxTap(at point: CGPoint) -> Bool {
        let layoutPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        let charIndex = layoutManager.characterIndex(
            for: layoutPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let ns = text as NSString
        guard charIndex < ns.length else { return false }

        let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineText = ns.substring(with: lineRange)
        let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        guard let match = ListHelper.parseLine(cleanLine) else { return false }
        guard match.kind == .unchecked || match.kind == .checked else { return false }

        let bracketStart = lineRange.location + match.contentStart - 4
        let bracketEnd = bracketStart + 3
        guard charIndex >= bracketStart && charIndex < bracketEnd else { return false }

        let toggled = ListHelper.toggleCheckbox(in: cleanLine)
        let replaceRange = NSRange(location: lineRange.location, length: cleanLine.utf16.count)
        replaceTextPreservingUndo(in: replaceRange, with: toggled)
        delegate?.textViewDidChange?(self)
        return true
    }

    // MARK: - Key command actions

    @objc private func duplicateLine() {
        let ns = text as NSString
        let sel = selectedRange
        let lineRange = ns.lineRange(for: sel)
        let lineText = ns.substring(with: lineRange)

        let insertAt: Int
        let insertion: String
        if lineText.hasSuffix("\n") {
            insertAt = lineRange.location + lineRange.length
            insertion = lineText
        } else {
            insertAt = lineRange.location + lineRange.length
            insertion = "\n" + lineText
        }

        replaceTextPreservingUndo(in: NSRange(location: insertAt, length: 0), with: insertion)
        selectedRange = NSRange(location: sel.location + insertion.utf16.count, length: sel.length)
        delegate?.textViewDidChange?(self)
    }

    @objc private func toggleCheckboxCommand() {
        let ns = text as NSString
        let sel = selectedRange
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = ns.substring(with: lineRange)
        let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        let toggled = ListHelper.toggleCheckbox(in: cleanLine)
        guard toggled != cleanLine else { return }

        let replaceRange = NSRange(location: lineRange.location, length: cleanLine.utf16.count)
        replaceTextPreservingUndo(in: replaceRange, with: toggled)
        let safeLoc = min(sel.location, lineRange.location + toggled.utf16.count)
        selectedRange = NSRange(location: safeLoc, length: 0)
        delegate?.textViewDidChange?(self)
    }

    @objc func toggleChecklistCommand() {
        toggleChecklist()
    }

    @objc private func toggleBulletCommand() {
        toggleBulletList()
    }

    @objc private func toggleNumberedCommand() {
        toggleNumberedList()
    }

    // MARK: - List toggle actions

    private func toggleLines(transform: @escaping (String) -> String) {
        let ns = text as NSString
        let sel = selectedRange
        let lineRange = ns.lineRange(for: sel)
        let blockText = ns.substring(with: lineRange)
        let endsWithNewline = blockText.hasSuffix("\n")

        var newLines: [String] = []
        if blockText.isEmpty {
            newLines.append(transform(""))
        } else {
            blockText.enumerateLines { line, _ in
                newLines.append(transform(line))
            }
        }

        var newText = newLines.joined(separator: "\n")
        if endsWithNewline { newText += "\n" }

        replaceTextPreservingUndo(in: lineRange, with: newText)

        if sel.length == 0, newLines.count == 1 {
            let oldLine = endsWithNewline ? String(blockText.dropLast()) : blockText
            let delta = newLines[0].utf16.count - oldLine.utf16.count
            let newCursor = max(lineRange.location, sel.location + delta)
            selectedRange = NSRange(location: min(newCursor, lineRange.location + newLines[0].utf16.count), length: 0)
        } else {
            selectedRange = NSRange(location: lineRange.location, length: newText.utf16.count - (endsWithNewline ? 1 : 0))
        }

        delegate?.textViewDidChange?(self)
    }

    func toggleChecklist() {
        guard listsAllowed, SettingsStore.shared.checklistsEnabled else { return }
        toggleLines { line in ListHelper.toggleChecklist(line: line) }
    }

    func toggleBulletList() {
        guard listsAllowed, SettingsStore.shared.bulletListsEnabled else { return }
        toggleLines { line in ListHelper.toggleBullet(line: line) }
    }

    func toggleNumberedList() {
        guard listsAllowed, SettingsStore.shared.numberedListsEnabled else { return }
        var number = 1
        toggleLines { line in
            defer { number += 1 }
            return ListHelper.toggleNumbered(line: line, number: number)
        }
    }

    @objc private func handleShiftTab() {
        guard let coordinator = delegate as? EditorCoordinator else { return }
        coordinator.outdentLines(tv: self)
    }

    // MARK: - Edge swipe tab switching

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // Require a deliberate horizontal drag to avoid accidental switches
        guard abs(gesture.translation(in: self).x) > 40 else { return }
        onEdgeSwipe?(gesture.edges == .left ? -1 : 1)
    }

    // MARK: - Swipe indent/outdent

    @objc private func handleSwipeIndent(_ gesture: UISwipeGestureRecognizer) {
        guard let coordinator = delegate as? EditorCoordinator else { return }
        coordinator.indentLines(tv: self)
    }

    @objc private func handleSwipeOutdent(_ gesture: UISwipeGestureRecognizer) {
        guard let coordinator = delegate as? EditorCoordinator else { return }
        coordinator.outdentLines(tv: self)
    }

    // MARK: - Appearance changes

    private var traitRegistration: UITraitChangeRegistration?

    func registerAppearanceTracking() {
        traitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: EditorTextView, _) in
            (self?.delegate as? EditorCoordinator)?.updateTheme()
        }
    }
}
