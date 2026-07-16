//
//  SettingsView.swift
//  VVTerm
//

import SwiftUI
#if os(macOS)
import AppKit

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
#endif

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case general
    case terminal
    case transcription
    case keychain
    case sync
    case about
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage(TerminalDefaults.fontNameKey) private var terminalFontName = TerminalDefaults.defaultFontName
    @AppStorage(TerminalDefaults.fontSizeKey) private var terminalFontSize = TerminalDefaults.defaultFontSize

    @State private var selection: SettingsSelection? = .general

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                settingsRow("General", icon: "gear", tag: .general)
                settingsRow("Terminal", icon: "terminal", tag: .terminal)
                settingsRow("Transcription", icon: "waveform", tag: .transcription)
                settingsRow("SSH Keys", icon: "key", tag: .keychain)
                settingsRow("Sync", icon: "icloud", tag: .sync)
                settingsRow("About", icon: "info.circle", tag: .about)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 240, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(240)
            .removingSidebarToggle()
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 500)
        #else
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                            .navigationTitle("General")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("General", systemImage: "gear")
                    }

                    NavigationLink {
                        TerminalSettingsView(fontName: $terminalFontName, fontSize: $terminalFontSize)
                            .navigationTitle("Terminal")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }

                    NavigationLink {
                        TranscriptionSettingsView()
                            .navigationTitle("Transcription")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Transcription", systemImage: "waveform")
                    }

                    NavigationLink {
                        KeychainSettingsView()
                            .navigationTitle("SSH Keys")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("SSH Keys", systemImage: "key")
                    }

                    NavigationLink {
                        SyncSettingsView()
                            .navigationTitle("Sync")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Sync", systemImage: "icloud")
                    }

                    NavigationLink {
                        AboutSettingsView()
                            .navigationTitle("About")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .adaptiveSoftScrollEdges()
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
                            GeneralSettingsView()
                                .navigationTitle("General")
                                .navigationSubtitle(String(localized: "Appearance and preferences"))
        case .terminal:
                            TerminalSettingsView(fontName: $terminalFontName, fontSize: $terminalFontSize)
                                .navigationTitle("Terminal")
                                .navigationSubtitle(String(localized: "Font, theme, and connection settings"))
        case .transcription:
                            TranscriptionSettingsView()
                                .navigationTitle("Transcription")
                                .navigationSubtitle(String(localized: "Speech-to-text engine and models"))
        case .keychain:
                            KeychainSettingsView()
                                .navigationTitle("SSH Keys")
                                .navigationSubtitle(String(localized: "Manage stored SSH keys"))
        case .sync:
                            SyncSettingsView()
                                .navigationTitle("Sync")
                                .navigationSubtitle(String(localized: "iCloud sync and data management"))
        case .about:
                            AboutSettingsView()
                                .navigationTitle("About")
                                .navigationSubtitle(String(localized: "Version and links"))
        case .none:
                            GeneralSettingsView()
                                .navigationTitle("General")
                                .navigationSubtitle(String(localized: "Appearance and preferences"))
        }
    }

    private func settingsRow(_ title: LocalizedStringKey, icon: String, tag: SettingsSelection) -> some View {
        Label(title, systemImage: icon)
            .tag(tag)
    }
    #endif
}

// MARK: - Preview

#Preview {
    SettingsView()
}
