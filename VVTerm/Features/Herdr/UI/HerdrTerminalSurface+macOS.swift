#if os(macOS)
import SwiftUI
import AppKit

struct HerdrTerminalSurface: NSViewRepresentable {
    let server: Server
    @Binding var state: HerdrWorkspacePreviewState

    @EnvironmentObject private var ghosttyApp: Ghostty.App

    func makeCoordinator() -> HerdrTerminalCoordinator {
        HerdrTerminalCoordinator(server: server) { state = $0 }
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
        }
        terminal.onZoomAction = { [weak coordinator = context.coordinator] action in
            coordinator?.handleZoom(action)
        }
        return terminal
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update { state = $0 }
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
