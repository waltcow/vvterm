import XCTest

final class HerdrLifecycleUITests: XCTestCase {
    @MainActor
    func testTabSwitchPreservesIdentityAndForegroundResumeWaitsPastInactive() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--vvterm-ui-test-herdr-lifecycle-harness",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["vvterm.herdrLifecycle.ready"].waitForExistence(timeout: 15)
        )

        app.buttons["vvterm.herdrLifecycle.tab.herdr"].tap()
        let identity = app.staticTexts["vvterm.herdrLifecycle.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        let initialLabel = identity.label

        app.buttons["vvterm.herdrLifecycle.input"].tap()
        XCTAssertTrue(identity.label.contains("input=1"))

        app.buttons["vvterm.herdrLifecycle.tab.terminal"].tap()
        XCTAssertFalse(identity.isHittable)
        app.buttons["vvterm.herdrLifecycle.tab.herdr"].tap()
        XCTAssertEqual(identity.label, initialLabel.replacingOccurrences(of: "input=0", with: "input=1"))

        let diagnostics = app.staticTexts["vvterm.herdrLifecycle.diagnostics"]
        app.buttons["vvterm.herdrLifecycle.background"].tap()
        XCTAssertTrue(wait(for: "action=suspendBackground", in: diagnostics))
        app.buttons["vvterm.herdrLifecycle.inactive"].tap()
        XCTAssertTrue(wait(for: "action=none", in: diagnostics))
        XCTAssertTrue(diagnostics.label.contains("suspended=true"))
        app.buttons["vvterm.herdrLifecycle.foreground"].tap()
        XCTAssertTrue(wait(for: "action=resumeForeground", in: diagnostics))
        XCTAssertTrue(diagnostics.label.contains("suspended=false"))
    }

    @MainActor
    private func wait(
        for fragment: String,
        in element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
