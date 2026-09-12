import XCTest

final class FirstCardFlowUITests: XCTestCase {
    func testDownloadedDetailsWaitForExplicitSigningAndCancelCanKeepDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["BONDSTW_UI_TEST_BYPASS_UNLOCK"] = "1"
        app.launchEnvironment["BONDSTW_UI_TEST_FORMAL_DOCUMENT_PREVIEW"] = "review"
        app.launchArguments += ["-AppleLanguages", "(zh-Hant)"]
        app.launch()
        let sign = app.buttons["簽章並建立卡片"]
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["請檢查下載的資料"].exists)
        XCTAssertFalse(app.staticTexts["卡片已儲存"].exists)
        XCTAssertTrue(app.staticTexts["證件資料"].exists)
        XCTAssertFalse(app.staticTexts["接下來會發生什麼"].exists)
        app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Cancel', '取消'}")).firstMatch.tap()
        XCTAssertTrue(app.alerts["捨棄這次的卡片草稿？"].waitForExistence(timeout: 3))
        app.buttons["繼續檢查"].tap()
        XCTAssertTrue(sign.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MyData review before explicit signing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
