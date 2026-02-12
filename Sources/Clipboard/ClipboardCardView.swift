import SwiftUI

struct ClipboardCardView: View {
    let entry: ClipboardEntry
    let themeBackground: Color
    let themeForeground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(themeForeground)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(relativeTimestamp)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(themeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var relativeTimestamp: String {
        let now = Date()
        let interval = now.timeIntervalSince(entry.timestamp)

        if interval < 60 { return "just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m)m ago"
        }
        if interval < 86400 {
            let h = Int(interval / 3600)
            return "\(h)h ago"
        }
        if interval < 172800 { return "yesterday" }
        let d = Int(interval / 86400)
        return "\(d)d ago"
    }
}
