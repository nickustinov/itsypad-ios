import SwiftUI

struct TabCardView: View {
    let tab: TabData
    let isSelected: Bool
    let themeBackground: Color
    let themeForeground: Color
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(tab.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)

                if tab.hasUnsavedChanges {
                    Circle()
                        .fill(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 6, height: 6)
                }

                Spacer(minLength: 20)
            }

            Text(previewText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(themeForeground.opacity(0.7))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(themeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(6)
            }
        }
    }

    private var previewText: String {
        let lines = tab.content.components(separatedBy: .newlines)
        return lines.prefix(4).joined(separator: "\n")
    }
}
