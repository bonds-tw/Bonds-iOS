import UIKit
import Testing
@testable import backupTW

@MainActor
struct FirstCardFlowTests {
    @Test func downloadedDataRequiresExplicitSigningAndFailurePreservesReview() {
        let vc = MyDataOnboardViewController()
        let nav = UINavigationController(rootViewController: vc)
        vc.loadViewIfNeeded()
        vc.showParsedDocument(NationalIDModel(nationality: "TEST", unifiedNo: "TEST000001", name: "Fixture", birthdate: "TEST", addressOfHousehold: "TEST"))
        #expect(vc.navigationItem.rightBarButtonItem?.title == NSLocalizedString("Sign and create card", comment: ""))
        #expect(nav.isModalInPresentation)
        #expect(vc.navigationItem.leftBarButtonItem != nil)
        vc.finishIssuance(.failure(CredentialIssuanceError.timedOut))
        #expect(vc.navigationItem.rightBarButtonItem?.title == NSLocalizedString("Retry signing", comment: ""))
        vc.finishIssuance(.success(()))
        #expect(vc.navigationItem.rightBarButtonItem != nil)
        #expect(!nav.isModalInPresentation)
    }

    @Test func leavingReviewDoesNotRetainIdentityDraft() async {
        weak var released: MyDataOnboardViewController?
        autoreleasepool {
            let vc = MyDataOnboardViewController()
            released = vc
            vc.loadViewIfNeeded()
            vc.showParsedDocument(NationalIDModel(nationality: "TEST", unifiedNo: "TEST000001", name: "Fixture", birthdate: "TEST", addressOfHousehold: "TEST"))
        }
        // Diffable data source may finish applying its queued snapshot first.
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(released == nil)
    }

    @Test func passwordNormalization() {
        #expect(MyDataWebViewController.normalizedDocumentPassword("  a123456789\n") == "A123456789")
    }

    @Test func readinessRequiresBothOperationsAndSupportedTransport() {
        #expect(SigningReadiness(version: 1, start_enabled: true, poll_enabled: true, transports: ["app_to_app"]).accepts(.appToApp))
        for readiness in [
            SigningReadiness(version: 1, start_enabled: false, poll_enabled: true, transports: ["app_to_app"]),
            SigningReadiness(version: 1, start_enabled: true, poll_enabled: false, transports: ["app_to_app"]),
            SigningReadiness(version: 2, start_enabled: true, poll_enabled: true, transports: ["app_to_app"]),
            SigningReadiness(version: 1, start_enabled: true, poll_enabled: true, transports: [])
        ] { #expect(!readiness.accepts(.appToApp)) }
        #expect(!SigningReadiness(version: 1, start_enabled: true, poll_enabled: true, transports: ["app_to_app"]).accepts(.push))
    }
}
