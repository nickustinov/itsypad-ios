import UIKit

class EditorCoordinator: NSObject, UITextViewDelegate {
    weak var textView: EditorTextView?
    var language: String = "plain" {
        didSet {
            if language != oldValue { scheduleHighlightIfNeeded() }
        }
    }
    var font: UIFont = .monospacedSystemFont(ofSize: 16, weight: .regular)

    private static let highlightJS = HighlightJS.shared
    private static let highlightQueue = DispatchQueue(label: "Itsypad.SyntaxHighlight", qos: .userInitiated)

    private(set) var theme: EditorTheme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
    private(set) var themeBackgroundColor: UIColor = EditorTheme.current(for: SettingsStore.shared.appearanceOverride).background
    private(set) var themeIsDark: Bool = EditorTheme.current(for: SettingsStore.shared.appearanceOverride).isDark

    private var pendingHighlight: DispatchWorkItem?
    private var lastHighlightedText: String = ""
    private var lastLanguage: String?
    private var lastAppearance: String?

    // Track which settings were last applied so updateUIView can detect changes
    private(set) var appliedAppearance: String = ""
    private(set) var appliedSyntaxTheme: String = ""
    private(set) var appliedLineSpacing: Double = 1.0
    private(set) var appliedLetterSpacing: Double = 0.0
    var appliedWordWrap: Bool = true
    var appliedShowLineNumbers: Bool = false
    weak var gutterView: LineNumberGutterView?
    weak var scrollWrapper: UIScrollView? // EditorScrollWrapper
    var gutterWidthConstraint: NSLayoutConstraint?

    // Custom attribute key for clickable link URLs
    static let linkURLKey = NSAttributedString.Key("ItsypadLinkURL")

    // Pre-compiled regex patterns
    private static let urlRegex = try! NSRegularExpression(
        pattern: "https?://\\S+", options: []
    )
    private static let bulletMarkerRegex = try! NSRegularExpression(
        pattern: "^[ \\t]*[-*](?= )", options: .anchorsMatchLines
    )
    private static let orderedMarkerRegex = try! NSRegularExpression(
        pattern: "^[ \\t]*\\d+\\.(?= )", options: .anchorsMatchLines
    )
    private static let checkboxRegex = try! NSRegularExpression(
        pattern: "^([ \\t]*[-*] )(\\[[ x]\\])( )(.*)",
        options: .anchorsMatchLines
    )

    override init() {
        super.init()
        applyTheme()
    }

    /// Updates the text view frame and scroll wrapper content size for horizontal scrolling.
    func updateHorizontalLayout() {
        guard let tv = textView, let wrapper = scrollWrapper else { return }
        let wrapperWidth = wrapper.bounds.width
        guard wrapperWidth > 0 else { return }

        let wrapperHeight = wrapper.bounds.height
        if tv.wrapsLines {
            if tv.frame.size != CGSize(width: wrapperWidth, height: wrapperHeight) {
                tv.frame = CGRect(x: 0, y: 0, width: wrapperWidth, height: wrapperHeight)
            }
            wrapper.contentSize = CGSize(width: wrapperWidth, height: wrapperHeight)
        } else {
            let contentWidth = max(tv.textContentWidth, wrapperWidth)
            if tv.frame.size != CGSize(width: contentWidth, height: wrapperHeight) {
                tv.frame = CGRect(x: 0, y: 0, width: contentWidth, height: wrapperHeight)
            }
            wrapper.contentSize = CGSize(width: contentWidth, height: wrapperHeight)
        }
    }

    private func scrollWrapperToCaret() {
        guard let tv = textView, !tv.wrapsLines,
              let wrapper = scrollWrapper,
              let pos = tv.selectedTextRange?.start else { return }
        let caretRect = tv.caretRect(for: pos)
        let rectInWrapper = tv.convert(caretRect, to: wrapper).insetBy(dx: -20, dy: 0)
        wrapper.scrollRectToVisible(rectInWrapper, animated: false)
    }

    func updateTheme() {
        theme = EditorTheme.current(for: SettingsStore.shared.appearanceOverride)
        applyTheme()

        if let tv = textView {
            tv.superview?.backgroundColor = themeBackgroundColor
            tv.backgroundColor = .clear
            tv.tintColor = theme.insertionPointColor

            let storage = tv.textStorage
            let len = storage.length
            if len > 0 {
                let fullRange = NSRange(location: 0, length: len)
                storage.beginEditing()
                storage.removeAttribute(.backgroundColor, range: fullRange)
                storage.addAttribute(.foregroundColor, value: theme.foreground, range: fullRange)
                storage.endEditing()
            }
        }

        lastAppearance = nil
        rehighlight()
    }

    private func applyTheme() {
        let isDark = theme.isDark
        let themeId = SettingsStore.shared.syntaxTheme
        appliedAppearance = SettingsStore.shared.appearanceOverride
        appliedSyntaxTheme = themeId
        let themeName = SyntaxThemeRegistry.cssResource(for: themeId, isDark: isDark)
        let currentFont = font

        Self.highlightQueue.sync {
            _ = Self.highlightJS.loadTheme(named: themeName)
            Self.highlightJS.setCodeFont(currentFont)
        }

        themeBackgroundColor = Self.highlightJS.backgroundColor

        // Detect actual theme darkness from background luminance
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        themeBackgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        themeIsDark = luminance < 0.5

        theme = EditorTheme(
            isDark: themeIsDark,
            background: themeBackgroundColor,
            foreground: Self.highlightJS.foregroundColor
        )
    }

    func scheduleHighlightIfNeeded(text: String? = nil) {
        guard let tv = textView else { return }
        let text = text ?? tv.text ?? ""
        let lang = language
        let appearance = SettingsStore.shared.appearanceOverride

        if (text as NSString).length > 200_000 {
            lastHighlightedText = text
            lastLanguage = lang
            lastAppearance = appearance
            return
        }

        if text == lastHighlightedText && lastLanguage == lang
            && lastAppearance == appearance {
            return
        }

        rehighlight()
    }

    func rehighlight() {
        guard let tv = textView else { return }
        let textSnapshot = tv.text ?? ""
        let userFont = font
        let currentTheme = theme
        let hlLang = LanguageDetector.shared.highlightrLanguage(for: language)

        pendingHighlight?.cancel()

        guard let hlLang else {
            applyPlainText(tv: tv, text: textSnapshot, font: userFont, theme: currentTheme)
            return
        }

        let highlightJS = Self.highlightJS

        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            guard let self, !work.isCancelled else { return }
            highlightJS.setCodeFont(userFont)
            let highlighted = highlightJS.highlight(textSnapshot, as: hlLang)

            DispatchQueue.main.async { [weak self] in
                guard let self, !work.isCancelled, let tv = self.textView else { return }
                guard tv.text == textSnapshot else { return }

                let ns = textSnapshot as NSString
                let fullRange = NSRange(location: 0, length: ns.length)
                let sel = tv.selectedRange

                tv.textStorage.beginEditing()

                if let highlighted {
                    // Apply attributes per-range directly from the highlighted
                    // string, avoiding a full-range reset that flashes gray.
                    highlighted.enumerateAttributes(
                        in: NSRange(location: 0, length: highlighted.length),
                        options: []
                    ) { attrs, range, _ in
                        var merged = attrs
                        if merged[.font] == nil { merged[.font] = userFont }
                        if merged[.foregroundColor] == nil { merged[.foregroundColor] = currentTheme.foreground }
                        tv.textStorage.setAttributes(merged, range: range)
                    }
                } else {
                    tv.textStorage.setAttributes([
                        .font: userFont,
                        .foregroundColor: currentTheme.foreground,
                    ], range: fullRange)
                }

                self.applySpacing(tv: tv, text: textSnapshot, font: userFont)
                self.applyListMarkers(tv: tv, text: textSnapshot, theme: currentTheme)
                self.applyLinkHighlighting(tv: tv, text: textSnapshot, theme: currentTheme)

                tv.textStorage.endEditing()

                let safeLocation = min(sel.location, ns.length)
                let safeLength = min(sel.length, ns.length - safeLocation)
                tv.selectedRange = NSRange(location: safeLocation, length: safeLength)

                self.lastHighlightedText = textSnapshot
                self.lastLanguage = self.language
                self.lastAppearance = SettingsStore.shared.appearanceOverride
                self.gutterView?.setNeedsDisplay()
            }
        }

        pendingHighlight = work
        Self.highlightQueue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func applyPlainText(tv: EditorTextView, text: String, font: UIFont, theme: EditorTheme) {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let sel = tv.selectedRange

        tv.textStorage.beginEditing()
        tv.textStorage.setAttributes([
            .font: font,
            .foregroundColor: theme.foreground,
        ], range: fullRange)

        applySpacing(tv: tv, text: text, font: font)
        applyListMarkers(tv: tv, text: text, theme: theme)
        applyLinkHighlighting(tv: tv, text: text, theme: theme)

        tv.textStorage.endEditing()

        let safeLocation = min(sel.location, ns.length)
        let safeLength = min(sel.length, ns.length - safeLocation)
        tv.selectedRange = NSRange(location: safeLocation, length: safeLength)

        lastHighlightedText = text
        lastLanguage = language
        lastAppearance = SettingsStore.shared.appearanceOverride
        gutterView?.setNeedsDisplay()
    }

    private func applyListMarkers(tv: EditorTextView, text: String, theme: EditorTheme) {
        guard language == "plain" || language == "markdown" else { return }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let dashColor = theme.bulletDashColor
        let checkboxColor = theme.checkboxColor

        let store = SettingsStore.shared

        if store.bulletListsEnabled {
            for match in Self.bulletMarkerRegex.matches(in: text, range: fullRange) {
                let r = match.range
                let markerRange = NSRange(location: r.location + r.length - 1, length: 1)
                tv.textStorage.addAttribute(.foregroundColor, value: dashColor, range: markerRange)
            }
        }

        if store.numberedListsEnabled {
            for match in Self.orderedMarkerRegex.matches(in: text, range: fullRange) {
                let r = match.range
                tv.textStorage.addAttribute(.foregroundColor, value: dashColor, range: r)
            }
        }

        guard store.checklistsEnabled else { return }
        for match in Self.checkboxRegex.matches(in: text, range: fullRange) {
            let bracketRange = match.range(at: 2)
            tv.textStorage.addAttribute(.foregroundColor, value: checkboxColor, range: bracketRange)

            let bracketText = ns.substring(with: bracketRange)
            if bracketText == "[x]" {
                let lineRange = match.range
                tv.textStorage.addAttribute(.foregroundColor, value: theme.foreground.withAlphaComponent(0.4), range: lineRange)
                tv.textStorage.addAttribute(.foregroundColor, value: checkboxColor.withAlphaComponent(0.4), range: bracketRange)
                let contentRange = match.range(at: 4)
                if contentRange.length > 0 {
                    tv.textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    tv.textStorage.addAttribute(.strikethroughColor, value: theme.foreground.withAlphaComponent(0.4), range: contentRange)
                }
            }
        }
    }

    private func applySpacing(tv: EditorTextView, text: String, font: UIFont) {
        let store = SettingsStore.shared
        let ns = text as NSString
        let totalLength = ns.length
        guard totalLength > 0 else { return }

        let kern = store.letterSpacing
        if kern != 0 {
            tv.textStorage.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: totalLength))
        }

        let lineSpacingMultiplier = store.lineSpacing
        let naturalLineHeight = ceil(font.ascender - font.descender + font.leading)
        let extraLineSpacing = (lineSpacingMultiplier - 1.0) * naturalLineHeight

        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let tabPixelWidth = spaceWidth * CGFloat(store.tabWidth)
        let listsAllowed = language == "plain" || language == "markdown"

        var pos = 0
        while pos < totalLength {
            let lineRange = ns.lineRange(for: NSRange(location: pos, length: 0))
            let lineText = ns.substring(with: lineRange)

            // Calculate leading whitespace width
            var indent: CGFloat = 0
            var i = lineRange.location
            let lineEnd = lineRange.location + lineRange.length
            while i < lineEnd {
                let ch = ns.character(at: i)
                if ch == 0x20 { indent += spaceWidth }
                else if ch == 0x09 { indent += tabPixelWidth }
                else { break }
                i += 1
            }

            // For list lines, indent wrapped text to content start (past the prefix)
            var headIndent = indent
            let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            if listsAllowed,
               let match = ListHelper.parseLine(cleanLine), ListHelper.isKindEnabled(match.kind) {
                headIndent = CGFloat(match.contentStart) * spaceWidth
            }

            let para = NSMutableParagraphStyle()
            para.headIndent = headIndent
            if extraLineSpacing > 0 {
                para.lineSpacing = extraLineSpacing
            }
            tv.textStorage.addAttribute(.paragraphStyle, value: para, range: lineRange)

            pos = lineRange.location + lineRange.length
        }

        appliedLineSpacing = lineSpacingMultiplier
        appliedLetterSpacing = kern
    }

    private func applyLinkHighlighting(tv: EditorTextView, text: String, theme: EditorTheme) {
        guard SettingsStore.shared.clickableLinks else { return }
        guard language == "plain" || language == "markdown" else { return }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let linkColor = theme.linkColor

        for match in Self.urlRegex.matches(in: text, range: fullRange) {
            let r = match.range
            tv.textStorage.addAttribute(.foregroundColor, value: linkColor, range: r)
            tv.textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            tv.textStorage.addAttribute(.underlineColor, value: linkColor, range: r)
            let urlString = ns.substring(with: r)
            tv.textStorage.addAttribute(Self.linkURLKey, value: urlString, range: r)
        }
    }

    // MARK: - UITextViewDelegate / UIScrollViewDelegate

    /// Incremented on each local edit, decremented after the async content
    /// update is delivered to the tab store.  While > 0, `updateUIView`
    /// must not reset `textView.text` from the (stale) tab-store content.
    var pendingLocalEdits = 0

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard let tv = textView as? EditorTextView else { return }
        tv.onCursorChange?(tv.selectedRange.location)
        scrollWrapperToCaret()

        // Scroll vertically to keep cursor above keyboard
        if tv.contentInset.bottom > 0 {
            tv.scrollRangeToVisible(tv.selectedRange)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let tv = textView as? EditorTextView else { return }
        let text = tv.text ?? ""
        pendingLocalEdits += 1
        tv.onTextChange?(text)
        scheduleHighlightIfNeeded(text: text)
        updateHorizontalLayout()
        gutterView?.setNeedsDisplay()
        scrollWrapperToCaret()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        gutterView?.setNeedsDisplay()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let tv = textView as? EditorTextView else { return true }
        let ns = (tv.text ?? "") as NSString

        // Newline — list continuation + auto-indent
        if text == "\n" {
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let currentLine = ns.substring(with: NSRange(
                location: lineRange.location,
                length: max(0, range.location - lineRange.location)
            ))

            let listsAllowed = language == "plain" || language == "markdown"
            if listsAllowed, let match = ListHelper.parseLine(currentLine), ListHelper.isKindEnabled(match.kind) {
                if ListHelper.isEmptyItem(currentLine, match: match) {
                    let prefixRange = NSRange(location: lineRange.location, length: currentLine.count)
                    tv.textStorage.replaceCharacters(in: prefixRange, with: "")
                    tv.selectedRange = NSRange(location: lineRange.location, length: 0)
                    self.textViewDidChange(tv)
                    return false
                } else {
                    let next = ListHelper.nextPrefix(for: match)
                    tv.textStorage.replaceCharacters(in: range, with: "\n" + next)
                    tv.selectedRange = NSRange(location: range.location + 1 + next.count, length: 0)
                    self.textViewDidChange(tv)
                    return false
                }
            }

            // Auto-indent
            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            if !indent.isEmpty {
                tv.textStorage.replaceCharacters(in: range, with: "\n" + indent)
                tv.selectedRange = NSRange(location: range.location + 1 + indent.count, length: 0)
                self.textViewDidChange(tv)
                return false
            }

            return true
        }

        // Tab key (hardware keyboard)
        if text == "\t" {
            let sel = tv.selectedRange
            if sel.length > 0 {
                indentSelectedLines(tv: tv)
                return false
            }

            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let lineText = ns.substring(with: lineRange)
            let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            let listsAllowed = language == "plain" || language == "markdown"

            if listsAllowed, let listMatch = ListHelper.parseLine(cleanLine), ListHelper.isKindEnabled(listMatch.kind) {
                let indent = SettingsStore.shared.indentString
                if case .ordered(let n) = listMatch.kind, n != 1 {
                    let numStr = "\(n)"
                    let prefixLen = listMatch.indent.count + numStr.count
                    let replaceRange = NSRange(location: lineRange.location, length: prefixLen)
                    let replacement = listMatch.indent + indent + "1"
                    tv.textStorage.replaceCharacters(in: replaceRange, with: replacement)
                    tv.selectedRange = NSRange(location: sel.location + replacement.count - prefixLen, length: 0)
                } else {
                    let insertRange = NSRange(location: lineRange.location, length: 0)
                    tv.textStorage.replaceCharacters(in: insertRange, with: indent)
                    tv.selectedRange = NSRange(location: sel.location + indent.count, length: 0)
                }
                self.textViewDidChange(tv)
                return false
            }

            let store = SettingsStore.shared
            if store.indentUsingSpaces {
                let spaces = String(repeating: " ", count: store.tabWidth)
                tv.textStorage.replaceCharacters(in: range, with: spaces)
                tv.selectedRange = NSRange(location: range.location + spaces.count, length: 0)
                self.textViewDidChange(tv)
                return false
            }

            return true
        }

        // Backspace at list prefix boundary
        if text.isEmpty && range.length == 1 {
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let columnOffset = range.location - lineRange.location
            let lineText = ns.substring(with: lineRange)
            let cleanLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            let listsAllowed = language == "plain" || language == "markdown"

            if listsAllowed, let match = ListHelper.parseLine(cleanLine), ListHelper.isKindEnabled(match.kind),
               columnOffset == match.contentStart {
                let prefixRange = NSRange(location: lineRange.location, length: match.contentStart)
                tv.textStorage.replaceCharacters(in: prefixRange, with: match.indent)
                tv.selectedRange = NSRange(location: lineRange.location + match.indent.count, length: 0)
                self.textViewDidChange(tv)
                return false
            }
        }

        return true
    }

    private func indentSelectedLines(tv: EditorTextView) {
        let indent = SettingsStore.shared.indentString
        let ns = (tv.text ?? "") as NSString
        let sel = tv.selectedRange
        let lineRange = ns.lineRange(for: sel)

        var newText = ""
        ns.substring(with: lineRange).enumerateLines { line, _ in
            newText += indent + line + "\n"
        }
        if lineRange.location + lineRange.length <= ns.length,
           !ns.substring(with: lineRange).hasSuffix("\n") {
            newText = String(newText.dropLast())
        }

        tv.textStorage.replaceCharacters(in: lineRange, with: newText)
        tv.selectedRange = NSRange(location: lineRange.location, length: newText.count)
        self.textViewDidChange(tv)
    }

    func indentLines(tv: EditorTextView) {
        let indent = SettingsStore.shared.indentString
        let ns = (tv.text ?? "") as NSString
        let sel = tv.selectedRange
        let lineRange = ns.lineRange(for: sel)

        var newText = ""
        ns.substring(with: lineRange).enumerateLines { line, _ in
            newText += indent + line + "\n"
        }
        if lineRange.location + lineRange.length <= ns.length,
           !ns.substring(with: lineRange).hasSuffix("\n") {
            newText = String(newText.dropLast())
        }

        tv.textStorage.replaceCharacters(in: lineRange, with: newText)
        if sel.length > 0 {
            tv.selectedRange = NSRange(location: lineRange.location, length: newText.count)
        } else {
            tv.selectedRange = NSRange(location: sel.location + indent.count, length: 0)
        }
        self.textViewDidChange(tv)
    }

    func outdentLines(tv: EditorTextView) {
        let store = SettingsStore.shared
        let ns = (tv.text ?? "") as NSString
        let sel = tv.selectedRange
        let lineRange = ns.lineRange(for: sel)
        let blockText = ns.substring(with: lineRange)
        let endsWithNewline = blockText.hasSuffix("\n")

        var newLines: [String] = []
        var totalRemoved = 0
        var firstLineRemoved = 0
        var isFirstLine = true

        blockText.enumerateLines { line, _ in
            var stripped = line
            if store.indentUsingSpaces {
                var count = 0
                for ch in line {
                    if ch == " " && count < store.tabWidth { count += 1 } else { break }
                }
                stripped = String(line.dropFirst(count))
                if isFirstLine { firstLineRemoved = count }
                totalRemoved += count
            } else {
                if line.hasPrefix("\t") {
                    stripped = String(line.dropFirst())
                    if isFirstLine { firstLineRemoved = 1 }
                    totalRemoved += 1
                }
            }
            newLines.append(stripped)
            isFirstLine = false
        }

        var newText = newLines.joined(separator: "\n")
        if endsWithNewline { newText += "\n" }

        tv.textStorage.replaceCharacters(in: lineRange, with: newText)
        if sel.length > 0 {
            tv.selectedRange = NSRange(location: lineRange.location, length: newText.count - (endsWithNewline ? 1 : 0))
        } else {
            let newLoc = max(lineRange.location, sel.location - firstLineRemoved)
            tv.selectedRange = NSRange(location: newLoc, length: 0)
        }
        self.textViewDidChange(tv)
    }
}
