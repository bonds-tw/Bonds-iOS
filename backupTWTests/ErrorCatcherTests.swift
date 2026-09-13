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

    @Test func nativeAlertPreservesTheRecoveryMessageAndOffersTheReport() {
        let report = ErrorDiagnosticReport(shortError: "The original is still on this phone.",
            errorDomain: NSCocoaErrorDomain, errorCode: 513, errorType: "NSError", technicalDetails: "")
        let alert = ErrorCatcher.makeAlert(title: "Could not delete", report: report, on: UIViewController())
        #expect(alert.preferredStyle == .alert)
        #expect(alert.message == report.shortError)
        #expect(alert.actions.count == 3)
        #expect(alert.actions[0].title == NSLocalizedString("Copy details", comment: ""))
        #expect(alert.actions[1].title == NSLocalizedString("Share error report", comment: ""))
        #expect(alert.preferredAction?.style == .cancel)
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

}
