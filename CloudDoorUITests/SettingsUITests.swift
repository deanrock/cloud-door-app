//
//  SettingsUITests.swift
//  CloudDoorUITests
//

import XCTest

final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        return app
    }

    @MainActor
    func testTappingTheEmailFieldBringsUpTheKeyboard() throws {
        let app = openSettings()

        let email = app.textFields["emailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "The email field should be on the Settings screen")
        email.tap()

        // A software keyboard only shows if the simulator isn't using the Mac's hardware keyboard.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Tapping the email field should show the keyboard")
    }

    @MainActor
    func testTappingThePasswordFieldBringsUpTheKeyboard() throws {
        let app = openSettings()

        let password = app.secureTextFields["passwordField"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), "The password field should be on the Settings screen")
        password.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Tapping the password field should show the keyboard")
    }

    @MainActor
    func testTappingBetweenFieldsKeepsTheKeyboardUp() throws {
        let app = openSettings()

        app.textFields["emailField"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        app.secureTextFields["passwordField"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Moving to the next field must not dismiss the keyboard")
    }
}
