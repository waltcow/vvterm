import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct HerdrWorkspaceView: View {
    let server: Server
    let isVisible: Bool
    private let runtime: HerdrRuntimeReference

    @State private var state: HerdrConnectionState = .idle
    @State private var retryNonce = 0
    @State private var terminal: GhosttyTerminalView?
    @State private var isKeyboardHidden = false
    @State private var showingVoiceRecording = false
    @State private var voiceProcessing = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var pendingVoiceReturn = false
    @StateObject private var audioService = AudioService()
    @StateObject private var voiceRecordingOperation = VoiceRecordingOperationCoordinator()
    @ObservedObject private var networkMonitor: NetworkMonitor
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("terminalVoiceButtonEnabled") private var voiceButtonEnabled = true

    init(
        server: Server,
        isVisible: Bool,
        sessionName: String = HerdrRuntimeReference.defaultSessionName,
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.server = server
        self.isVisible = isVisible
        self._networkMonitor = ObservedObject(
            wrappedValue: networkMonitor ?? NetworkMonitor.shared
        )
        self.runtime = HerdrRuntimeReference(
            serverId: server.id,
            sessionName: sessionName
        )
    }

    var body: some View {
        ZStack {
            HerdrTerminalSurface(
                server: server,
                runtime: runtime,
                state: $state,
                isVisible: isVisible,
                retryNonce: retryNonce,
                networkSnapshot: networkSnapshot,
                appActivity: appActivity,
                onTerminalReady: { terminal = $0 },
                onKeyboardHidden: { isKeyboardHidden = true },
                onVoiceInput: startVoiceRecording
            )

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
        .onChange(of: isVisible) { visible in
            guard !visible, showingVoiceRecording else { return }
            cancelVoiceRecording()
        }
        .onChange(of: appActivity) { activity in
            guard activity == .background, showingVoiceRecording else { return }
            cancelVoiceRecording()
        }
        .onDisappear {
            cancelVoiceRecording()
            terminal = nil
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch state {
        case .idle:
            progressCard(title: "Preparing Herdr…")
        case .attached(let versionWarning):
            if let versionWarning {
                versionWarningBanner(versionWarning)
            }
        case .connecting:
            progressCard(title: "Connecting to Herdr…")
        case .handshaking:
            progressCard(title: "Opening Herdr workspace…")
        case .reconnecting(let attempt):
            progressCard(title: "Reconnecting to Herdr (attempt \(attempt))…")
        case .suspended(.background):
            progressCard(title: "Herdr is paused in the background")
        case .suspended(.offline):
            progressCard(title: "Waiting for network…")
        case .failed(let failure):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Herdr is unavailable")
                    .font(.headline)
                Text(failure.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    isKeyboardHidden = false
                    pendingVoiceReturn = false
                    retryNonce += 1
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

    private func versionWarningBanner(_ warning: HerdrBinaryVersionWarning) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(warning.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .allowsHitTesting(false)
        .accessibilityIdentifier("herdr.versionWarning")
    }

    private var isAttached: Bool {
        state.isAttached
    }

    private var networkSnapshot: HerdrNetworkSnapshot {
        let interface: HerdrNetworkInterface
        switch networkMonitor.connectionType {
        case .wifi:
            interface = .wifi
        case .cellular:
            interface = .cellular
        case .ethernet:
            interface = .ethernet
        case .unknown:
            interface = .unknown
        }
        return HerdrNetworkSnapshot(
            isConnected: networkMonitor.isConnected,
            interface: interface
        )
    }

    private var appActivity: HerdrAppActivity {
        #if os(iOS)
        switch scenePhase {
        case .active:
            return .foreground
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
        #else
        return .foreground
        #endif
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
            onStop: finishVoiceRecording,
            onCancel: cancelVoiceRecording,
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
        voiceRecordingOperation.cancel()
        audioService.cancelRecording()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingVoiceRecording = true
        }
        #if os(iOS)
        let activeTerminal = terminal
        let lifecycleState: @MainActor @Sendable () -> AudioCaptureLifecycleState = { [weak activeTerminal] in
            AudioCaptureLifecycleState(
                applicationIsActive: UIApplication.shared.applicationState == .active,
                sceneIsActive: activeTerminal?.window?.windowScene?.activationState == .foregroundActive
            )
        }
        #else
        let lifecycleState: @MainActor @Sendable () -> AudioCaptureLifecycleState = {
            AudioCaptureLifecycleState(
                applicationIsActive: NSApplication.shared.isActive,
                sceneIsActive: NSApplication.shared.isActive
            )
        }
        #endif
        voiceRecordingOperation.start(
            operation: { [audioService] operationID in
                try await audioService.startRecording(
                    operationID: operationID,
                    lifecycleState: lifecycleState
                )
            },
            onSuccess: { _ in },
            onFailure: { error in
                showingVoiceRecording = false
                voiceProcessing = false
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = AudioService.formattedRecordingErrorMessage(recordingError)
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        )
    }

    private func cancelVoiceRecording() {
        voiceRecordingOperation.cancel()
        audioService.cancelRecording()
        showingVoiceRecording = false
        voiceProcessing = false
    }

    private func finishVoiceRecording() {
        guard !voiceProcessing else { return }
        voiceProcessing = true
        voiceRecordingOperation.start(
            operation: { [audioService] operationID in
                await audioService.stopRecording(operationID: operationID)
            },
            onSuccess: { text in
                let fallback = text.isEmpty ? audioService.partialTranscription : text
                sendTranscription(fallback)
                showingVoiceRecording = false
                voiceProcessing = false
            },
            onFailure: { _ in
                showingVoiceRecording = false
                voiceProcessing = false
            }
        )
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
