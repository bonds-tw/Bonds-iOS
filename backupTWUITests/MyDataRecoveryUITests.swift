import XCTest

final class MyDataRecoveryUITests: XCTestCase {
    private func launch(_ preview: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launchEnvironment["BONDSTW_UI_TEST_BYPASS_UNLOCK"] = "1"
        app.launchEnvironment[preview] = "1"
        app.launch()
        return app
    }

    private func button(_ app: XCUIApplication, _ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    func testSigningFailureCanRetryOnTheSameScreen() {
        let app = launch("BONDSTW_UI_TEST_MYDATA_RECOVERY_PREVIEW")
        let confirm = button(app, ["Confirm", "確認"])
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        let retry = button(app, ["Retry signing", "重試簽章"])
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Signing failure with retry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(button(app, ["Done", "完成"]).waitForExistence(timeout: 5))
        XCTAssertFalse(button(app, ["Retry signing", "重試簽章"]).exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testWrongPasswordThenCorrectPasswordUsesTheSamePDF() {
        let app = launch("BONDSTW_UI_TEST_MYDATA_PASSWORD_PREVIEW")
        var field = app.secureTextFields["mydata.pdfPassword"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(button(app, ["Continue", "繼續"]).isEnabled)
        field.tap()
        field.typeText("WRONG")
        button(app, ["Continue", "繼續"]).tap()
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(
            format: "label CONTAINS '不必重新下載' OR label CONTAINS 'do not need to download'"))
            .firstMatch.waitForExistence(timeout: 5))
        field = app.secureTextFields["mydata.pdfPassword"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(button(app, ["Continue", "繼續"]).isEnabled)
        field.tap()
        field.typeText("test000001")
        button(app, ["Continue", "繼續"]).tap()
        XCTAssertTrue(button(app, ["Done", "完成"]).waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testCancellingPasswordReturnsToTheSameMyDataPage() {
        let app = launch("BONDSTW_UI_TEST_MYDATA_PASSWORD_PREVIEW")
        XCTAssertTrue(app.secureTextFields["mydata.pdfPassword"].waitForExistence(timeout: 10))
        button(app, ["Cancel", "取消"]).tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS '尚未匯入 PDF' OR label CONTAINS 'PDF was not imported'"))
            .firstMatch.waitForExistence(timeout: 5))
    }
}
