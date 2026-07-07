#if os(iOS)
import SwiftUI
import UIKit

extension TerminalSettingsView {
    func loadSystemFonts() -> [String] {
        var fonts = ["Menlo", "SF Mono", "Courier New"]
        let nerdFonts = [
            "JetBrainsMono Nerd Font",
            "Hack Nerd Font",
            "FiraCode Nerd Font",
            "MesloLGS Nerd Font"
        ]

        for fontFamily in nerdFonts where UIFont(name: fontFamily, size: 12) != nil {
            fonts.append(fontFamily)
        }

        return fonts.sorted()
    }

    @ViewBuilder
    var keyboardAccessorySection: some View {
        if terminalAccessoryCustomizationEnabled {
            Section {
                Toggle("Show keyboard dismiss button", isOn: $terminalKeyboardDismissButtonEnabled)

                NavigationLink {
                    TerminalAccessoryCustomizationView()
                } label: {
                    Text("Customize Accessory Bar")
                }

                NavigationLink {
                    TerminalCustomActionLibraryView()
                } label: {
                    Text("Manage Custom Actions")
                }
            } header: {
                Text("Keyboard Accessory")
            } footer: {
                Text("Reorder actions, add custom actions, show or hide the keyboard dismiss button, and sync your accessory bar across devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
