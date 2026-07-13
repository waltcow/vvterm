import Foundation

nonisolated enum HerdrAppActivity: Equatable, Sendable {
    case foreground
    case inactive
    case background
}

nonisolated enum HerdrAppLifecycleAction: Equatable, Sendable {
    case none
    case suspendBackground
    case resumeForeground
}

nonisolated struct HerdrAppLifecyclePolicy: Sendable {
    private(set) var activity: HerdrAppActivity
    private(set) var isSuspendedForBackground: Bool

    init(initialActivity: HerdrAppActivity) {
        activity = initialActivity
        isSuspendedForBackground = initialActivity == .background
    }

    mutating func update(
        _ newActivity: HerdrAppActivity,
        hasStartedSession: Bool
    ) -> HerdrAppLifecycleAction {
        activity = newActivity

        if newActivity == .background {
            guard !isSuspendedForBackground else { return .none }
            isSuspendedForBackground = true
            return hasStartedSession ? .suspendBackground : .none
        }

        if newActivity == .foreground, isSuspendedForBackground {
            isSuspendedForBackground = false
            return hasStartedSession ? .resumeForeground : .none
        }

        return .none
    }
}
