//
//  ErrorCatcher.swift
//  backupTW
//
//  獨立的錯誤捕捉與診斷回報中心。
//  將零散的 UIAlertController 替換為統一的 Short Error、Catch Error 與 Send Error 流程。
//

import UIKit

/// 結構化的錯誤診斷報告，匯總 App 與系統環境資訊，供複製或傳送。
public struct ErrorDiagnosticReport: Sendable {
    public let timestamp: Date
    public let shortError: String
    public let errorDomain: String
    public let errorCode: Int
    public let errorType: String
    public let technicalDetails: String
    public let appVersion: String
    public let buildNumber: String
    public let systemVersion: String
    public let deviceModel: String

    public init(timestamp: Date = Date(),
                shortError: String,
                errorDomain: String,
                errorCode: Int,
                errorType: String,
                technicalDetails: String) {
        self.timestamp = timestamp
        self.shortError = Self.safeUserFacingText(shortError)
        self.errorDomain = Self.safeDomain(errorDomain)
        self.errorCode = errorCode
        self.errorType = Self.safeType(errorType)
        // `technicalDetails` remains a source-compatible initializer argument,
        // but is deliberately not part of the user report. Arbitrary details
        // are not an allowlist and may contain credentials or response bodies.
        self.technicalDetails = NSLocalizedString(
            "Sensitive diagnostic details are excluded from this report.",
            comment: "error catcher privacy boundary")

        let bundle = Bundle.main
        self.appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        self.systemVersion = UIDevice.current.systemVersion
        self.deviceModel = Self.resolveDeviceModel()
    }

    /// 產生格式化診斷文字，提供剪貼簿複製與分享面板傳送。
    public var formattedText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timeString = formatter.string(from: timestamp)

        return """
        【有備而來（Bonds）錯誤診斷報告】
        時間：\(timeString)
        裝置：\(deviceModel)（iOS \(systemVersion)）
        版本：\(appVersion)（Build \(buildNumber)）

        [錯誤概要]
        \(shortError)

        [技術資訊]
        類型：\(errorType)
        識別碼：\(errorDomain)（代碼 \(errorCode)）

        [詳細描述]
        \(technicalDetails)
        """
    }

    /// Error reports are user-controlled output boundaries. A provider error
    /// can contain a URL, a filesystem path, a bearer token, a response body,
    /// or a credential claim even when it is merely being displayed. Keep the
    /// report useful with bounded, redacted text; never serialize NSError's
    /// userInfo or String(describing:) output here.
    fileprivate static func safeUserFacingText(_ value: String) -> String {
        let value = safeDiagnosticText(value)
        return value.isEmpty ? NSLocalizedString(
            "An unexpected issue occurred. Please try again.",
            comment: "fallback error message") : value
    }

    fileprivate static func safeDomain(_ value: String) -> String {
        let allowed: Set<String> = [
            NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain,
            NSOSStatusErrorDomain, XMLParser.errorDomain,
            "tw.bonds.app", "tw.bonds.network", "tw.bonds.store",
            "tw.bonds.test", "tw.bonds.backupTW"
        ]
        return allowed.contains(value) ? value : "unknown"
    }

    fileprivate static func safeType(_ value: String) -> String {
        let allowed: Set<String> = [
            "ApplicationError", "NSError", "NetworkError", "StoreError", "SigningError"
        ]
        return allowed.contains(value) ? value : "ApplicationError"
    }

    private static func safeDiagnosticText(_ value: String) -> String {
        let text = String(value.prefix(240))
        guard !text.isEmpty else { return "" }
        // This helper is only used to protect an explicitly user-facing
        // message. Any credential-shaped or path/URL-shaped content makes the
        // whole message ineligible; it is safer to show the generic message.
        let sensitivePatterns = [
            "(?i)\\b[a-z][a-z0-9+.-]*://",
            "(?i)(?:token|secret|password|passwd|authorization|cookie|credential|userInfo|response[_ -]?body|id[_ -]?number|pin)\\s*[:=]",
            "(?i)\\bpin\\s+\\d{4,}",
            "(?<![A-Za-z0-9])/(?:Users|private|var|tmp|home|Applications|Documents|Library)/",
            "(?<![A-Za-z0-9])[A-Z][12]\\d{8}(?!\\d)"
        ]
        for pattern in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil {
                return NSLocalizedString(
                    "An unexpected issue occurred. Please try again.",
                    comment: "fallback error message")
            }
        }
        return text
    }

    private static func resolveDeviceModel() -> String {
        #if targetEnvironment(simulator)
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "Simulator (\(simModel))"
        }
        return "iPhone Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
        #endif
    }
}

/// 集中管理錯誤彈窗之獨立模組。
@MainActor
public enum ErrorCatcher {

    /// 將任何 Swift Error 解析為 Short Error 與技術診斷細節，並以固定彈窗呈現。
    public static func present(
        error: Error,
        title: String? = nil,
        on presenter: UIViewController? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        let short = deriveShortError(for: error)
        let (domain, code, typeString, details) = extractTechnicalInfo(from: error)
        let report = ErrorDiagnosticReport(
            shortError: short,
            errorDomain: domain,
            errorCode: code,
            errorType: typeString,
            technicalDetails: details
        )
        let alertTitle = title ?? NSLocalizedString("Error", comment: "error catcher default title")
        show(title: alertTitle, report: report, on: presenter, onDismiss: onDismiss)
    }

    /// 傳入自訂短錯誤與技術文字並呈現。
    public static func present(
        title: String? = nil,
        shortError: String,
        technicalDetails: String? = nil,
        underlyingError: Error? = nil,
        on presenter: UIViewController? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        let (domain, code, typeString, extractedDetails) = underlyingError.map(extractTechnicalInfo(from:))
            ?? ("tw.bonds.app", 0, "ApplicationError", technicalDetails ?? shortError)
        let details = technicalDetails ?? extractedDetails
        let report = ErrorDiagnosticReport(
            shortError: shortError,
            errorDomain: domain,
            errorCode: code,
            errorType: typeString,
            technicalDetails: details
        )
        let alertTitle = title ?? NSLocalizedString("Error", comment: "error catcher default title")
        show(title: alertTitle, report: report, on: presenter, onDismiss: onDismiss)
    }

    // MARK: - 內部轉譯與呈現

    private static func show(
        title: String,
        report: ErrorDiagnosticReport,
        on presenter: UIViewController?,
        onDismiss: (() -> Void)?
    ) {
        let controller = ErrorCatcherViewController(title: title, report: report, onDismiss: onDismiss)
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve

        let host = resolvePresenter(explicit: presenter)
        host?.present(controller, animated: true)
    }

    private static func resolvePresenter(explicit: UIViewController?) -> UIViewController? {
        if let explicit {
            var top = explicit
            while let next = top.presentedViewController, !next.isBeingDismissed {
                top = next
            }
            return top
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let root = window.rootViewController else {
            return nil
        }

        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }

    /// 依循 UserFacingError 與 LocalizedError 轉譯出平實人話。
    public static func deriveShortError(for error: Error) -> String {
        // 先嘗試既有的 UserFacingError 轉譯
        if error is OID4VPRequestError || error is OID4VPResponseError || error is TrustListFetcherError {
            return UserFacingError.presentationMessage(for: error)
        }
        if error is OID4VCICollectionError || error is IssuerAuthorization.Refusal || error is CredentialOfferError {
            return UserFacingError.collectionMessage(for: error)
        }
        if error is ConvenienceStorePickupError {
            return UserFacingError.pickupMessage(for: error)
        }
        if error is ModaServiceURLResolverError {
            return UserFacingError.cardApplicationMessage(for: error)
        }
        if error is TelecomCardCatalogError {
            return UserFacingError.telecomCatalogMessage(for: error)
        }

        // 常見網路錯誤處理
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return NSLocalizedString("Could not reach the card service. Check your connection and try again.", comment: "")
            case .timedOut:
                return NSLocalizedString("The request timed out. Please try again in a moment.", comment: "")
            default:
                break
            }
        }

        // LocalizedError 描述
        // Unknown LocalizedError descriptions are not trusted display data;
        // they commonly embed server messages, URLs or credential fields.
        return NSLocalizedString("An unexpected issue occurred. Please try again.", comment: "fallback error message")
    }

    private static func extractTechnicalInfo(from error: Error) -> (domain: String, code: Int, type: String, details: String) {
        let nsError = error as NSError
        let domain = ErrorDiagnosticReport.safeDomain(nsError.domain)
        let code = nsError.code
        let typeString: String
        if error is URLError {
            typeString = "NetworkError"
        } else {
            typeString = "ApplicationError"
        }

        // Keep only a stable classification. The localized short message is
        // already shown above; all arbitrary underlying details stay out of
        // display, copy and share in Release.
        let details = NSLocalizedString(
            "Sensitive diagnostic details are excluded from this report.",
            comment: "error catcher privacy boundary")
        return (domain, code, typeString, details)
    }
}
