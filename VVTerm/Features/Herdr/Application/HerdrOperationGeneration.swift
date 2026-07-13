import Foundation

/// Identifies the latest scheduled operation so cancelled work cannot clear or
/// complete a newer replacement operation.
nonisolated struct HerdrOperationGeneration: Sendable {
    private(set) var currentID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    mutating func invalidate() {
        currentID = nil
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }
}
