import XCTest
@testable import VVTerm

@MainActor
final class StoreManagerTests: XCTestCase {
    func testDefaultBuildStartsWithProAccessEnabled() {
        XCTAssertTrue(StoreManager.shared.isPro)
    }
}
