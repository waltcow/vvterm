import Foundation

/// Lazily mounts the Herdr workspace the first time its connection view is
/// selected, then keeps it alive until the containing server route is removed.
nonisolated struct HerdrTabMountState: Equatable, Sendable {
    private(set) var hasMounted = false

    mutating func observe(isSelected: Bool) {
        if isSelected {
            hasMounted = true
        }
    }
}
