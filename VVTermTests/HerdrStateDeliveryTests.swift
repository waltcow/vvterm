import XCTest
@testable import VVTerm

@MainActor
final class HerdrStateDeliveryTests: XCTestCase {
    func testDeliveryWaitsUntilScheduledWorkRuns() {
        var pending: [@MainActor () -> Void] = []
        var received: [Int] = []
        let delivery = HerdrStateDelivery<Int>(
            callback: { received.append($0) },
            scheduler: { pending.append($0) }
        )

        delivery.enqueue(1)

        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(pending.count, 1)
        pending.removeFirst()()
        XCTAssertEqual(received, [1])
    }

    func testTeardownDropsQueuedAndFutureStateCallbacks() {
        var pending: [@MainActor () -> Void] = []
        var received: [Int] = []
        let delivery = HerdrStateDelivery<Int>(
            callback: { received.append($0) },
            scheduler: { pending.append($0) }
        )

        delivery.enqueue(1)
        delivery.invalidate()
        delivery.enqueue(2)
        pending.removeFirst()()

        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(pending.isEmpty)
    }
}
