import Testing
import UIKit
@testable import backupTW

@MainActor
struct MyDataCompatibilityTests {
    @Test func webVerificationLinksNeverOpenTheCertificateApp() {
        var opened: [URL] = []
        let controller = MyDataWebViewController(
            documentType: MyDataDocumentRegistry.nationalID,
            openCertificateApp: { url, completion in opened.append(url); completion(true) },
            completion: { _ in Issue.record("Opening a login link must not create a card") })
        for address in ["https://mydata.nat.gov.tw/signin", "https://identity.example/verify", "about:blank"] {
            #expect(!controller.handleCertificateLink(URL(string: address)!))
        }
        #expect(opened.isEmpty)
        #expect(!controller.openedCertificateApp)
    }

    @Test func failedOpenIsInterceptedAndCanBeRetried() {
        var attempts = 0
        let controller = MyDataWebViewController(
            documentType: MyDataDocumentRegistry.nationalID,
            openCertificateApp: { _, completion in attempts += 1; completion(false) },
            completion: { _ in Issue.record("Failed app launch must not complete an import") })
        let link = URL(string: "MOBILEMOICA://verify?request=fixture")!
        #expect(controller.handleCertificateLink(link))
        #expect(!controller.openedCertificateApp)
        #expect(controller.handleCertificateLink(link))
        #expect(attempts == 2)
        #expect(!controller.openedCertificateApp)
    }

    @Test func returnConsumesOnlyTheAppHandoffAndDoesNotCompleteTheImport() {
        var attempts = 0
        var finishOpening: (@MainActor (Bool) -> Void)?
        let controller = MyDataWebViewController(
            documentType: MyDataDocumentRegistry.nationalID,
            openCertificateApp: { _, completion in attempts += 1; finishOpening = completion },
            completion: { _ in Issue.record("Returning to Bonds is not proof of MyData verification") })
        let link = URL(string: "mobilemoica://verify?request=fixture")!
        #expect(controller.handleCertificateLink(link))
        #expect(controller.handleCertificateLink(link))
        #expect(attempts == 1, "Repeated navigation must not launch the app twice")
        finishOpening?(true)
        #expect(controller.openedCertificateApp)
        controller.perform(NSSelectorFromString("appDidBecomeActive"))
        #expect(!controller.openedCertificateApp)
        controller.perform(NSSelectorFromString("appDidBecomeActive"))
        #expect(!controller.openedCertificateApp)
        #expect(controller.handleCertificateLink(link))
        #expect(attempts == 2)
    }

    @Test func myDataEntryDoesNotRequireTheCompanionApp() throws {
        // Vault retrieval does not depend on card signing. The simulator has no
        // MobileMoica app, but Continue must still reach the MyData web screen.
        let type = try #require(MyDataDocumentRegistry.lookup(id: "mydata-income"))
        let onboard = MyDataOnboardViewController(documentType: type)
        let navigation = UINavigationController(rootViewController: onboard)
        onboard.loadViewIfNeeded()
        let button = try #require(onboard.navigationItem.rightBarButtonItem)
        #expect(button.isEnabled)
        onboard.perform(try #require(button.action))
        #expect(navigation.topViewController is MyDataWebViewController)
        #expect(onboard.presentedViewController == nil)
    }
}
