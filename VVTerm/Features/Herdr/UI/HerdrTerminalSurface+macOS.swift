#if os(macOS)
import SwiftUI
import AppKit

struct HerdrTerminalSurface: NSViewRepresentable {
    let server: Server
    let runtime: HerdrRuntimeReference
    @Binding var state: HerdrConnectionState
    let isVisible: Bool
    let retryNonce: Int
    let networkSnapshot: HerdrNetworkSnapshot
    let onTerminalReady: (GhosttyTerminalView) -> Void
    let onKeyboardHidden: () -> Void
    let onVoiceInput: () -> Void

    @EnvironmentObject private var ghosttyApp: Ghostty.App

    func makeCoordinator() -> HerdrTerminalCoordinator {
        HerdrTerminalCoordinator(
            server: server,
            runtime: runtime,
            initialRetryNonce: retryNonce,
            initialNetworkSnapshot: networkSnapshot
        ) { state = $0 }
    }

    func makeNSView(context: Context) -> NSView {
        guard let app = ghosttyApp.app else { return NSView(frame: .zero) }

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
        return terminal
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update { state = $0 }
        context.coordinator.setVisible(isVisible)
        context.coordinator.observeRetryNonce(retryNonce)
        context.coordinator.observeNetworkSnapshot(networkSnapshot)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: HerdrTerminalCoordinator) {
        coordinator.stop()
        if let terminal = nsView as? GhosttyTerminalView {
            terminal.onZoomAction = nil
            terminal.cleanup()
        }
    }
}
#endif
