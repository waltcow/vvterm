#if os(iOS)
import SwiftUI
import UIKit

struct HerdrTerminalSurface: UIViewRepresentable {
    let server: Server
    let runtime: HerdrRuntimeReference
    @Binding var state: HerdrConnectionState
    let isVisible: Bool
    let retryNonce: Int
    let networkSnapshot: HerdrNetworkSnapshot
    let appActivity: HerdrAppActivity
    let onTerminalReady: (GhosttyTerminalView) -> Void
    let onKeyboardHidden: () -> Void
    let onVoiceInput: () -> Void

    @EnvironmentObject private var ghosttyApp: Ghostty.App

    func makeCoordinator() -> HerdrTerminalCoordinator {
        HerdrTerminalCoordinator(
            server: server,
            runtime: runtime,
            initialRetryNonce: retryNonce,
            initialNetworkSnapshot: networkSnapshot,
            initialAppActivity: appActivity
        ) { state = $0 }
    }

    func makeUIView(context: Context) -> UIView {
        guard let app = ghosttyApp.app else { return UIView(frame: .zero) }

        let terminal = GhosttyTerminalView(
            frame: .zero,
            worktreePath: NSHomeDirectory(),
            ghosttyApp: app,
            appWrapper: ghosttyApp,
            paneId: "herdr-\(server.id.uuidString)",
            useCustomIO: true
        )
        terminal.onReady = { [weak terminal, weak coordinator = context.coordinator] in
            guard let terminal, let coordinator else { return }
            coordinator.bind(to: terminal)
            coordinator.setVisible(isVisible)
            onTerminalReady(terminal)
        }
        terminal.onZoomAction = { [weak coordinator = context.coordinator] action in
            coordinator?.handleZoom(action)
        }
        terminal.onKeyboardAccessoryHideRequested = onKeyboardHidden
        terminal.onVoiceButtonTapped = onVoiceInput
        return terminal
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update { state = $0 }
        context.coordinator.setVisible(isVisible)
        context.coordinator.observeRetryNonce(retryNonce)
        context.coordinator.observeNetworkSnapshot(networkSnapshot)
        context.coordinator.observeAppActivity(appActivity)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: HerdrTerminalCoordinator) {
        coordinator.stop()
        if let terminal = uiView as? GhosttyTerminalView {
            terminal.onZoomAction = nil
            terminal.onKeyboardAccessoryHideRequested = nil
            terminal.onVoiceButtonTapped = nil
            terminal.cleanup()
        }
    }
}
#endif
