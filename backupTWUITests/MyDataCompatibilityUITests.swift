import XCTest

final class MyDataCompatibilityUITests: XCTestCase {
    func testMyDataOpensWithoutTheCertificateAppAndSurvivesReturning() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launchEnvironment["BONDSTW_UI_TEST_BYPASS_UNLOCK"] = "1"
        app.launchEnvironment["BONDSTW_UI_TEST_MYDATA_FLOW_PREVIEW"] = "1"
        app.launch()
        let button = app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Continue', '繼續'}")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10),
                      "A phone without MobileMoica must still reach MyData")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "MyData after returning to Bonds"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testErrorReportRecoveryAndShareRemainReachableWithLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["BONDSTW_UI_TEST_BYPASS_UNLOCK"] = "1"
        app.launchEnvironment["BONDSTW_UI_TEST_ERROR_REPORT_PREVIEW"] = "1"
        app.launch()
        let dismiss = app.buttons["errorCatcher.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["errorCatcher.reportScroll"]
        for _ in 0..<6 where !dismiss.isHittable { scroll.swipeUp() }
        XCTAssertTrue(dismiss.isHittable)
        let share = app.buttons.matching(NSPredicate(format: "label CONTAINS '分享錯誤報告' OR label CONTAINS 'Share error report'")).firstMatch
        XCTAssertTrue(share.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Error report with accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
