import Foundation

nonisolated enum HerdrNetworkInterface: Equatable, Sendable {
    case wifi
    case cellular
    case ethernet
    case unknown
}

nonisolated struct HerdrNetworkSnapshot: Equatable, Sendable {
    let isConnected: Bool
    let interface: HerdrNetworkInterface
}

nonisolated enum HerdrNetworkAction: Equatable, Sendable {
    case none
    case suspendOffline
    case reconnect
}

nonisolated struct HerdrNetworkTransitionPolicy: Sendable {
    private(set) var snapshot: HerdrNetworkSnapshot

    init(initialSnapshot: HerdrNetworkSnapshot) {
        snapshot = initialSnapshot
    }

    mutating func update(
        _ newSnapshot: HerdrNetworkSnapshot,
        hasStartedSession: Bool
    ) -> HerdrNetworkAction {
        let previous = snapshot
        snapshot = newSnapshot

        guard newSnapshot != previous else { return .none }
        guard newSnapshot.isConnected else { return .suspendOffline }
        guard hasStartedSession else { return .none }

        if !previous.isConnected {
            return .reconnect
        }

        let knownInterfaceChanged = previous.interface != .unknown
            && newSnapshot.interface != .unknown
            && previous.interface != newSnapshot.interface
        return knownInterfaceChanged ? .reconnect : .none
    }
}
