#if os(macOS)
import AppKit
import SwiftUI

extension TerminalSettingsView {
    func loadSystemFonts() -> [String] {
        let fontManager = NSFontManager.shared
        return fontManager.availableFontFamilies.filter { familyName in
            guard let font = NSFont(name: familyName, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()
    }

    var keyboardAccessorySection: EmptyView {
        EmptyView()
    }
}

struct CustomThemeManagerRow: View {
    let theme: TerminalTheme
    let assignment: String?
    let usePerAppearanceTheme: Bool
    let isHovered: Bool
    let isSelected: Bool
    let onApply: (CustomThemeApplyTarget) -> Void
    let onEdit: () -> Void
    let onDeleteRequest: () -> Void

    @Environment(\.controlActiveState) private var controlActiveState

    private var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    private var selectedTextColor: Color {
        Color(nsColor: .selectedTextColor)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(theme.name)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? selectedTextColor : .primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let assignment {
                PillBadge(text: assignment, color: .secondary)
            }

            if isHovered || isSelected {
                Menu {
                    applyMenuItems
                } label: {
                    Image(systemName: "paintbrush.pointed.fill")
                        .foregroundStyle(isSelected ? selectedTextColor.opacity(0.9) : .secondary)
                        .imageScale(.medium)
                }
                .menuStyle(.borderlessButton)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(isSelected ? selectedTextColor.opacity(0.9) : .secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? selectionFillColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            if usePerAppearanceTheme {
                onApply(.both)
            } else {
                onApply(.dark)
            }
        }
        .contextMenu {
            applyMenuItems
            Divider()
            Button("Edit") {
                onEdit()
            }
            Button("Delete", role: .destructive) {
                onDeleteRequest()
            }
        }
    }

    @ViewBuilder
    private var applyMenuItems: some View {
        if usePerAppearanceTheme {
            Button("Apply to Dark") {
                onApply(.dark)
            }
            Button("Apply to Light") {
                onApply(.light)
            }
            Button("Apply to Both") {
                onApply(.both)
            }
        } else {
            Button("Use Theme") {
                onApply(.dark)
            }
        }
    }
}
#endif
