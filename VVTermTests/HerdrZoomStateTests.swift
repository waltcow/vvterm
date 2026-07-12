import XCTest
@testable import VVTerm

@MainActor
final class HerdrZoomStateTests: XCTestCase {
    func testZoomChangesPresentationOverridesAndResetRestoresDefault() {
        let defaults = UserDefaults.standard
        let defaultSize = TerminalDefaults.storedFontSize(defaults: defaults)
        var state = HerdrZoomState()

        let zoomed = state.apply(.zoomIn)
        XCTAssertEqual(
            zoomed.effectiveFontSize,
            TerminalDefaults.clampedFontSize(defaultSize + TerminalDefaults.fontSizeStep)
        )
        XCTAssertFalse(zoomed.presentationOverrides.isEmpty)

        let reset = state.apply(.reset)
        XCTAssertTrue(reset.presentationOverrides.isEmpty)
        XCTAssertEqual(reset.effectiveFontSize, defaultSize)
    }
}
