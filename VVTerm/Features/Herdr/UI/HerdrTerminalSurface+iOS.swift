#if os(iOS)
import SwiftUI
import UIKit

struct HerdrTerminalSurface: UIViewRepresentable {
    let server: Server
    @Binding var state: HerdrWorkspacePreviewState

    @EnvironmentObject private var ghosttyApp: Ghostty.App

    func makeCoordinator() -> HerdrTerminalCoordinator {
        HerdrTerminalCoordinator(server: server) { state = $0 }
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
        }
        terminal.onZoomAction = { [weak coordinator = context.coordinator] action in
            coordinator?.handleZoom(action)
        }
        return terminal
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update { state = $0 }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: HerdrTerminalCoordinator) {
        coordinator.stop()
        if let terminal = uiView as? GhosttyTerminalView {
            terminal.onZoomAction = nil
            terminal.cleanup()
        }
    }
}
#endif
