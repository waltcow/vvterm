#if os(iOS)
import SwiftUI

struct TerminalFloatingInputControls: View {
    let showsVoiceButton: Bool
    let showsReturnButton: Bool
    let onKeyboard: () -> Void
    let onVoice: () -> Void
    let onReturn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                controlButton(
                    title: "Keyboard",
                    systemImage: "keyboard",
                    accessibilityLabel: "Show Keyboard",
                    accessibilityIdentifier: "vvterm.floating.keyboard",
                    showsTitle: true,
                    action: onKeyboard
                )
                if showsVoiceButton {
                    controlButton(
                        title: "Voice input",
                        systemImage: "mic.fill",
                        accessibilityLabel: "Voice input",
                        accessibilityIdentifier: "vvterm.floating.voice",
                        showsTitle: true,
                        action: onVoice
                    )
                }
            }
            .layoutPriority(1)

            if showsReturnButton {
                Spacer(minLength: 14)
                controlButton(
                    title: "Enter",
                    systemImage: "arrow.turn.down.left",
                    accessibilityLabel: "Enter",
                    accessibilityIdentifier: "vvterm.floating.return",
                    showsTitle: false,
                    isPrimary: true,
                    action: onReturn
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: showsReturnButton ? .infinity : nil)
    }

    private func controlButton(
        title: LocalizedStringKey,
        systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        accessibilityIdentifier: String,
        showsTitle: Bool,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: showsTitle ? 6 : 0) {
                Image(systemName: systemImage)
                if showsTitle {
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isPrimary ? Color.accentColor : Color.primary)
            .padding(.horizontal, showsTitle ? 2 : 0)
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(
            TerminalFloatingInputControlButtonStyle(
                isPrimary: isPrimary,
                colorScheme: colorScheme
            )
        )
    }
}

private struct TerminalFloatingInputControlButtonStyle: ViewModifier {
    let isPrimary: Bool
    let colorScheme: ColorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isPrimary {
                content
                    .tint(Color.accentColor)
                    .buttonStyle(SwiftUI.GlassButtonStyle())
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            } else {
                content
                    .buttonStyle(SwiftUI.GlassButtonStyle())
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        } else {
            content
                .buttonStyle(
                    .glass(
                        tint: Color.accentColor.opacity(
                            isPrimary ? 0.5 : (colorScheme == .dark ? 0.24 : 0.14)
                        )
                    )
                )
        }
    }
}
#endif
