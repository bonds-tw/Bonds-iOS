import UIKit

/// Explicit online preparation, separate from the nonce-to-verdict interval.
final class OfflinePreparationViewController: UIViewController {
    private let status = UILabel()
    private let trustButton = UIButton(type: .system)
    private var task: Task<Void, Never>?
    private var operationID: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Prepare offline checking", comment: "offline preparation")
        view.backgroundColor = .systemGroupedBackground
        let explanation = UILabel()
        explanation.text = NSLocalizedString("Before disconnecting, save issuer trust data on the checking device. Offline document checks use QR codes and Bluetooth. The checker does not need a copy of your cards. Current revocation status cannot be checked while offline.", comment: "offline preparation")
        for label in [explanation, status] {
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
        }
        configure(trustButton, "Save issuer trust", #selector(prepareTrust))
        let stack = UIStackView(arrangedSubviews: [explanation, trustButton, status])
        stack.axis = .vertical
        stack.spacing = 20
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        if let snapshots = try? OfflineIssuerTrustStore().registrySnapshots(),
           let date = snapshots.map(\.verifiedAt).min() {
            status.text = String(format: NSLocalizedString("Saved %d issuer records. Oldest check: %@. This does not establish current card revocation status.", comment: "offline preparation"),
                                 snapshots.count, date.formatted(date: .abbreviated, time: .shortened))
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        operationID = nil
        task?.cancel()
    }

    private func configure(_ button: UIButton, _ title: String, _ action: Selector) {
        var config = UIButton.Configuration.bordered()
        config.title = NSLocalizedString(title, comment: "offline preparation")
        config.titleLineBreakMode = .byWordWrapping
        button.configuration = config
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> String) {
        task?.cancel()
        let id = UUID()
        operationID = id
        for button in [trustButton] { button.isEnabled = false }
        status.text = NSLocalizedString("Preparing… Keep this screen open.", comment: "offline preparation")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if operationID == id { operationID = nil }
                for button in [trustButton] { button.isEnabled = true }
            }
            do {
                let message = try await operation()
                try Task.checkCancellation()
                status.text = message
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                status.text = OfflineVerificationPreparation.failureMessage(for: error)
            }
        }
    }

    @objc private func prepareTrust() {
        run { [self] in
            let id = operationID
            let count = try await OfflineVerificationPreparation.refreshTrust { [self] completed, total in
                Task { @MainActor [self] in
                    guard operationID == id else { return }
                    status.text = String(format: NSLocalizedString("Checking issuer trust… %d of %d. Keep this screen open.", comment: "offline preparation"), completed, total)
                }
            }
            return String(format: NSLocalizedString("Saved %d issuer records. Only matching API and blockchain records can be used offline; current card revocation remains unknown.", comment: "offline preparation"), count)
        }
    }

}
