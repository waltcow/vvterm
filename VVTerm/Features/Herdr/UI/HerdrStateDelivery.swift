import Foundation

/// Defers coordinator state callbacks until SwiftUI has finished its current
/// representable update and invalidates queued callbacks during teardown.
@MainActor
final class HerdrStateDelivery<State> {
    typealias Scheduler = (@escaping @MainActor () -> Void) -> Void

    private var callback: ((State) -> Void)?
    private var generation: UInt = 0
    private let scheduler: Scheduler

    init(
        callback: @escaping (State) -> Void,
        scheduler: @escaping Scheduler = { action in
            Task { @MainActor in
                action()
            }
        }
    ) {
        self.callback = callback
        self.scheduler = scheduler
    }

    func update(callback: @escaping (State) -> Void) {
        self.callback = callback
    }

    func enqueue(_ state: State) {
        guard callback != nil else { return }
        let scheduledGeneration = generation
        scheduler { [weak self] in
            guard let self,
                  self.generation == scheduledGeneration,
                  let callback = self.callback else { return }
            callback(state)
        }
    }

    func invalidate() {
        generation &+= 1
        callback = nil
    }
}
