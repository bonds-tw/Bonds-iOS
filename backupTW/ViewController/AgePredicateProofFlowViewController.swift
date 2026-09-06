//
//  AgePredicateProofFlowViewController.swift
//  backupTW
//
//  Online age proofs. Scan the website request, obtain consent, create the
//  proof locally, then submit it to the approved HTTPS verifier.
//

import UIKit

@MainActor
enum AgePredicateProofHolderFlow {

    static func begin(on navigationController: UINavigationController?) {
        final class Latch { var fired = false }
        let latch = Latch()
        let scanner = QRScanningViewController(
            title: NSLocalizedString("Scan an online age-check request", comment: "age proof"),
            prompt: NSLocalizedString("Scan the age-check QR code on the verifier website. Internet is required.", comment: "age proof"),
            allowsPhotoImport: true
        ) { [weak navigationController] text in
            guard !latch.fired else { return .stop }
            let request: AgePredicateProofRequest
            do {
                request = try AgePredicateProofRequest.decodeOnlineAge(from: text)
            } catch {
                return .keepScanning(status: error.localizedDescription)
            }
            latch.fired = true
            Task { @MainActor in showConsent(for: request, on: navigationController) }
            return .stop
        }
        navigationController?.pushViewController(scanner, animated: true)
    }

    private static func showConsent(for request: AgePredicateProofRequest,
                                    on navigationController: UINavigationController?) {
        guard let navigationController else { return }
        let source = request.credentialSource == .twdiw
            ? NSLocalizedString("government wallet card", comment: "age proof")
            : NSLocalizedString("self-issued MyData document", comment: "age proof")
        let message = String(
            format: NSLocalizedString(
                "The checker asks whether you are at least %d.\n\nPurpose: %@\nSource: %@\n\nYour birth date and card never leave this phone.",
                comment: "age proof consent"),
            request.minimumAge, request.purpose, source)
            + "\n\n" + String(
                format: NSLocalizedString("The finished proof will be sent to %@.", comment: "age proof consent"),
                request.responseURL?.host ?? "")
        let alert = UIAlertController(
            title: NSLocalizedString("Create a private age proof?", comment: "age proof"),
            message: message,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            navigationController.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Create proof", comment: "age proof"),
                                      style: .default) { _ in
            var stack = navigationController.viewControllers
            if stack.last is QRScanningViewController { stack.removeLast() }
            stack.append(AgePredicateProofSendViewController(request: request))
            navigationController.setViewControllers(stack, animated: true)
        })
        navigationController.topViewController?.present(alert, animated: true)
    }
}

@MainActor
final class AgePredicateProofSendViewController: UIViewController {

    private let request: AgePredicateProofRequest
    private let engine: any AgePredicateProofEngine
    private let webClient: AgePredicateProofWebClient
    /// Set the moment a web submission starts, so a failure on the way records
    /// the transport that was attempted rather than 「local」.
    private var usedWeb = false
    private var webOutcome: AgePredicateProofWebOutcome?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var createStartedAt: UInt64?
    private var transportStartedAt: UInt64?
    private var createdPackage: AgePredicateProofPackage?
    private var runRecordWritten = false
    private var creationTask: Task<Void, Never>?

    init(request: AgePredicateProofRequest,
         engine: any AgePredicateProofEngine = AgePredicateProofEngineAssembly.make(),
         webClient: AgePredicateProofWebClient = AgePredicateProofWebClient()) {
        self.request = request
        self.engine = engine
        self.webClient = webClient
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("Private age proof", comment: "age proof")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        createStartedAt = VerificationClock.now()
        createProof()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        creationTask?.cancel()
    }

    private func buildInterface() {
        view.backgroundColor = .systemGroupedBackground
        spinner.startAnimating()
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = NSLocalizedString("Creating the proof on this phone…", comment: "age proof")
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.text = NSLocalizedString(
            "Only the yes/no statement is returned. The hidden birth date, card and proving files stay here.",
            comment: "age proof")
        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("Done", comment: "")
        configuration.cornerStyle = .large
        doneButton.configuration = configuration
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, titleLabel, detailLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    private func createProof() {
        creationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try request.onlineAgeResponseURL()
                let store = try CredentialStore()
                let material = try AgePredicateCredentialProvider(
                    holder: HolderPresentation(store: store)).material(for: request.credentialSource)
                let package = try await engine.prove(
                    request: request,
                    credential: material.sdJWT,
                    issuerDID: material.issuerDID,
                    issuerPublicKeyX963: material.issuerPublicKeyX963,
                    holder: material.holderKey,
                    cacheKey: material.cacheKey,
                    assetProgress: { [weak self] fraction in
                        Task { @MainActor in
                            self?.detailLabel.text = String(
                                format: NSLocalizedString("Preparing private proof files… %d%%", comment: "age proof"),
                                Int((fraction * 100).rounded()))
                        }
                    })
                try Task.checkCancellation()
                try package.validate(answering: request)
                createdPackage = package
                let responseURL = try request.onlineAgeResponseURL()
                try await sendOverWeb(package, to: responseURL)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                showFailure(error)
            }
        }
    }

    /// The web checker's path: one HTTPS POST to the allow-listed website in the
    /// request, then its verdict — the website did the checking, this phone
    /// only reports what it said. Timings come back with the verdict so the
    /// holder's record carries the same numbers the website shows.
    private func sendOverWeb(_ package: AgePredicateProofPackage, to url: URL) async throws {
        usedWeb = true
        transportStartedAt = VerificationClock.now()
        titleLabel.text = NSLocalizedString("Proof ready", comment: "age proof")
        detailLabel.text = String(
            format: NSLocalizedString("Sending it to the checker's website %@…", comment: "age proof"),
            url.host ?? "")
        let outcome = try await webClient.submit(package, to: url)
        try Task.checkCancellation()
        webOutcome = outcome
        spinner.stopAnimating()
        if outcome.verdict.accepted {
            titleLabel.text = String(
                format: NSLocalizedString("The website verified the proof: at least %d", comment: "age proof"),
                request.minimumAge)
            detailLabel.text = NSLocalizedString("No birth date or card data was sent.", comment: "age proof")
                + "\n" + Self.timingSummary(package: package, outcome: outcome)
            Bonds.Haptic.delivered()
        } else {
            titleLabel.text = NSLocalizedString("The website did not accept the proof", comment: "age proof")
            detailLabel.text = outcome.verdict.reason.map { UntrustedText($0, limit: 200).text }
                ?? NSLocalizedString("The zero-knowledge proof did not verify.", comment: "age proof")
        }
        doneButton.isHidden = false
        recordRun(succeeded: outcome.verdict.accepted)
    }

    private static func timingSummary(package: AgePredicateProofPackage,
                                      outcome: AgePredicateProofWebOutcome) -> String {
        let verify = outcome.verdict.timingMs?.verify
        return String(
            format: NSLocalizedString("Proof creation %@ + %@ ms · website verification %@ ms · round trip %@ ms",
                                      comment: "age proof web timing"),
            Self.number(package.prepareMilliseconds),
            Self.number(package.showMilliseconds),
            verify.map(Self.number) ?? "—",
            Self.number(outcome.roundTripMilliseconds))
    }

    private static func number(_ value: UInt64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func showFailure(_ error: Error) {
        spinner.stopAnimating()
        titleLabel.text = NSLocalizedString("The proof was not sent", comment: "age proof")
        detailLabel.text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        doneButton.isHidden = false
        recordRun(succeeded: false)
    }

    private func recordRun(succeeded: Bool) {
        guard !runRecordWritten else { return }
        runRecordWritten = true
        let completed = VerificationClock.now()
        let started = createStartedAt ?? completed
        let transportStarted = transportStartedAt
        let package = createdPackage
        let transport: VerificationRunRecord.Transport = usedWeb ? .https : .local
        let record = VerificationRunRecord(
            flow: .privateAgeProof,
            role: .holder,
            credentialKind: request.credentialSource == .twdiw
                ? .governmentWallet : .selfIssued,
            transport: transport,
            succeeded: succeeded,
            preparationMilliseconds: package.map {
                $0.prepareMilliseconds + $0.showMilliseconds
            },
            transportMilliseconds: webOutcome?.roundTripMilliseconds ?? transportStarted.map {
                VerificationClock.milliseconds(from: $0, to: completed)
            },
            // The website's own verification figure, carried back with the
            // verdict returned by the online verifier.
            verificationMilliseconds: webOutcome?.verdict.timingMs?.verify,
            endToEndMilliseconds: VerificationClock.milliseconds(
                from: started, to: completed),
            proofPrepareMilliseconds: package?.prepareMilliseconds,
            proofShowMilliseconds: package?.showMilliseconds,
            proofPrepareWasCached: package?.prepareWasCached,
            payloadBytes: package.flatMap { try? UInt64($0.encoded().count) },
            correlationToken: VerificationRunRecord.correlationToken(
                for: request.serviceID.uuidString),
            qrFallbackWasVisible: false)
        try? VerificationRunStore.shared.append(record)
    }

    @objc private func done() { navigationController?.popViewController(animated: true) }
}
