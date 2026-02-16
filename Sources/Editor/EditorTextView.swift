import UIKit

final class EditorTextView: UITextView {
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((Int) -> Void)?

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
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Keyboard avoidance

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let window = self.window,
              let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let viewFrame = convert(bounds, to: window)
        let overlap = max(viewFrame.maxY - endFrame.minY, 0)

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.contentInset.bottom = overlap
            self.verticalScrollIndicatorInsets.bottom = overlap
        } completion: { _ in
            if overlap > 0 {
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
        let replaceRange = NSRange(location: lineRange.location, length: cleanLine.count)
        textStorage.replaceCharacters(in: replaceRange, with: toggled)
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

        textStorage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: insertion)
        selectedRange = NSRange(location: sel.location + insertion.count, length: sel.length)
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

        let replaceRange = NSRange(location: lineRange.location, length: cleanLine.count)
        textStorage.replaceCharacters(in: replaceRange, with: toggled)
        let safeLoc = min(sel.location, lineRange.location + toggled.count)
        selectedRange = NSRange(location: safeLoc, length: 0)
        delegate?.textViewDidChange?(self)
    }

    @objc private func toggleChecklistCommand() {
        guard listsAllowed, SettingsStore.shared.checklistsEnabled else { return }
        let ns = text as NSString
        let sel = selectedRange
        let lineRange = ns.lineRange(for: sel)

        var newLines: [String] = []
        let blockText = ns.substring(with: lineRange)
        blockText.enumerateLines { line, _ in
            newLines.append(ListHelper.toggleChecklist(line: line))
        }

        var newText = newLines.joined(separator: "\n")
        if blockText.hasSuffix("\n") { newText += "\n" }

        textStorage.replaceCharacters(in: lineRange, with: newText)
        selectedRange = NSRange(location: lineRange.location, length: newText.count - (blockText.hasSuffix("\n") ? 1 : 0))
        delegate?.textViewDidChange?(self)
    }

    @objc private func handleShiftTab() {
        guard let coordinator = delegate as? EditorCoordinator else { return }
        coordinator.outdentLines(tv: self)
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
