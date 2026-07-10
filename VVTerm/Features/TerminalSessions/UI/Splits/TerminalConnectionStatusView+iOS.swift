#if os(iOS)
import SwiftUI

struct TerminalConnectionStatusView: View {
    let presentation: TerminalConnectionStatusPresentation
    let surfaceStyle: NoticeSurfaceStyle
    let isActive: Bool
    let onRetry: () -> Void
    let onTrustNewHostKey: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .sheet(isPresented: isPresented) {
                sheetContent
                    .presentationDetents([.height(sheetHeight)])
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: {
                guard isActive else { return false }
                if case .hidden = presentation { return false }
                return true
            },
            set: { _ in }
        )
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .connecting(let serverName):
            statusSheet(
                level: .info,
                leading: .activity,
                title: String(
                    format: String(localized: "Connecting to %@..."),
                    serverName
                )
            )
        case .disconnected(let message):
            statusSheet(
                level: .warning,
                leading: .icon("bolt.slash.fill"),
                title: String(localized: "Disconnected"),
                message: message,
                primaryAction: NoticeAction(
                    id: "reconnect",
                    title: String(localized: "Reconnect"),
                    handler: onRetry
                )
            )
        case .failed(let message, let allowsHostKeyReplacement):
            statusSheet(
                level: .error,
                leading: .icon("exclamationmark.triangle.fill"),
                title: String(localized: "Connection Failed"),
                message: message,
                primaryAction: NoticeAction(
                    id: "retry",
                    title: String(localized: "Retry"),
                    handler: onRetry
                ),
                secondaryAction: allowsHostKeyReplacement
                    ? NoticeAction(
                        id: "trust-new-host-key",
                        title: String(localized: "Trust New Host Key"),
                        handler: onTrustNewHostKey
                    )
                    : nil
            )
        }
    }

    private func statusSheet(
        level: NoticeLevel,
        leading: NoticeLeading,
        title: String,
        message: String? = nil,
        primaryAction: NoticeAction? = nil,
        secondaryAction: NoticeAction? = nil
    ) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(level.tintColor.opacity(0.14))

                sheetLeadingView(leading, level: level)
            }
            .frame(width: 52, height: 52)

            VStack(spacing: 7) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)

            if primaryAction != nil || secondaryAction != nil {
                VStack(spacing: 10) {
                    if let primaryAction {
                        nativeSheetButton(primaryAction, isPrimary: true)
                    }

                    if let secondaryAction {
                        nativeSheetButton(secondaryAction, isPrimary: false)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func sheetLeadingView(_ leading: NoticeLeading, level: NoticeLevel) -> some View {
        switch leading {
        case .none:
            EmptyView()
        case .activity:
            ProgressView()
                .controlSize(.large)
                .tint(level.tintColor)
        case .icon(let systemName):
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(level.tintColor)
        }
    }

    @ViewBuilder
    private func nativeSheetButton(_ action: NoticeAction, isPrimary: Bool) -> some View {
        let button = Button(role: action.role, action: action.handler) {
            Text(action.title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .controlSize(.large)

        if isPrimary {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var sheetHeight: CGFloat {
        switch presentation {
        case .hidden:
            return 1
        case .connecting:
            return 170
        case .disconnected(let message):
            return message == nil ? 248 : 280
        case .failed(_, let allowsHostKeyReplacement):
            return allowsHostKeyReplacement ? 360 : 300
        }
    }
}
#endif
