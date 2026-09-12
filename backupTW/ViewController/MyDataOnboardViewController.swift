//
//  MyDataOnboardViewController.swift
//  backupTW
//
//  Created by Denken Chen on 2025/8/11.
//

import UIKit

private let reuseIdentifier = "MyDataOnboardCell"

class MyDataOnboardViewController: UICollectionViewController {

    private enum Section: Int, CaseIterable {
        case cover, guidance, profile, data
    }
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    /// Block unavailable builds before requesting identity data.
    private var coverItem: Item
    private var items: [Item]
    private var parsedModel: NationalIDModel?
    private var signingInProgress = false
    private var checkingReadiness = false
    private var signingTask: Task<Void, Never>?

    /// National ID creation signs parsed details; other imports archive the original.
    private let documentType: MyDataDocumentType

    private var isNationalID: Bool { documentType.id == MyDataDocumentRegistry.nationalID.id }
    private var canProceed: Bool { !isNationalID || CredentialIssuanceAssembly.isAvailable }

    private var guidanceItems: [Item] {
        var rows = [
            Item(image: UIImage(systemName: "1.circle.fill"),
                 title: NSLocalizedString("Fill in your MyData details", comment: "MyData flow step"),
                 secondaryText: NSLocalizedString("Saved details can be filled for you on the official MyData page.", comment: "MyData flow step"),
                 identifier: "mydata.step.details"),
            Item(image: UIImage(systemName: "2.circle.fill"),
                 title: NSLocalizedString("Approve in 行動自然人憑證", comment: "MyData flow step"),
                 secondaryText: NSLocalizedString("Follow the instructions on the MyData page to approve the request.", comment: "MyData flow step"),
                 identifier: "mydata.step.certificate"),
            Item(image: UIImage(systemName: "3.circle.fill"),
                 title: NSLocalizedString("Return to Bonds", comment: "MyData flow step"),
                 secondaryText: NSLocalizedString("The MyData page stays open and continues after the signature.", comment: "MyData flow step"),
                 identifier: "mydata.step.return"),
        ]
        let finalText = isNationalID ? NSLocalizedString("Download your details, unlock the PDF if asked, and review them in Bonds before signing.", comment: "") : documentType.estimatedMinutes.map {
            String(format: NSLocalizedString("This document may take about %lld minutes. You can leave and later continue from MyData personal documents.", comment: "MyData slow document step"), Int64($0))
        } ?? NSLocalizedString("Download the completed file; it is then sealed in the data vault.", comment: "MyData flow step")
        rows.append(Item(image: UIImage(systemName: "4.circle.fill"),
                         title: NSLocalizedString("Download or continue later", comment: "MyData flow step"),
                         secondaryText: finalText,
                         identifier: "mydata.step.download"))
        if isNationalID {
            rows.append(Item(image: UIImage(systemName: "5.circle.fill"), title: NSLocalizedString("Sign and create card", comment: ""), secondaryText: NSLocalizedString("Approve a separate Bonds signature in 行動自然人憑證. Return to Bonds and wait for the card-saved confirmation.", comment: ""), identifier: "mydata.step.sign"))
        }
        return rows
    }

    private var profileItem: Item {
        let saved = MyDataAutofillProfileStore.load() != nil
        return Item(
            image: UIImage(systemName: saved ? "checkmark.shield.fill" : "person.crop.circle.badge.plus"),
            title: NSLocalizedString("Remember MyData details on this iPhone", comment: "MyData profile row"),
            secondaryText: saved
                ? NSLocalizedString("Saved in Keychain · tap to change or forget", comment: "MyData profile row")
                : NSLocalizedString("Optional · saves repeated ID number and birth-date entry", comment: "MyData profile row"),
            identifier: "mydata.profile")
    }

    init(documentType: MyDataDocumentType = MyDataDocumentRegistry.nationalID) {
        self.documentType = documentType
        if documentType.id == MyDataDocumentRegistry.nationalID.id {
            self.coverItem = CredentialIssuanceAssembly.isAvailable
                ? Item(image: Self.statusImage("person.text.rectangle", colour: .tintColor),
                       title: NSLocalizedString("Create my card from MyData", comment: ""),
                       secondaryText: NSLocalizedString("First authorize MyData to download your details. Then review them and sign separately to create your Bonds card. This does not replace a government-issued ID.", comment: ""))
                : Item(image: Self.statusImage("xmark.shield.fill", colour: .systemOrange),
                       title: NSLocalizedString("This version cannot create a document", comment: ""),
                       secondaryText: NSLocalizedString("Signing needs a service this build cannot reach, so the document could not be created even after fetching your data. Nothing is fetched.", comment: ""))
            self.items = [
                Item(title: NSLocalizedString("Nationality", comment: ""), secondaryText: ""),
                Item(title: NSLocalizedString("Unified No.", comment: ""), secondaryText: ""),
                Item(title: NSLocalizedString("Name", comment: ""), secondaryText: ""),
                Item(title: NSLocalizedString("Birth date", comment: ""), secondaryText: ""),
                Item(title: NSLocalizedString("Address of household", comment: ""), secondaryText: ""),
            ]
        } else {
            self.coverItem = Item(
                image: Self.statusImage("tray.and.arrow.down.fill", colour: .tintColor),
                title: String(format: NSLocalizedString("Import %@", comment: "MyData document import title"), documentType.title),
                secondaryText: NSLocalizedString("Download this document from Taiwan's MyData service and keep the original in your on-device data vault.", comment: ""))
            self.items = [
                Item(title: NSLocalizedString("Document type", comment: ""), secondaryText: documentType.title),
                Item(title: NSLocalizedString("Source", comment: ""), secondaryText: NSLocalizedString("Taiwan MyData", comment: "")),
                Item(title: NSLocalizedString("Storage", comment: ""), secondaryText: NSLocalizedString("Original file, protected on this phone and excluded from backups", comment: "")),
            ]
        }
        let layout = UICollectionViewCompositionalLayout() { sectionIndex, layoutEnvironment in
            let shouldShowHeaderFooter = (sectionIndex != 0)
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.headerMode = shouldShowHeaderFooter ? .supplementary : .none
            configuration.footerMode = shouldShowHeaderFooter ? .supplementary : .none
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            return section
        }
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = isNationalID ? NSLocalizedString("Create my card", comment: "") : documentType.title
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        // Configuration is checked here; live service acceptance is checked on Continue.
        let proceed = UIBarButtonItem(title: NSLocalizedString("Continue", comment: ""),
                                      style: .done, target: self, action: #selector(nextAction))
        proceed.isEnabled = canProceed
        navigationItem.rightBarButtonItem = proceed
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        collectionView.allowsSelection = true

        configureDataSource()
        applySnapshot()
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, indexPath, item in
            let section = self.dataSource.sectionIdentifier(for: indexPath.section)
            let isCover = section == .cover
            // The household address is structurally a long field, even when a
            // particular test value happens to be short.  Keeping it in the
            // trailing-value layout makes the value fight the title for width
            // and produces the clipped row seen on an iPhone.  Other long
            // MyData values get the same stacked treatment automatically.
            let isHouseholdAddress = self.isNationalID && section == .data && indexPath.item == 4
            let usesStackedValue = isHouseholdAddress
                || item.secondaryText.count > 18
                || item.secondaryText.contains("\n")
            var content = isCover || usesStackedValue
                ? UIListContentConfiguration.subtitleCell()
                : UIListContentConfiguration.valueCell()

            if isCover {
                // Keep the result readable as a compact status card. Embedding a
                // hero symbol and emoji inside large attributed text made the
                // cell several hundred points tall and broke at real-device
                // Dynamic Type sizes.
                content.image = item.image
                // 40pt cap and token margins (design system §4): the 52pt frame
                // read as an illustration rather than a status mark, and 20/18
                // margins were off the 4pt grid.
                content.imageProperties.maximumSize = CGSize(width: 40, height: 40)
                content.textProperties.font = .preferredFont(forTextStyle: .title2)
                content.textProperties.color = .label
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                    top: Bonds.Space.l, leading: Bonds.Space.l,
                    bottom: Bonds.Space.l, trailing: Bonds.Space.l)
            } else {
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            }
            content.text = item.title
            content.secondaryText = item.secondaryText
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel
            content.textToSecondaryTextVerticalPadding = isCover ? 6 : 3
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = isCover
                ? "mydataOnboard.cover"
                : section == .profile ? "mydataOnboard.profile"
                : "mydataOnboard.\(section?.rawValue ?? -1).\(indexPath.item)"
            cell.accessories = section == .profile ? [.disclosureIndicator()] : []
            // Interaction stays ON: `isUserInteractionEnabled = false` made the
            // list cell render its *disabled* appearance, so every step title
            // sat in grey under a lighter body — a wizard that looked switched
            // off (回報 2026-09-02). Which rows respond is decided by
            // `shouldSelectItemAt`, which greys nothing.
            cell.isUserInteractionEnabled = true
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { headerView, elementKind, indexPath in
            var content = headerView.defaultContentConfiguration()
            switch self.dataSource.sectionIdentifier(for: indexPath.section) {
            case .guidance:
                content.text = NSLocalizedString("What happens next", comment: "MyData guidance header")
            case .profile:
                content.text = NSLocalizedString("Make the next visit easier", comment: "MyData profile header")
            case .data:
                content.text = NSLocalizedString("Document information", comment: "")
            default:
                content.text = nil
            }
            headerView.contentConfiguration = content
        }
        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { footerView, elementKind, indexPath in
            var content = footerView.defaultContentConfiguration()
            switch self.dataSource.sectionIdentifier(for: indexPath.section) {
            case .profile:
                content.text = NSLocalizedString("Remembered details are stored in the iOS Keychain on this iPhone and filled only on mydata.nat.gov.tw.", comment: "MyData profile footer")
            case .data:
                content.text = self.isNationalID
                    ? NSLocalizedString("Your downloaded details stay on this iPhone. Signing sends your ID number and a digest of the card to the signing service.", comment: "")
                    : NSLocalizedString("All information are stored only on your phone.", comment: "")
            default:
                content.text = nil
            }
            footerView.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            } else {
                return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
            }
        }
    }

    /// Set when the flow has delivered its result. The 「接下來會發生什麼」
    /// steps and the remember-my-details invitation describe a journey that is
    /// over — keeping them under a green 「已儲存」 card read as more work to do
    /// (回報 2026-09-02). Done means the screen shows what was done.
    private var flowIsFinished = false

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.cover])
        snapshot.appendItems([coverItem])
        if !flowIsFinished && parsedModel == nil {
            snapshot.appendSections([.guidance])
            snapshot.appendItems(guidanceItems)
            snapshot.appendSections([.profile])
            snapshot.appendItems([profileItem])
        }
        snapshot.appendSections([.data])
        for item in items {
            snapshot.appendItems([item])
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    override func collectionView(_ collectionView: UICollectionView,
                                 shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.sectionIdentifier(for: indexPath.section) == .profile
    }

    override func collectionView(_ collectionView: UICollectionView,
                                 didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard dataSource.sectionIdentifier(for: indexPath.section) == .profile else { return }
        navigationController?.pushViewController(
            MyDataProfileViewController { [weak self] in self?.applySnapshot() }, animated: true)
    }

    @objc private func cancel() {
        guard !signingInProgress else { return }
        if parsedModel != nil && !flowIsFinished {
            let alert = UIAlertController(title: NSLocalizedString("Discard this card draft?", comment: ""), message: NSLocalizedString("These details are only kept for this visit. Leaving now means downloading them again next time.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Keep reviewing", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Discard", comment: ""), style: .destructive) { [weak self] _ in self?.dismiss(animated: true) })
            present(alert, animated: true)
        } else { dismiss(animated: true) }
    }

    @objc private func nextAction() {
        // Belt as well as braces. The disabled button is what a person sees; this
        // is what holds if some future path invokes the action another way —
        // a keyboard shortcut, a restored state, a test. The thing being
        // guarded is somebody's national ID number, so it is guarded twice.
        guard canProceed, !checkingReadiness else { return }
        guard isNationalID else { openMyData(); return }
        checkingReadiness = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.title = NSLocalizedString("Checking service…", comment: "")
        Task { [weak self] in
            do {
                try await SigningReadiness.check()
                guard let self else { return }
                self.checkingReadiness = false
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.navigationItem.rightBarButtonItem?.title = NSLocalizedString("Continue", comment: "")
                guard self.viewIfLoaded?.window != nil else { return }
                self.openMyData()
            } catch {
                guard let self else { return }
                self.checkingReadiness = false
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.navigationItem.rightBarButtonItem?.title = NSLocalizedString("Try again", comment: "")
                self.coverItem = Item(image: Self.statusImage("exclamationmark.triangle.fill", colour: .systemOrange), title: NSLocalizedString("Cannot start card creation", comment: ""), secondaryText: error.localizedDescription)
                self.applySnapshot()
            }
        }
    }

    private func openMyData() {

        // The web controller resolves the entry URL from the document's item path
        // (guarded non-nil upstream) and archives the original for vault documents.
        let vc = MyDataWebViewController(documentType: documentType, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .nationalID(let nationalIDModel):
                self.showParsedDocument(nationalIDModel)
            case .vaultDocument(let entry):
                self.finishVaultImport(entry)
            }
        })
        // Pushed, not presented. This flow used to be a sheet on a
        // fullScreen modal on (from Settings) another modal, with the
        // password alert as a fourth layer — the deepest stack in the app.
        // One navigation container, push sequence (design system §10.1):
        // Back is the escape hatch, and the wizard is still underneath
        // when the web step completes.
        if let nav = navigationController {
            nav.pushViewController(vc, animated: true)
        } else {
            present(vc, animated: true)
        }
    }

    // MARK: - Issuance

    private func finishVaultImport(_ entry: MyDataVaultArchive.Entry) {
        flowIsFinished = true
        coverItem = Item(
            image: Self.statusImage("checkmark.circle.fill", colour: .systemGreen),
            title: NSLocalizedString("Saved in MyData vault", comment: ""),
            secondaryText: NSLocalizedString("The original file is protected on this phone. It was not turned into national-ID data or a self-issued credential.", comment: ""))
        items = [
            Item(title: NSLocalizedString("Document type", comment: ""), secondaryText: documentType.title),
            Item(title: NSLocalizedString("Source", comment: ""), secondaryText: NSLocalizedString("Taiwan MyData", comment: "")),
            Item(title: NSLocalizedString("File format", comment: ""), secondaryText: entry.fileExtension.isEmpty ? NSLocalizedString("Unknown", comment: "") : entry.fileExtension.uppercased()),
            Item(title: NSLocalizedString("File fingerprint", comment: ""), secondaryText: WalletCardMask.middleEllipsis(entry.sha256)),
        ]
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(cancel))
        applySnapshot()
    }

    /// Download success requires a separate review and explicit signature.
    func showParsedDocument(_ nationalIDModel: NationalIDModel) {
        parsedModel = nationalIDModel
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
        coverItem = Item(
            image: Self.statusImage("signature", colour: .tintColor),
            title: NSLocalizedString("Review your downloaded details", comment: ""),
            secondaryText: NSLocalizedString("MyData authorization is complete. Your Bonds card is not created yet. Check these details, then approve a separate signature in 行動自然人憑證 and return here.", comment: ""))
        items = [
            Item(title: NSLocalizedString("Nationality", comment: ""),
                 secondaryText: nationalIDModel.nationality ?? NSLocalizedString("Unknown", comment: "")),
            Item(title: NSLocalizedString("Unified No.", comment: ""),
                 secondaryText: nationalIDModel.unifiedNo ?? NSLocalizedString("Unknown", comment: "")),
            Item(title: NSLocalizedString("Name", comment: ""),
                 secondaryText: nationalIDModel.name ?? NSLocalizedString("Unknown", comment: "")),
            Item(title: NSLocalizedString("Birth date", comment: ""),
                 secondaryText: nationalIDModel.birthdate ?? NSLocalizedString("Unknown", comment: "")),
            Item(title: NSLocalizedString("Address of household", comment: ""),
                 secondaryText: nationalIDModel.addressOfHousehold ?? NSLocalizedString("Unknown", comment: "")),
        ]
        applySnapshot()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Sign and create card", comment: ""), style: .done, target: self, action: #selector(startSigning))
    }

    @objc private func startSigning() {
        guard !signingInProgress, let model = parsedModel else { return }
        signingInProgress = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Stop waiting", comment: ""), style: .plain, target: self, action: #selector(stopWaiting))
        navigationItem.rightBarButtonItem = nil
        coverItem = Item(image: Self.statusImage("signature", colour: .tintColor), title: NSLocalizedString("Waiting for you to sign in 行動自然人憑證", comment: ""), secondaryText: NSLocalizedString("Approve the Bonds card signature, then return here. Wait for the saved confirmation. This can take up to 10 minutes; keep Bonds open.", comment: ""))
        applySnapshot()
        issueCredential(for: model)
    }

    @objc private func stopWaiting() {
        let alert = UIAlertController(title: NSLocalizedString("Stop waiting for this signature?", comment: ""), message: NSLocalizedString("This stops Bonds from waiting. It does not cancel the request in 行動自然人憑證. Cancel that request there before starting another signature.", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Keep waiting", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Stop waiting", comment: ""), style: .destructive) { [weak self] _ in self?.signingTask?.cancel() })
        present(alert, animated: true)
    }

    @objc private func retrySigning() {
        let alert = UIAlertController(title: NSLocalizedString("Start a new signature?", comment: ""), message: NSLocalizedString("The previous attempt did not save a card. If a request is still visible in 行動自然人憑證, cancel it or wait for it to expire first. Your downloaded details will be reused without another MyData download.", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Start new signature", comment: ""), style: .default) { [weak self] _ in self?.startSigning() })
        present(alert, animated: true)
    }

    /// Turns the parsed document into a credential this device has signed, and
    /// writes it to disk.
    ///
    /// Off the main thread on purpose. Creating the device key is a Keychain
    /// round trip — a Secure Enclave one on real hardware — and the write goes
    /// through Data Protection. Neither is slow enough to notice on a good day,
    /// and both are exactly the kind of call that stalls for a second on a bad
    /// one, right when a sheet is animating away.
    private func issueCredential(for nationalIDModel: NationalIDModel) {
        // Stored under the document type's id — 「national-id」 for the national ID,
        // 「mydata-…」 for a vault document — which is what routes it to the right
        // section (CardInventory classifies self-issued docs by id). The id is
        // stable per document type on purpose: re-running onboarding replaces the
        // previous credential rather than leaving a stale twin on disk beside it.
        let credentialID = documentType.id
        // UIKit transport detection belongs to this main-actor method, not the
        // detached task below. A missing local app selects remote push.
        let selectedTransport = TWFidOTransportSelection.automatic()

        // Key creation and storage stay off the main actor. Cancellation keeps the review screen.
        signingTask = Task.detached(priority: .userInitiated) { [weak self] in
            // `Result(catching:)` has no `async` overload, so the two arms are
            // written out rather than smuggled through a synchronous closure.
            let result: Result<Void, Error>
            do {
                guard let issuance = CredentialIssuanceAssembly.make(transport: selectedTransport) else {
                    // Deliberately *not* `SPCredentialError.requiresBackend.description`.
                    // That type is `CustomStringConvertible` rather than
                    // `LocalizedError` on purpose — its own doc says its audience
                    // is whoever reads the log — and piping it here would put
                    // 「sp_checksum must be computed by the bonds-tw backend」 in
                    // front of somebody who was trying to back up their ID card.
                    throw CredentialIssuanceError.signingUnavailable(
                        message: NSLocalizedString("This version cannot sign documents yet. Signing has to go through the bonds-tw service, which is not available in this build.",
                                                   comment: ""))
                }
                // A national ID owns its key. The app installation has a separate
                // WalletIdentity DID, and every TWDIW card already follows the
                // same per-credential rule through HolderKeyring.
                let keyring = HolderKeyring.app()
                let documentKey = try keyring.newKey()
                do {
                    let subjectDID = try DIDKey.did(fromP256PublicKeyX963: documentKey.publicKeyX963)
                    let signed = try await issuance.issue(nationalIDModel,
                                                          subjectDID: subjectDID,
                                                          issuerKey: documentKey)
                    try Task.checkCancellation()
                    try CredentialStore().save(jws: try signed.serialized(), id: credentialID)
                } catch {
                    Self.destroyProvisionalKey(documentKey, in: keyring)
                    throw error
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }

            await MainActor.run { self?.finishIssuance(result) }
        }
    }

    private static func destroyProvisionalKey(_ key: DeviceKey, in keyring: HolderKeyring) {
        guard let entries = try? keyring.entries() else { return }
        for entry in entries where entry.publicKeyX963 == key.publicKeyX963 && !entry.isLegacy {
            try? DeviceKey.deleteKey(tag: entry.tag, installRecord: nil)
        }
    }

    func finishIssuance(_ result: Result<Void, Error>) {
        signingInProgress = false
        signingTask = nil
        switch result {
        case .success:
            flowIsFinished = true
            navigationController?.isModalInPresentation = false
            isModalInPresentation = false
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(cancel))
            coverItem = Item(
                image: Self.statusImage("checkmark.seal.fill", colour: .systemGreen),
                title: NSLocalizedString("Your card has been saved", comment: ""),
                secondaryText: "")
        case .failure(let error):
            // The five fields below are still on screen and still correct — what
            // failed is the signing — so the list is corrected rather than
            // cleared. Putting the reason in the row as well as in the alert is
            // not redundancy for its own sake: the alert can be swallowed if the
            // MyData sheet has not finished animating out, and a user left with
            // no credential and no explanation would reasonably assume they had
            // one.
            coverItem = Item(
                image: Self.statusImage("exclamationmark.triangle.fill", colour: .systemOrange),
                title: NSLocalizedString("The document could not be signed", comment: ""),
                secondaryText: error is CancellationError ? NSLocalizedString("Waiting stopped. No card was saved by this attempt. Cancel any pending request in 行動自然人憑證 before retrying.", comment: "") : error.localizedDescription)
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Retry signing", comment: ""), style: .done, target: self, action: #selector(retrySigning))
            if !(error is CancellationError) { presentIssuanceFailure(error) }
        }
        applySnapshot()
    }

    /// The cover card's status glyph.
    ///
    /// Two corrections (回報 2026-09-02): the glyph was drawn at 34pt semibold
    /// inside a 52pt frame — a banner, not a status mark — and `.tintColor`
    /// baked through `withTintColor` outside any view resolves against no
    /// trait, which rendered the accent-coloured covers grey. `title1` scale
    /// sits the mark against the title it accompanies, and the named accent
    /// colour keeps its dynamic light/dark resolution through the bake.
    private static func statusImage(_ name: String, colour: UIColor) -> UIImage? {
        let resolved = colour == .tintColor
            ? (UIColor(named: "AccentColor") ?? colour)
            : colour
        return UIImage(systemName: name,
                       withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1,
                                                                      scale: .large))?
            .withTintColor(resolved, renderingMode: .alwaysOriginal)
    }

    #if DEBUG
    /// A deterministic, non-personal fixture for layout and screenshot tests.
    /// It exercises the same post-signing state that previously expanded into a
    /// broken hero card on real devices.
    func seedSuccessfulNationalIDPreviewForUITest(completed: Bool = true) {
        guard isNationalID else { return }
        showParsedDocument(NationalIDModel(
            nationality: "中華民國（臺灣）",
            unifiedNo: "TEST000001",
            name: "版面測試",
            birthdate: "民國 100 年 01 月 01 日",
            addressOfHousehold: "測試市測試區第一里第二鄰測試路三段四十二巷五號十二樓之十"))
        if completed { finishIssuance(.success(())) }
    }
    #endif

    /// Reports a signing failure once the screen is actually able to show it.
    ///
    /// `MyDataWebViewController` asks to be dismissed in the same run-loop turn
    /// that it hands over the parsed document, so when issuance finishes the
    /// sheet may still be on screen or still animating out. UIKit does not queue
    /// a presentation attempted in that window, it drops it. Retrying is bounded
    /// so that "the stack never settles" — including the case where the user
    /// dismissed this screen and there is nothing left to present on — decays
    /// into no alert rather than a timer that runs forever.
    private func presentIssuanceFailure(_ error: Error, attemptsRemaining: Int = 20) {
        guard presentedViewController == nil, viewIfLoaded?.window != nil else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.presentIssuanceFailure(error, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("The document could not be signed", comment: ""),
            // Every error reaching here conforms to LocalizedError, so this is the
            // module's own sentence. The underlying OSStatus and DID stay out of
            // it — an error string is one of the easier ways for an identifier to
            // end up in a screenshot or a crash report.
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .default))
        present(alert, animated: true)
    }
}
