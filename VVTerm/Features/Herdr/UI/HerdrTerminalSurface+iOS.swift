#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class HerdrTerminalSurfaceCoordinator {
    let terminal: HerdrTerminalCoordinator
    let volumeButtons: HerdrVolumeButtonScrollMonitor

    init(
        server: Server,
        runtime: HerdrRuntimeReference,
        initialRetryNonce: Int,
        initialNetworkSnapshot: HerdrNetworkSnapshot,
        initialAppActivity: HerdrAppActivity,
        onStateChange: @escaping (HerdrConnectionState) -> Void
    ) {
        let terminal = HerdrTerminalCoordinator(
            server: server,
            runtime: runtime,
            initialRetryNonce: initialRetryNonce,
            initialNetworkSnapshot: initialNetworkSnapshot,
            initialAppActivity: initialAppActivity,
            onStateChange: onStateChange
        )
        let volumeButtons = HerdrVolumeButtonScrollMonitor()
        volumeButtons.onScroll = { [weak terminal] direction in
            terminal?.handleScroll(direction)
        }
        self.terminal = terminal
        self.volumeButtons = volumeButtons
    }
}

struct HerdrTerminalSurface: UIViewRepresentable {
    let server: Server
    let runtime: HerdrRuntimeReference
    @Binding var state: HerdrConnectionState
    let isVisible: Bool
    let capturesVolumeButtons: Bool
    let retryNonce: Int
    let networkSnapshot: HerdrNetworkSnapshot
    let appActivity: HerdrAppActivity
    let onTerminalReady: (GhosttyTerminalView) -> Void
    let onKeyboardHidden: () -> Void
    let onVoiceInput: () -> Void

    @EnvironmentObject private var ghosttyApp: Ghostty.App

    func makeCoordinator() -> HerdrTerminalSurfaceCoordinator {
        HerdrTerminalSurfaceCoordinator(
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
            coordinator.terminal.bind(to: terminal)
            coordinator.terminal.setVisible(isVisible)
            onTerminalReady(terminal)
        }
        terminal.onZoomAction = { [weak coordinator = context.coordinator] action in
            coordinator?.terminal.handleZoom(action)
        }
        terminal.onKeyboardAccessoryHideRequested = onKeyboardHidden
        terminal.onVoiceButtonTapped = onVoiceInput
        context.coordinator.volumeButtons.attach(to: terminal)
        return terminal
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.terminal.update { state = $0 }
        context.coordinator.terminal.setVisible(isVisible)
        context.coordinator.terminal.observeRetryNonce(retryNonce)
        context.coordinator.terminal.observeNetworkSnapshot(networkSnapshot)
        context.coordinator.terminal.observeAppActivity(appActivity)
        context.coordinator.volumeButtons.setEnabled(
            capturesVolumeButtons
                && isVisible
                && state.isAttached
                && appActivity == .foreground
        )
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: HerdrTerminalSurfaceCoordinator) {
        coordinator.volumeButtons.detach()
        coordinator.terminal.stop()
        if let terminal = uiView as? GhosttyTerminalView {
            terminal.onZoomAction = nil
            terminal.onKeyboardAccessoryHideRequested = nil
            terminal.onVoiceButtonTapped = nil
            terminal.cleanup()
        }
    }
}
#endif
