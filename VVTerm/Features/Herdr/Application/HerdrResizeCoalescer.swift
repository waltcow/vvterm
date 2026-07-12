import Foundation

nonisolated struct HerdrTerminalSize: Equatable, Sendable {
    let cols: UInt16
    let rows: UInt16
}

/// Leading-edge resize with a trailing update for the latest dimensions.
///
/// The caller owns the clock. After an immediate value is returned from
/// `offer`, it should call `flush` once per throttle interval until
/// `shouldContinue` becomes false.
nonisolated struct HerdrResizeCoalescer: Sendable {
    private(set) var lastSent: HerdrTerminalSize?
    private(set) var pending: HerdrTerminalSize?
    private(set) var isThrottleWindowOpen = false

    mutating func offer(cols: Int, rows: Int) -> HerdrTerminalSize? {
        guard cols > 0, rows > 0 else { return nil }

        let size = HerdrTerminalSize(
            cols: UInt16(clamping: cols),
            rows: UInt16(clamping: rows)
        )
        guard isThrottleWindowOpen else {
            guard size != lastSent else { return nil }
            isThrottleWindowOpen = true
            lastSent = size
            return size
        }

        if size == lastSent {
            pending = nil
            return nil
        }
        guard size != pending else { return nil }
        pending = size
        return nil
    }

    mutating func flush() -> (size: HerdrTerminalSize?, shouldContinue: Bool) {
        guard let pending else {
            isThrottleWindowOpen = false
            return (nil, false)
        }

        self.pending = nil
        lastSent = pending
        return (pending, true)
    }

    mutating func reset() {
        lastSent = nil
        pending = nil
        isThrottleWindowOpen = false
    }
}
