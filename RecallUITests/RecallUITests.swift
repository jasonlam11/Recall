import XCTest

/// One smoke test: the app launches and shows its composer.
///
/// Deliberately minimal. UI tests here are slow (seconds each) and brittle
/// against layout changes, so the logic worth testing lives in unit tests
/// instead. This exists to catch a launch-time crash — the one failure a unit
/// test genuinely cannot see.
final class RecallUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchesAndShowsComposer() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["New Entry"].waitForExistence(timeout: 10),
            "Composer heading should be visible on launch"
        )
    }
}
