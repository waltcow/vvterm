import Testing
@testable import VVTerm

struct HerdrNetworkRecoveryPolicyTests {
    @Test
    func ignoresInitialUnknownInterfaceResolutionButReconnectsOnRealInterfaceChange() {
        var policy = HerdrNetworkTransitionPolicy(
            initialSnapshot: HerdrNetworkSnapshot(isConnected: true, interface: .unknown)
        )

        let resolved = policy.update(
            HerdrNetworkSnapshot(isConnected: true, interface: .wifi),
            hasStartedSession: true
        )
        let switched = policy.update(
            HerdrNetworkSnapshot(isConnected: true, interface: .cellular),
            hasStartedSession: true
        )

        #expect(resolved == .none)
        #expect(switched == .reconnect)
    }

    @Test
    func suspendsOfflineAndReconnectsOnceConnectivityReturns() {
        var policy = HerdrNetworkTransitionPolicy(
            initialSnapshot: HerdrNetworkSnapshot(isConnected: true, interface: .wifi)
        )

        let offline = policy.update(
            HerdrNetworkSnapshot(isConnected: false, interface: .unknown),
            hasStartedSession: true
        )
        let online = policy.update(
            HerdrNetworkSnapshot(isConnected: true, interface: .cellular),
            hasStartedSession: true
        )

        #expect(offline == .suspendOffline)
        #expect(online == .reconnect)
    }

    @Test
    func doesNotReconnectBeforeHerdrHasBeenMounted() {
        var policy = HerdrNetworkTransitionPolicy(
            initialSnapshot: HerdrNetworkSnapshot(isConnected: false, interface: .unknown)
        )

        let action = policy.update(
            HerdrNetworkSnapshot(isConnected: true, interface: .wifi),
            hasStartedSession: false
        )

        #expect(action == .none)
    }

    @Test
    func backoffIsFiniteAndResettable() {
        var backoff = HerdrReconnectBackoff(delaysMilliseconds: [10, 20])

        let first = backoff.next()
        let second = backoff.next()
        let exhausted = backoff.next()
        backoff.reset()
        let reset = backoff.next()

        #expect(first == HerdrReconnectPlan(attempt: 1, delayMilliseconds: 10))
        #expect(second == HerdrReconnectPlan(attempt: 2, delayMilliseconds: 20))
        #expect(exhausted == nil)
        #expect(reset == HerdrReconnectPlan(attempt: 1, delayMilliseconds: 10))
    }
}

@MainActor
struct HerdrFailureClassifierTests {
    @Test
    func separatesAuthenticationTransportRuntimeAndProtocolFailures() {
        #expect(
            HerdrFailureClassifier.classify(
                SSHError.authenticationFailed,
                sessionName: "session"
            ) == .authenticationFailed
        )

        let transport = HerdrFailureClassifier.classify(
            SSHError.notConnected,
            sessionName: "session"
        )
        #expect(transport.allowsAutomaticReconnect)

        #expect(
            HerdrFailureClassifier.classify(
                HerdrSSHTransportError.preflightFailed(.runtimeUnavailable),
                sessionName: "kept-session"
            ) == .runtimeUnavailable(sessionName: "kept-session")
        )

        if case .protocolError = HerdrFailureClassifier.classify(
            HerdrClientKitAdapterError.invalidBuffer,
            sessionName: "session"
        ) {
            // Expected.
        } else {
            Issue.record("ClientKit errors must be classified as protocol failures")
        }
    }

    @Test
    func treatsMoshOnlyFailuresAsUnrelatedUnknownErrors() {
        let errors: [SSHError] = [
            .moshServerMissing,
            .moshBootstrapFailed("bootstrap"),
            .moshSessionFailed("session"),
            .moshInvalidEndpoint,
            .moshUDPTimeout,
            .moshClientSessionFailed("client"),
        ]

        for error in errors {
            let failure = HerdrFailureClassifier.classify(
                error,
                sessionName: "session"
            )
            guard case .unknown = failure else {
                Issue.record("Mosh-only failures must not be treated as Herdr SSH failures")
                continue
            }
            #expect(!failure.allowsAutomaticReconnect)
        }
    }
}
