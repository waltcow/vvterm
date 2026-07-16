import XCTest
@testable import VVTerm

@MainActor
final class StoreManagerTests: XCTestCase {
    func testDefaultBuildStartsWithProAccessEnabled() {
        XCTAssertTrue(StoreManager.shared.isPro)
    }

    func testDefaultBuildDisablesPaywallPresentation() {
        XCTAssertFalse(StoreFeaturePolicy.paywallPresentationEnabled)
    }
}
