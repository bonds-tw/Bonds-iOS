import Testing
import UIKit
import PDFKit
@testable import backupTW

@MainActor
struct MyDataRecoveryTests {
    private let model = NationalIDModel(nationality: "fixture", unifiedNo: "TEST000001",
                                        name: "fixture", birthdate: nil, addressOfHousehold: nil)

    @Test func failedSigningCanReuseTheDownloadedDetailsWithoutOpeningMyData() async throws {
        let signer = RecoverySigner()
        let controller = MyDataOnboardViewController(issueAndStore: { model, id in
            try await signer.issue(model, id: id)
        })
        let navigation = UINavigationController(rootViewController: controller)
        controller.loadViewIfNeeded()
        let first = try #require(controller.issueCredential(for: model))
        #expect(controller.isIssuing)
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == false)
        #expect(controller.issueCredential(for: model) == nil, "Rapid taps must not start another signing request")
        await signer.resolve(.failure(CredentialIssuanceError.timedOut))
        await first.value
        #expect(!controller.isIssuing)
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == true)
        #expect(controller.navigationItem.rightBarButtonItem?.action == #selector(controller.retryIssuance))

        // Invoke the same action the user taps, with no second download/model.
        controller.retryIssuance()
        controller.retryIssuance()
        #expect(controller.isIssuing)
        await signer.resolve(.success(()))
        for _ in 0..<100 where controller.isIssuing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.isIssuing)
        let calls = await signer.calls
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.0 == "TEST000001" && $0.1 == MyDataDocumentRegistry.nationalID.id })
        #expect(navigation.viewControllers.count == 1, "Retry must not reopen MyData")
        #expect(controller.navigationItem.leftBarButtonItem == nil)
        #expect(controller.issueCredential(for: model) == nil, "A completed screen cannot issue again")
    }

    @Test func closingDoesNotCancelTheExistingDetachedSigningOperation() async throws {
        let signer = RecoverySigner()
        let controller = MyDataOnboardViewController(issueAndStore: { model, id in
            try await signer.issue(model, id: id)
        })
        controller.loadViewIfNeeded()
        let task = try #require(controller.issueCredential(for: model))
        let close = try #require(controller.navigationItem.leftBarButtonItem?.action)
        controller.perform(close)
        await signer.resolve(.success(()))
        await task.value
        #expect(await signer.calls.count == 1)
        #expect(!controller.isIssuing)
        #expect(controller.navigationItem.leftBarButtonItem == nil)
    }

    @Test func closingAfterFailureDropsTheRetryDetails() async throws {
        let signer = RecoverySigner()
        let controller = MyDataOnboardViewController(issueAndStore: { model, id in
            try await signer.issue(model, id: id)
        })
        controller.loadViewIfNeeded()
        let task = try #require(controller.issueCredential(for: model))
        await signer.resolve(.failure(CredentialIssuanceError.timedOut))
        await task.value
        controller.perform(try #require(controller.navigationItem.leftBarButtonItem?.action))
        controller.retryIssuance()
        #expect(!controller.isIssuing)
        #expect(await signer.calls.count == 1)
    }

    @Test func pdfPromptHasAnEscapeAndRejectsEmptyInput() throws {
        let controller = MyDataWebViewController(documentType: MyDataDocumentRegistry.nationalID,
            completion: { _ in Issue.record("Constructing or editing a prompt must not complete import") })
        let prompt = controller.makePDFPasswordAlert(for: PDFDocument())
        let field = try #require(prompt.textFields?.first)
        let confirm = try #require(prompt.preferredAction)
        #expect(prompt.actions.contains { $0.style == .cancel })
        #expect(field.isSecureTextEntry)
        #expect(field.autocorrectionType == .no)
        #expect(field.keyboardType == .asciiCapable)
        #expect(!confirm.isEnabled)
        field.text = "  \n "
        field.sendActions(for: .editingChanged)
        #expect(!confirm.isEnabled)
        field.text = " test000001 "
        field.sendActions(for: .editingChanged)
        #expect(confirm.isEnabled)
        #expect(MyDataWebViewController.normalizedPDFPassword(field.text!) == "TEST000001")
        field.text = ""
        field.sendActions(for: .editingChanged)
        #expect(!confirm.isEnabled)
    }

    @Test func dismissedPasswordPromptDoesNotRetainItsControllerOrField() {
        weak var weakController: MyDataWebViewController?
        weak var weakPrompt: UIAlertController?
        weak var field: UITextField?
        autoreleasepool {
            let controller = MyDataWebViewController(
                documentType: MyDataDocumentRegistry.nationalID, completion: { _ in })
            let prompt = controller.makePDFPasswordAlert(for: PDFDocument())
            weakController = controller
            weakPrompt = prompt
            field = prompt.textFields?.first
            field?.text = "TEST000001"
        }
        #expect(weakPrompt == nil)
        #expect(weakController == nil)
        #expect(field == nil)
    }

    @Test func passwordPreviewUsesARealEncryptedParseablePDF() throws {
        let pdf = try #require(MyDataWebViewController.makePDFPasswordPreviewForUITest())
        #expect(pdf.isLocked)
        #expect(!pdf.unlock(withPassword: "WRONG"))
        #expect(pdf.unlock(withPassword: "TEST000001"))
        let text = try #require(pdf.page(at: 0)?.string)
        #expect(NationalIDModel.parse(fromPDFText: text)?.unifiedNo == "TEST000001", "Synthetic PDF text: \(text)")
    }

}

private actor RecoverySigner {
    private(set) var calls: [(String?, String)] = []
    private var pending: CheckedContinuation<Void, Error>?
    private var queuedResult: Result<Void, Error>?

    func issue(_ model: NationalIDModel, id: String) async throws {
        calls.append((model.unifiedNo, id))
        try await withCheckedThrowingContinuation { continuation in
            if let queuedResult {
                self.queuedResult = nil
                continuation.resume(with: queuedResult)
            } else {
                pending = continuation
            }
        }
    }

    func resolve(_ result: Result<Void, Error>) {
        if let pending {
            self.pending = nil
            pending.resume(with: result)
        } else {
            queuedResult = result
        }
    }
}
