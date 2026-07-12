import Foundation

nonisolated struct HerdrReconnectPlan: Equatable, Sendable {
    let attempt: Int
    let delayMilliseconds: Int
}

nonisolated struct HerdrReconnectBackoff: Sendable {
    private let delaysMilliseconds: [Int]
    private(set) var completedAttempts = 0

    init(delaysMilliseconds: [Int] = [500, 1_000, 2_000, 5_000]) {
        self.delaysMilliseconds = delaysMilliseconds
    }

    mutating func next() -> HerdrReconnectPlan? {
        guard completedAttempts < delaysMilliseconds.count else { return nil }
        let plan = HerdrReconnectPlan(
            attempt: completedAttempts + 1,
            delayMilliseconds: delaysMilliseconds[completedAttempts]
        )
        completedAttempts += 1
        return plan
    }

    mutating func reset() {
        completedAttempts = 0
    }
}
