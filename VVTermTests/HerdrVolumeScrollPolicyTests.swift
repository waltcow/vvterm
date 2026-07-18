import XCTest
@testable import VVTerm

final class HerdrVolumeScrollPolicyTests: XCTestCase {
    func testInactivePolicyIgnoresVolumeChanges() {
        let policy = HerdrVolumeScrollPolicy()

        XCTAssertNil(policy.scrollDirection(for: 0.75))
        XCTAssertNil(policy.scrollDirection(for: 0.25))
    }

    func testActivePolicyMapsVolumeIncreaseAndDecreaseToScrollDirection() {
        var policy = HerdrVolumeScrollPolicy()
        policy.activate()

        XCTAssertEqual(policy.scrollDirection(for: 0.5625), .up)
        XCTAssertEqual(policy.scrollDirection(for: 0.4375), .down)
    }

    func testCaptureVolumeAndRestorationNoiseDoNotScroll() {
        var policy = HerdrVolumeScrollPolicy()
        policy.activate()

        XCTAssertNil(policy.scrollDirection(for: HerdrVolumeScrollPolicy.captureVolume))
        XCTAssertNil(policy.scrollDirection(for: 0.5001))
        XCTAssertNil(policy.scrollDirection(for: .nan))

        policy.deactivate()
        XCTAssertNil(policy.scrollDirection(for: 0.75))
    }
}
