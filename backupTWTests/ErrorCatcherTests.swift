//
//  ErrorCatcherTests.swift
//  backupTWTests
//
//  驗證 ErrorCatcher 與 ErrorDiagnosticReport 的功能、格式與排版完整性。
//

import Foundation
import Testing
import UIKit
@testable import backupTW

private enum SampleTestError: LocalizedError {
    case connectionDropped
    case customBroken(reason: String)

    var errorDescription: String? {
        switch self {
        case .connectionDropped:
            return "無法連線至發卡服務，請檢查網路連線。"
        case .customBroken(let reason):
            return "操作未完成：\(reason)"
        }
    }
}

@MainActor
struct ErrorCatcherTests {

    @Test func diagnosticReportContainsStandardFields() {
        let report = ErrorDiagnosticReport(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            shortError: "連線超時，請稍後再試。",
            errorDomain: "tw.bonds.network",
            errorCode: 408,
            errorType: "TimeoutError",
            technicalDetails: "gateway timeout after 30000ms"
        )

        let text = report.formattedText

        #expect(text.contains("【有備而來（Bonds）錯誤診斷報告】"))
        #expect(text.contains("[錯誤概要]"))
        #expect(text.contains("連線超時，請稍後再試。"))
        #expect(text.contains("[技術資訊]"))
        #expect(text.contains("類型：ApplicationError"))
        #expect(text.contains("識別碼：tw.bonds.network（代碼 408）"))
        #expect(text.contains("[詳細描述]"))
        #expect(text.contains("Sensitive diagnostic details are excluded from this report.") ||
                text.contains("此報告不包含敏感診斷詳細資料。"))
        #expect(text.contains("裝置："))
        #expect(text.contains("iOS"))
    }

    @Test func shortErrorDerivesFromLocalizedError() {
        let error = SampleTestError.connectionDropped
        let short = ErrorCatcher.deriveShortError(for: error)
        #expect(short.contains("unexpected") || short.contains("未預期"))
    }

    @Test func shortErrorDerivesFromURLError() {
        let urlError = URLError(.notConnectedToInternet)
        let short = ErrorCatcher.deriveShortError(for: urlError)
        #expect(short.contains("card service") || short.contains("連線") || short.contains("網路"))
    }

    @Test func errorCatcherViewControllerInstantiatesWithExpectedStructure() {
        let report = ErrorDiagnosticReport(
            shortError: "儲存卡片失敗",
            errorDomain: "tw.bonds.store",
            errorCode: -1,
            errorType: "StoreFailure",
            technicalDetails: "disk write error"
        )

        let vc = ErrorCatcherViewController(title: "測試錯誤", report: report)
        #expect(vc.modalPresentationStyle == .overFullScreen)
        #expect(vc.modalTransitionStyle == .crossDissolve)

        // 觸發 viewDidLoad
        vc.loadViewIfNeeded()

        #expect(vc.view.backgroundColor == .clear)
        // 驗證 subviews 有加入 backdropView 與 cardContainer
        #expect(vc.view.subviews.count >= 2)
    }

    @Test func technicalDetailsScrollTogetherWithTheRecoveryActions() throws {
        let report = ErrorDiagnosticReport(
            shortError: "測試錯誤概要", errorDomain: "tw.bonds.test", errorCode: 100,
            errorType: "ApplicationError", technicalDetails: "safe diagnostic details")
        let vc = ErrorCatcherViewController(title: "測試錯誤", report: report)
        vc.loadViewIfNeeded()
        func descendant(in view: UIView, identifier: String) -> UIView? {
            if view.accessibilityIdentifier == identifier { return view }
            return view.subviews.lazy.compactMap { descendant(in: $0, identifier: identifier) }.first
        }
        let scroll = try #require(descendant(in: vc.view, identifier: "errorCatcher.reportScroll") as? UIScrollView)
        let detail = try #require(descendant(in: vc.view, identifier: "errorCatcher.technicalDetails") as? UILabel)
        #expect(detail.isDescendant(of: scroll))
        #expect(detail.text == "\(report.errorType) (\(report.errorCode))\n\(report.technicalDetails)")
    }

    @Test func reportTextRespectsCopyGuideRules() {
        let report = ErrorDiagnosticReport(
            shortError: "測試錯誤概要",
            errorDomain: "tw.bonds.test",
            errorCode: 100,
            errorType: "TestType",
            technicalDetails: "test technical details"
        )
        let text = report.formattedText

        // 不得出現「您」
        #expect(!text.contains("您"))
        // 不得出現「本 App」或「這支 App」
        #expect(!text.contains("本 App"))
        #expect(!text.contains("這支 App"))
    }

    @Test func releaseSafeReportExcludesSecretsPathsURLsAndUserInfo() {
        let error = NSError(
            domain: "/private/var/mobile/Containers/Data/application.sqlite",
            code: 17,
            userInfo: [
                NSLocalizedDescriptionKey: "https://broker.example/v1/poll?token=secret-token",
                "authorization": "Bearer very-secret-value",
                "response_body": "credential=A123456789"
            ])
        let report = ErrorDiagnosticReport(
            shortError: error.localizedDescription,
            errorDomain: error.domain,
            errorCode: error.code,
            errorType: "NSError",
            technicalDetails: "身分證 A123456789 PIN 1234 response secret-value")

        let text = report.formattedText
        #expect(!text.contains("secret-token"))
        #expect(!text.contains("very-secret-value"))
        #expect(!text.contains("A123456789"))
        #expect(!text.contains("https://broker.example"))
        #expect(!text.contains("/private/var/mobile"))
        #expect(!text.contains("userInfo"))
        #expect(text.contains("Sensitive diagnostic details are excluded from this report.") ||
                text.contains("此報告不包含敏感診斷詳細資料。"))
    }

    @Test func unknownLocalizedErrorUsesGenericShortMessage() {
        let error = SampleTestError.customBroken(reason: "身分證 A123456789 PIN 1234 response secret-value")
        let short = ErrorCatcher.deriveShortError(for: error)
        #expect(short.contains("unexpected") || short.contains("未預期"))
        #expect(!short.contains("A123456789"))
        #expect(!short.contains("secret-value"))
    }

    @Test func metadataUsesExactAllowlists() {
        let report = ErrorDiagnosticReport(
            shortError: "PIN 1234",
            errorDomain: "tw.bonds.A123456789",
            errorCode: 9,
            errorType: "response secret-value",
            technicalDetails: "response secret-value")

        let text = report.formattedText
        #expect(text.contains("unknown"))
        #expect(text.contains("ApplicationError"))
        #expect(!text.contains("A123456789"))
        #expect(!text.contains("PIN 1234"))
        #expect(!text.contains("secret-value"))
    }

    @Test func knownDocumentErrorsKeepTheirRecoveryMessage() {
        let error = OfficialDocumentInboxError.signatureInvalid
        #expect(ErrorCatcher.deriveShortError(for: error) == error.localizedDescription)
        let packageError = OfficialDocumentPackageError.hashMismatch("private fixture filename")
        #expect(ErrorCatcher.deriveShortError(for: packageError) == packageError.localizedDescription)
        #expect(!ErrorCatcher.deriveShortError(for: packageError).contains("private fixture filename"))
    }

    @Test func deletionRecoveryIsPreservedInTheShareableReport() {
        let message = NSLocalizedString("The protected original is still on this phone. Try again in a moment.", comment: "")
        let report = ErrorDiagnosticReport(shortError: message, errorDomain: NSCocoaErrorDomain,
                                           errorCode: 513, errorType: "NSError", technicalDetails: "/private/fixture")
        #expect(report.shortError == message)
        #expect(report.formattedText.contains(message))
        #expect(!report.formattedText.contains("/private/fixture"))
    }

    @Test func theDismissButtonRemainsReachableOnAShortScreenWithLargeText() throws {
        let report = ErrorDiagnosticReport(
            shortError: String(repeating: "The document is still on this phone. ", count: 6),
            errorDomain: "tw.bonds.store", errorCode: 1, errorType: "StoreError", technicalDetails: "")
        let controller = ErrorCatcherViewController(title: "The document was not deleted", report: report)
        let host = UIViewController()
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        controller.view.layoutIfNeeded()
        func find(_ id: String, in view: UIView) -> UIView? {
            if view.accessibilityIdentifier == id { return view }
            return view.subviews.lazy.compactMap { find(id, in: $0) }.first
        }
        let scroll = try #require(find("errorCatcher.reportScroll", in: controller.view) as? UIScrollView)
        let button = try #require(find("errorCatcher.dismiss", in: controller.view))
        #expect(scroll.contentSize.height > scroll.bounds.height)
        let buttonRect = button.convert(button.bounds, to: scroll)
        #expect(buttonRect.maxY <= scroll.contentSize.height)
        scroll.scrollRectToVisible(buttonRect, animated: false)
        #expect(scroll.bounds.contains(buttonRect))
    }
}
