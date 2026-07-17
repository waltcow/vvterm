import Foundation
import Testing
@testable import VVTerm

struct HerdrConnectionStateMachineTests {
    @Test
    func rejectsDuplicateBeginUntilActiveGenerationFinishes() throws {
        var machine = HerdrConnectionStateMachine()

        let started = machine.begin()
        let first = try #require(started)

        #expect(machine.state == .connecting)
        let duplicate = machine.begin()
        #expect(duplicate == nil)
        #expect(machine.accepts(first))

        let finished = machine.finish(first, as: .failed(.sshInterrupted("closed")))
        #expect(finished)
        #expect(machine.activeConnectionID == nil)
        #expect(machine.state == .failed(.sshInterrupted("closed")))
        let restarted = machine.begin()
        #expect(restarted != nil)
    }

    @Test
    func staleGenerationCannotPublishOrFinishNewConnection() throws {
        var machine = HerdrConnectionStateMachine()
        let firstStart = machine.begin()
        let old = try #require(firstStart)
        machine.invalidate()
        let reconnectStart = machine.begin(reconnectingAttempt: 1)
        let current = try #require(reconnectStart)

        let staleTransition = machine.transition(to: .attached(versionWarning: nil), for: old)
        let staleFinish = machine.finish(old, as: .failed(.unknown("stale")))
        #expect(!staleTransition)
        #expect(!staleFinish)
        #expect(machine.activeConnectionID == current)
        #expect(machine.state == .reconnecting(attempt: 1))

        let didHandshake = machine.transition(to: .handshaking, for: current)
        let didAttach = machine.transition(to: .attached(versionWarning: nil), for: current)
        #expect(didHandshake)
        #expect(didAttach)
        #expect(machine.state == .attached(versionWarning: nil))
    }

    @Test
    func invalidateReturnsGenerationAndPublishesSuspension() throws {
        var machine = HerdrConnectionStateMachine()
        let started = machine.begin()
        let active = try #require(started)

        let invalidated = machine.invalidate(as: .suspended(.background))
        #expect(invalidated == active)
        #expect(machine.activeConnectionID == nil)
        #expect(machine.state == .suspended(.background))
        let staleTransition = machine.transition(to: .attached(versionWarning: nil), for: active)
        #expect(!staleTransition)
    }
}
