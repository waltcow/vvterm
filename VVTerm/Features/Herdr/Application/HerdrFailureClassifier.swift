import Foundation

@MainActor
enum HerdrFailureClassifier {
    static func classify(_ error: Error, sessionName: String) -> HerdrFailure {
        if let transportError = error as? HerdrSSHTransportError {
            switch transportError {
            case .preflightFailed(let result):
                switch result {
                case .binaryMissing:
                    return .binaryMissing
                case .runtimeUnavailable:
                    return .runtimeUnavailable(sessionName: sessionName)
                case .bridgeUnavailable:
                    return .bridgeUnavailable
                case .versionMismatch(let client, let remote):
                    return .versionMismatch(client: client, remote: remote)
                case .protocolMismatch(let client, let remote):
                    return .protocolMismatch(client: client, remote: remote)
                case .invalidStatus:
                    return .invalidStatus
                case .compatible:
                    return .unknown("Unexpected compatible preflight failure.")
                }
            case .connectionClosed:
                return .sshInterrupted("The SSH connection was interrupted.")
            case .concurrentRead, .workspaceRequiresClientKit:
                return .protocolError(String(describing: transportError))
            case .invalidDimensions, .readOnlySession, .inputReleased:
                return .unknown(String(describing: transportError))
            }
        }

        if let sshError = error as? SSHError {
            switch sshError {
            case .authenticationFailed:
                return .authenticationFailed
            case .hostKeyVerificationFailed:
                return .hostKeyVerificationFailed
            case .notConnected, .connectionFailed, .timeout, .channelOpenFailed,
                 .shellRequestFailed, .socketError:
                return .sshInterrupted(sshError.localizedDescription)
            case .moshServerMissing, .moshBootstrapFailed, .moshSessionFailed,
                 .moshInvalidEndpoint, .moshUDPTimeout, .moshClientSessionFailed,
                 .unknown:
                return .unknown(sshError.localizedDescription)
            }
        }

        if let streamFailure = error as? SSHExecStreamFailure {
            switch streamFailure {
            case .transport(let message):
                return .sshInterrupted(message)
            case .remoteExit(let status):
                return .sshInterrupted("The remote SSH stream exited with status \(status).")
            case .bufferLimitExceeded:
                return .protocolError(streamFailure.localizedDescription)
            }
        }

        if let connectionError = error as? HerdrWorkspaceConnectionError {
            switch connectionError {
            case .closed:
                return .sshInterrupted("The Herdr SSH stream closed.")
            case .concurrentRead:
                return .protocolError("Herdr received concurrent stream reads.")
            case .detached:
                return .unknown("The Herdr client detached.")
            }
        }

        if error is HerdrClientKitAdapterError {
            return .protocolError(String(describing: error))
        }
        return .unknown(error.localizedDescription)
    }
}
