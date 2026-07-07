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

extension ManageCustomThemesSheet {
    var platformBody: some View {
        NavigationStack {
            Group {
                if sortedThemes.isEmpty {
                    customThemesEmptyState
                } else {
                    List {
                        ForEach(sortedThemes) { theme in
                            themeRow(theme)
                        }
                    }
                }
            }
            .navigationTitle("Custom Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        createThemeMenuItems
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private func themeRow(_ theme: TerminalTheme) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                if let assignment = assignmentLabel(for: theme.name) {
                    Text(assignment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Menu {
                applyMenuItems(themeName: theme.name)

                Divider()

                Button("Edit") {
                    themePendingEdit = theme
                }

                Button("Delete", role: .destructive) {
                    themePendingDeletion = theme
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Edit") {
                themePendingEdit = theme
            }
            .tint(.blue)

            Button("Delete", role: .destructive) {
                themePendingDeletion = theme
            }
        }
    }
}
#endif
