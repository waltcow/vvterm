import SwiftUI

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

    var body: some View {
        ZStack {
            HerdrTerminalSurface(server: server, state: $state)
                .id(retryToken)

            statusOverlay
        }
        .background(Color.black)
        .accessibilityIdentifier("herdr.workspace")
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
}
