import Foundation
import Testing
@testable import VVTerm

struct HerdrRetryRequestGateTests {
    @Test
    func consumesEachMonotonicRetryNonceOnce() {
        var gate = HerdrRetryRequestGate(initialNonce: 4)

        let duplicateInitial = gate.consume(4)
        let stale = gate.consume(3)
        let first = gate.consume(5)
        let duplicate = gate.consume(5)
        let latest = gate.consume(7)
        #expect(!duplicateInitial)
        #expect(!stale)
        #expect(first)
        #expect(!duplicate)
        #expect(latest)
        #expect(gate.lastHandledNonce == 7)
    }

    @Test
    func runtimeIdentityKeepsServerAndSessionStableAcrossRetries() {
        let runtime = HerdrRuntimeReference(
            serverId: UUID(),
            sessionName: "persistent-session"
        )
        var gate = HerdrRetryRequestGate()

        let first = gate.consume(1)
        let second = gate.consume(2)
        #expect(first)
        #expect(second)
        #expect(runtime.sessionName == "persistent-session")
        #expect(
            HerdrRemoteCommandBuilder(sessionName: runtime.sessionName).workspaceBridge()
                .contains("'persistent-session'")
        )
    }
}
