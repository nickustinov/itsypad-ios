import UIKit

final class LineNumberGutterView: UIView {
    weak var textView: EditorTextView?

    var showLineNumbers: Bool = false {
        didSet { setNeedsDisplay() }
    }

    var lineFont: UIFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular) {
        didSet { setNeedsDisplay() }
    }

    var lineColor: UIColor = .secondaryLabel {
        didSet { setNeedsDisplay() }
    }

    var bgColor: UIColor = .clear {
        didSet { setNeedsDisplay() }
    }

    static func calculateWidth(lineCount: Int, font: UIFont) -> CGFloat {
        let digits = max(String(lineCount).count, 2)
        let sampleString = String(repeating: "8", count: digits) as NSString
        let size = sampleString.size(withAttributes: [.font: font])
        return ceil(size.width) + 16 // 8pt padding on each side
    }

    override func draw(_ rect: CGRect) {
        guard showLineNumbers, let tv = textView else { return }

        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(bgColor.cgColor)
        ctx?.fill(rect)

        let layoutManager = tv.layoutManager
        let textContainer = tv.textContainer
        let textStorage = tv.textStorage
        let text = textStorage.string as NSString

        // Visible rect in text view coordinates
        let visibleRect = CGRect(
            x: tv.contentOffset.x,
            y: tv.contentOffset.y,
            width: tv.bounds.width,
            height: tv.bounds.height
        )

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )

        guard visibleCharRange.location != NSNotFound else { return }

        // Count lines before the visible range to find the starting number.
        // lineRange(for:) walks per line without bridging the whole prefix to
        // a Swift String, and counts \r / \r\n / U+2028 the same way the
        // fragment enumeration below does.
        // ponytail: O(text above viewport) per draw – cache line starts if
        // scrolling huge documents ever measures slow.
        var lineNumber = 1
        var scanIndex = 0
        while scanIndex < visibleCharRange.location {
            scanIndex = NSMaxRange(text.lineRange(for: NSRange(location: scanIndex, length: 0)))
            if scanIndex <= visibleCharRange.location { lineNumber += 1 }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor,
        ]

        let gutterWidth = bounds.width

        // Enumerate line fragments in visible range
        var lastParaLocation = -1
        layoutManager.enumerateLineFragments(
            forGlyphRange: visibleGlyphRange
        ) { fragmentRect, _, _, glyphRange, _ in
            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let paraRange = text.paragraphRange(for: NSRange(location: charRange.location, length: 0))

            // Only draw the number for the first fragment of each paragraph
            if paraRange.location != lastParaLocation {
                lastParaLocation = paraRange.location

                let numberString = "\(lineNumber)" as NSString
                let size = numberString.size(withAttributes: attrs)

                // Let UIKit map text-content coordinates into gutter
                // coordinates. Manual "- contentOffset" arithmetic silently
                // assumes the two views share an origin and drifts whenever
                // adjusted insets or intermediate views shift the text view.
                let yInTextView = fragmentRect.origin.y + tv.textContainerInset.top
                let y = tv.convert(CGPoint(x: 0, y: yInTextView), to: self).y
                let x = gutterWidth - size.width - 8

                // Align to text baseline using the editor font
                let editorAscender = tv.font?.ascender ?? fragmentRect.height
                let gutterAscender = self.lineFont.ascender
                let baselineY = y + editorAscender - gutterAscender

                numberString.draw(
                    at: CGPoint(x: x, y: baselineY),
                    withAttributes: attrs
                )
                lineNumber += 1
            }
        }

        // Handle trailing empty line after final newline
        let totalLength = text.length
        if totalLength > 0 && text.character(at: totalLength - 1) == 0x0A {
            let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: totalLength - 1)
            let lastFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: lastGlyphIndex,
                effectiveRange: nil
            )
            let extraLineY = tv.convert(
                CGPoint(x: 0, y: lastFragmentRect.maxY + tv.textContainerInset.top),
                to: self
            ).y

            if extraLineY < bounds.height {
                let numberString = "\(lineNumber)" as NSString
                let size = numberString.size(withAttributes: attrs)
                let x = gutterWidth - size.width - 8
                let editorAscender = tv.font?.ascender ?? lineFont.ascender
                let gutterAscender = lineFont.ascender
                numberString.draw(
                    at: CGPoint(x: x, y: extraLineY + editorAscender - gutterAscender),
                    withAttributes: attrs
                )
            }
        }
    }
}
