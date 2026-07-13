import XCTest
@testable import VVTerm

final class HerdrResizeCoalescerTests: XCTestCase {
    func testFirstValidSizeIsSentImmediately() {
        var coalescer = HerdrResizeCoalescer()

        XCTAssertEqual(coalescer.offer(cols: 80, rows: 24), HerdrTerminalSize(cols: 80, rows: 24))
        XCTAssertTrue(coalescer.isThrottleWindowOpen)
    }

    func testBurstKeepsOnlyLatestTrailingSize() {
        var coalescer = HerdrResizeCoalescer()
        _ = coalescer.offer(cols: 80, rows: 24)

        XCTAssertNil(coalescer.offer(cols: 90, rows: 30))
        XCTAssertNil(coalescer.offer(cols: 100, rows: 40))
        XCTAssertEqual(coalescer.flush().size, HerdrTerminalSize(cols: 100, rows: 40))
    }

    func testDuplicateAndInvalidSizesAreIgnored() {
        var coalescer = HerdrResizeCoalescer()

        XCTAssertNil(coalescer.offer(cols: 0, rows: 24))
        XCTAssertNotNil(coalescer.offer(cols: 80, rows: 24))
        XCTAssertNil(coalescer.offer(cols: 80, rows: 24))
        XCTAssertNil(coalescer.pending)
    }

    func testReturningToLastSentSizeCancelsTrailingResize() {
        var coalescer = HerdrResizeCoalescer()
        _ = coalescer.offer(cols: 80, rows: 24)
        _ = coalescer.offer(cols: 100, rows: 40)

        XCTAssertNil(coalescer.offer(cols: 80, rows: 24))
        XCTAssertNil(coalescer.flush().size)
    }

    func testIdleFlushClosesWindowAndNextSizeIsImmediate() {
        var coalescer = HerdrResizeCoalescer()
        _ = coalescer.offer(cols: 80, rows: 24)

        let idleFlush = coalescer.flush()
        XCTAssertNil(idleFlush.size)
        XCTAssertFalse(idleFlush.shouldContinue)
        XCTAssertEqual(coalescer.offer(cols: 100, rows: 40), HerdrTerminalSize(cols: 100, rows: 40))
    }
}
