import Foundation

/// Converts SwiftUI's monotonic retry nonce into exactly-once retry requests.
nonisolated struct HerdrRetryRequestGate: Equatable, Sendable {
    private(set) var lastHandledNonce: Int

    init(initialNonce: Int = 0) {
        lastHandledNonce = initialNonce
    }

    mutating func consume(_ nonce: Int) -> Bool {
        guard nonce > lastHandledNonce else { return false }
        lastHandledNonce = nonce
        return true
    }
}
