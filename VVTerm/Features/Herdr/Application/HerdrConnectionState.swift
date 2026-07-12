import Foundation

/// Owns the active connection generation and rejects stale transitions.
///
/// Starting while a generation is active is intentionally a no-op. Callers
/// must invalidate and clean up that generation before beginning another one.
nonisolated struct HerdrConnectionStateMachine: Sendable {
    private(set) var state: HerdrConnectionState = .idle
    private(set) var activeConnectionID: UUID?

    mutating func begin(reconnectingAttempt: Int? = nil) -> UUID? {
        guard activeConnectionID == nil else { return nil }
        let id = UUID()
        activeConnectionID = id
        if let reconnectingAttempt {
            state = .reconnecting(attempt: reconnectingAttempt)
        } else {
            state = .connecting
        }
        return id
    }

    func accepts(_ connectionID: UUID) -> Bool {
        activeConnectionID == connectionID
    }

    @discardableResult
    mutating func transition(
        to newState: HerdrConnectionState,
        for connectionID: UUID
    ) -> Bool {
        guard accepts(connectionID) else { return false }
        state = newState
        return true
    }

    @discardableResult
    mutating func finish(
        _ connectionID: UUID,
        as finalState: HerdrConnectionState
    ) -> Bool {
        guard accepts(connectionID) else { return false }
        activeConnectionID = nil
        state = finalState
        return true
    }

    @discardableResult
    mutating func invalidate(as newState: HerdrConnectionState = .idle) -> UUID? {
        let invalidatedID = activeConnectionID
        activeConnectionID = nil
        state = newState
        return invalidatedID
    }
}
