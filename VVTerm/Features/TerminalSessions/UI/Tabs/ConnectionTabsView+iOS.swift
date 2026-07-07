#if os(iOS)
import SwiftUI

extension ConnectionTerminalContainer {
    @ViewBuilder
    var terminalLayer: some View {
        if selectedView == "terminal" && serverTabs.isEmpty {
            TerminalEmptyStateView(server: server) {
                openNewTab()
            }
        }
    }
}
#endif
