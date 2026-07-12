import SwiftUI
#if os(iOS)
import UIKit
#endif

enum HerdrWorkspacePreviewState: Equatable {
    case connecting
    case handshaking
    case attached
    case failed(String)
}

struct HerdrWorkspaceView: View {
    let server: Server

    @State private var state: HerdrWorkspacePreviewState = .connecting
    @State private var retryToken = UUID()
    @State private var terminal: GhosttyTerminalView?
    @State private var isKeyboardHidden = false
    @State private var showingVoiceRecording = false
    @State private var voiceProcessing = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var pendingVoiceReturn = false
    @StateObject private var audioService = AudioService()
    @AppStorage("terminalVoiceButtonEnabled") private var voiceButtonEnabled = true

    var body: some View {
        ZStack {
            HerdrTerminalSurface(
                server: server,
                state: $state,
                onTerminalReady: { terminal = $0 },
                onKeyboardHidden: { isKeyboardHidden = true },
                onVoiceInput: startVoiceRecording
            )
                .id(retryToken)

            statusOverlay

            #if os(iOS)
            if shouldShowFloatingInputControls {
                TerminalFloatingInputControls(
                    showsVoiceButton: voiceButtonEnabled,
                    showsReturnButton: pendingVoiceReturn,
                    onKeyboard: showKeyboard,
                    onVoice: startVoiceRecording,
                    onReturn: sendReturn
                )
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
            #endif

            if showingVoiceRecording {
                voiceOverlay
            }
        }
        .background(Color.black)
        .accessibilityIdentifier("herdr.workspace")
        .alert("Voice Input Unavailable", isPresented: $showingPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage)
        }
        .onChange(of: audioService.runtimeRecordingError) { error in
            guard let error else { return }
            permissionErrorMessage = AudioService.formattedRecordingErrorMessage(error)
            showingPermissionError = true
        }
        .onDisappear {
            if showingVoiceRecording {
                audioService.cancelRecording()
            }
            showingVoiceRecording = false
            voiceProcessing = false
            terminal = nil
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch state {
        case .attached:
            EmptyView()
        case .connecting:
            progressCard(title: "Connecting to Herdr…")
        case .handshaking:
            progressCard(title: "Opening Herdr workspace…")
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Herdr is unavailable")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    state = .connecting
                    terminal = nil
                    isKeyboardHidden = false
                    pendingVoiceReturn = false
                    retryToken = UUID()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("herdr.retry")
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding()
            .accessibilityIdentifier("herdr.failed")
        }
    }

    private func progressCard(title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .accessibilityIdentifier("herdr.connecting")
    }

    private var isAttached: Bool {
        state == .attached
    }

    #if os(iOS)
    private var shouldShowFloatingInputControls: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && isAttached
            && isKeyboardHidden
            && terminal?.isHardwareKeyboardAttached != true
            && !showingVoiceRecording
    }

    private func showKeyboard() {
        pendingVoiceReturn = false
        isKeyboardHidden = false
        terminal?.requestKeyboardFocus(for: .explicitUserRequest)
    }

    private func sendReturn() {
        guard terminal?.sendReturnKey() == true else { return }
        pendingVoiceReturn = false
    }
    #endif

    private var voiceOverlay: some View {
        VoiceRecordingView(
            audioService: audioService,
            onSend: { text in
                sendTranscription(text)
                showingVoiceRecording = false
                voiceProcessing = false
            },
            onCancel: {
                showingVoiceRecording = false
                voiceProcessing = false
            },
            isProcessing: $voiceProcessing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(3)
    }

    private func startVoiceRecording() {
        guard isAttached, voiceButtonEnabled, !showingVoiceRecording else { return }
        pendingVoiceReturn = false
        Task {
            do {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = true
                }
                try await audioService.startRecording()
            } catch {
                showingVoiceRecording = false
                voiceProcessing = false
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = AudioService.formattedRecordingErrorMessage(recordingError)
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        }
    }

    private func sendTranscription(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let terminal else { return }
        terminal.sendText(trimmed)
        #if os(iOS)
        if isKeyboardHidden {
            pendingVoiceReturn = true
        }
        #endif
    }
}
