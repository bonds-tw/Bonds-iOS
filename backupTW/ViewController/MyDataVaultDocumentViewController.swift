//
//  MyDataVaultDocumentViewController.swift
//  backupTW
//

import PDFKit
import UIKit

enum MyDataVaultPreviewError: Error, Equatable {
    case originalMissing
    case unsupportedFormat(String)
    case noPDF
}

extension MyDataVaultPreviewError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .originalMissing:
            return NSLocalizedString("The original file is no longer stored on this phone.", comment: "")
        case .unsupportedFormat(let format):
            return String(format: NSLocalizedString(
                "This version cannot preview %@ files yet. The protected original is still stored.",
                comment: "MyData vault preview unsupported"),
                          UntrustedText.term(format.isEmpty ? "?" : format.uppercased()).text)
        case .noPDF:
            return NSLocalizedString("The stored file does not contain a PDF this version can show.", comment: "")
        }
    }
}

/// The holder-facing side of one raw MyData original.
///
/// A vault document is deliberately not a credential. This screen therefore
/// never shows an issuer, a DID, or a 「present」 action: it shows what the phone
/// actually has — the source, format, import time and fingerprint — and lets the
/// holder reopen, replace or delete that exact original.
final class MyDataVaultDocumentViewController: UICollectionViewController {

    private struct Row: Hashable {
        enum Kind: Hashable { case fact, viewOriginal, share, credentialUseCases, parsePreview, replace, delete }
        let id: String
        let title: String
        let value: String
        let kind: Kind
    }

    private struct Group: Hashable {
        let id: String
        let title: String
        let rows: [Row]
    }

    private let documentID: String
    private let archive: MyDataVaultArchive
    private let onDeleted: (() -> Void)?
    private var document: MyDataVaultArchive.Document?
    private var integrity: MyDataVaultArchive.Integrity = .fileMissing
    private var groups: [Group] = []
    private var dataSource: UICollectionViewDiffableDataSource<Group, Row>!
    private var hasAppeared = false

    init(id: String, archive: MyDataVaultArchive, onDeleted: (() -> Void)? = nil) {
        self.documentID = id
        self.archive = archive
        self.onDeleted = onDeleted
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        configureDataSource()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from 「replace from MyData」 must show the new fingerprint and
        // import time rather than the values that were on screen before the sheet.
        if hasAppeared { reload() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    private func reload() {
        document = (try? archive.documents())?.first { $0.id == documentID }
        integrity = (try? archive.integrity(id: documentID)) ?? .fileMissing
        title = document?.entry?.displayName
            ?? MyDataDocumentRegistry.lookup(id: documentID)?.title
            ?? NSLocalizedString("MyData document", comment: "vault document detail title")
        applySnapshot()
    }

    private func buildGroups() -> [Group] {
        guard let document else {
            return [Group(id: "missing", title: "", rows: [
                Row(id: "missing", title: NSLocalizedString("Original file missing", comment: ""),
                    value: NSLocalizedString("This document is no longer stored on this phone.", comment: ""),
                    kind: .fact)
            ])]
        }

        let type = MyDataDocumentRegistry.lookup(id: document.id)
        let entry = document.entry
        let imported: String
        if let date = document.importedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            imported = formatter.string(from: date)
        } else {
            imported = NSLocalizedString("Unknown", comment: "")
        }

        let format = entry.flatMap { entry in
            entry.fileExtension.isEmpty
                ? nil
                : UntrustedText.term(entry.fileExtension.uppercased()).text
        } ?? NSLocalizedString("Unknown", comment: "")
        let facts = Group(id: "facts", title: NSLocalizedString("This document", comment: ""), rows: [
            Row(id: "type", title: NSLocalizedString("Document type", comment: ""),
                value: entry?.displayName ?? type?.title ?? UntrustedText.term(document.id).text, kind: .fact),
            Row(id: "source", title: NSLocalizedString("Source", comment: ""),
                value: NSLocalizedString("Taiwan MyData", comment: ""), kind: .fact),
            Row(id: "imported", title: NSLocalizedString("Imported", comment: ""),
                value: imported, kind: .fact),
            Row(id: "format", title: NSLocalizedString("File format", comment: ""),
                value: format, kind: .fact),
            Row(id: "fingerprint", title: NSLocalizedString("File fingerprint", comment: ""),
                value: entry?.sha256
                    ?? NSLocalizedString("Metadata missing", comment: ""),
                kind: .fact),
            Row(id: "integrity", title: NSLocalizedString("Integrity check", comment: ""),
                value: Self.integrityMessage(integrity), kind: .fact),
            Row(id: "answers", title: NSLocalizedString("Can answer", comment: "vault document: derivable claims"),
                value: Self.answersMessage(documentTypeID: type?.id
                    ?? entry?.displayName.flatMap(MyDataDocumentRegistry.knownDocument(in:))?.id),
                kind: .fact),
        ])

        let actions = Group(id: "actions", title: NSLocalizedString("Manage", comment: ""), rows: [
            Row(id: "view", title: NSLocalizedString("View original document", comment: ""),
                value: NSLocalizedString("Open the protected copy stored on this phone.", comment: ""),
                kind: .viewOriginal),
            Row(id: "share", title: NSLocalizedString("Export or share a copy", comment: "MyData vault action"),
                value: NSLocalizedString("Choose an iOS app or person. The exported copy leaves the vault.", comment: "MyData vault share warning"),
                kind: .share),
            Row(id: "credential-use-cases",
                title: NSLocalizedString("Selective-disclosure credential scenarios", comment: "MyData vault action"),
                value: NSLocalizedString("See what this document could prove without sharing the whole file.", comment: "MyData VC scenarios action"),
                kind: .credentialUseCases),
            Row(id: "replace", title: NSLocalizedString("Replace from MyData", comment: ""),
                value: NSLocalizedString("Download this document again and replace the stored original.", comment: ""),
                kind: .replace),
            Row(id: "delete", title: NSLocalizedString("Delete document", comment: ""),
                value: NSLocalizedString("Remove the original file and its fingerprint from this phone.", comment: ""),
                kind: .delete),
        ])
        #if DEBUG
        // Development only: run this build's parser over the stored original
        // and show what it read. This is how the real-document gate in
        // docs/mydata-vc-verifier-scenarios.md is checked on a phone — the
        // fields are shown once, in an alert, and not retained.
        let debug = Group(id: "debug", title: "[DEBUG]", rows: [
            Row(id: "parse-preview", title: "[DEBUG] Parse the original",
                value: "Runs the derivation parser and shows the fields it read.",
                kind: .parsePreview),
        ])
        return [facts, actions, debug]
        #else
        return [facts, actions]
        #endif
    }

    /// The questions this document can answer through a verifier's request,
    /// or the plain fact that it cannot yet.
    static func answersMessage(documentTypeID: String?) -> String {
        guard let documentTypeID,
              let type = MyDataDerivedCredentialType.lookup(documentTypeID: documentTypeID) else {
            return NSLocalizedString("No verifier question is defined for this document yet. It can be viewed and exported.",
                                     comment: "vault document: no derivation")
        }
        let questions = type.rules.map { MyDataDisclosureRule(id: $0, params: [:]).kindDescription }
        return questions.joined(separator: "、")
    }

    static func integrityMessage(_ integrity: MyDataVaultArchive.Integrity) -> String {
        switch integrity {
        case .verified:
            return NSLocalizedString("Verified — the file matches the fingerprint saved when it was imported.", comment: "")
        case .mismatch:
            return NSLocalizedString("Warning — the file no longer matches its saved fingerprint.", comment: "")
        case .metadataMissing:
            return NSLocalizedString("The original is present, but its fingerprint metadata is missing.", comment: "")
        case .fileMissing:
            return NSLocalizedString("The original file is missing.", comment: "")
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { cell, _, row in
            var content = cell.defaultContentConfiguration()
            content.text = row.title
            content.secondaryText = row.value.isEmpty ? nil : row.value
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel
            if row.id == "fingerprint" {
                let base = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                content.secondaryTextProperties.font = UIFontMetrics(forTextStyle: .footnote)
                    .scaledFont(for: base)
            }
            switch row.kind {
            case .fact:
                break
            case .viewOriginal, .share, .credentialUseCases, .parsePreview, .replace:
                content.textProperties.color = .tintColor
                cell.accessories = [.disclosureIndicator()]
            case .delete:
                content.textProperties.color = .systemRed
                content.image = UIImage(systemName: "trash")?.withTintColor(.systemRed,
                                                                              renderingMode: .alwaysOriginal)
            }
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "mydata.vault.\(row.id)"
        }
        dataSource = UICollectionViewDiffableDataSource<Group, Row>(collectionView: collectionView) {
            view, indexPath, row in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            var content = view.defaultContentConfiguration()
            content.text = self?.groups[indexPath.section].title
            view.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { view, kind, indexPath in
            kind == UICollectionView.elementKindSectionHeader
                ? view.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
                : nil
        }
    }

    private func applySnapshot() {
        groups = buildGroups()
        var snapshot = NSDiffableDataSourceSnapshot<Group, Row>()
        for group in groups {
            snapshot.appendSections([group])
            snapshot.appendItems(group.rows, toSection: group)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func collectionView(_ collectionView: UICollectionView,
                                 shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return false }
        return row.kind != .fact
    }

    override func collectionView(_ collectionView: UICollectionView,
                                 didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row.kind {
        case .fact: break
        case .viewOriginal: showOriginal()
        case .share: confirmShare()
        case .credentialUseCases: showCredentialUseCases()
        case .parsePreview: showParsePreview()
        case .replace: replaceFromMyData()
        case .delete: confirmDelete()
        }
    }

    private func showParsePreview(password: String? = nil) {
        #if DEBUG
        // Diagnostics first, verdict second: when the parser refuses, the alert
        // has to say *which* step refused — no type, no text layer, or text
        // without the expected labels — or the phone tells us nothing useful.
        var lines: [String] = []
        var text: String?
        let entry = document?.entry
        lines.append("file: \(entry?.fileExtension ?? "?") · name: \(entry?.displayName ?? "-")")
        var typeID = MyDataDocumentRegistry.lookup(id: documentID)?.id
            ?? entry?.displayName.flatMap(MyDataDocumentRegistry.knownDocument(in:))?.id
        do {
            let extracted = try MyDataVaultText.extract(id: documentID, archive: archive, password: password)
            text = extracted
            lines.append("text: \(extracted.count) chars, \(extracted.components(separatedBy: .newlines).count) lines")
            if typeID == nil {
                typeID = MyDataDocumentRegistry.knownDocument(in: extracted)?.id
                lines.append("type sniffed from text: \(typeID ?? "none")")
            } else {
                lines.append("type: \(typeID!)")
            }
            guard let typeID, let parser = MyDataDocumentParsers.parser(for: typeID) else {
                throw MyDataDocumentParserError.notThisDocument
            }
            let parsed = try parser.parse(text: extracted)
            lines.append("✓ " + parsed.parserVersion)
            lines.append(contentsOf: parsed.fields.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" })
            if !parsed.periods.isEmpty {
                lines.append("periods: " + parsed.periods.map { "\($0.start)…\($0.end ?? "now")" }.joined(separator: ", "))
            }
        } catch MyDataDocumentParserError.locked {
            // Sealed with the national ID number and none is stored: ask, retry.
            let prompt = UIAlertController(title: "[DEBUG] PDF is locked",
                                           message: lines.joined(separator: "\n") + "\nEnter the ID number (the PDF password).",
                                           preferredStyle: .alert)
            prompt.addTextField { $0.placeholder = "A123456789"; $0.autocapitalizationType = .allCharacters }
            prompt.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self, weak prompt] _ in
                self?.showParsePreview(password: prompt?.textFields?.first?.text)
            })
            prompt.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            present(prompt, animated: true)
            return
        } catch {
            lines.append("✗ \(error)")
        }
        if let text {
            lines.append("— first 300 chars —")
            lines.append(String(text.prefix(300)))
        }
        let message = lines.joined(separator: "\n")
        let alert = UIAlertController(title: "[DEBUG] Parse the original", message: message, preferredStyle: .alert)
        if let text {
            alert.addAction(UIAlertAction(title: "Copy full text", style: .default) { _ in
                UIPasteboard.general.string = message + "\n\n===== FULL TEXT =====\n" + text
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
        #endif
    }

    private func showOriginal() {
        do {
            let data = try Self.previewPDFData(id: documentID, archive: archive)
            guard let pdf = PDFDocument(data: data) else { throw MyDataVaultPreviewError.noPDF }
            navigationController?.pushViewController(
                MyDataVaultPDFViewController(title: title ?? "", document: pdf), animated: true)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    /// Returns PDF bytes without leaving a decrypted/extracted copy behind.
    /// Direct PDFs are read into memory. A zip is copied under a generated `.zip`
    /// name into `MyDataScratch`, vetted for zip-slip, unpacked, read, and purged
    /// before this method returns.
    static func previewPDFData(id: String, archive: MyDataVaultArchive) throws -> Data {
        guard let original = archive.originalURL(id: id) else {
            throw MyDataVaultPreviewError.originalMissing
        }
        let format = archive.entry(id: id)?.fileExtension.lowercased() ?? ""
        switch format {
        case "pdf":
            return try Data(contentsOf: original)
        case "zip":
            let scratch = MyDataScratch(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MyDataVaultPreview-\(UUID().uuidString)", isDirectory: true))
            defer { try? scratch.purge() }
            let zip = try scratch.downloadDestination()
            try Data(contentsOf: original).write(to: zip,
                                                 options: [.atomic, .completeFileProtectionUnlessOpen])
            do { return try scratch.pdfData(fromArchiveAt: zip) }
            catch { throw MyDataVaultPreviewError.noPDF }
        default:
            throw MyDataVaultPreviewError.unsupportedFormat(format)
        }
    }

    private func replaceFromMyData() {
        guard let document else { return }
        let type = MyDataDocumentRegistry.lookup(id: documentID)
            ?? MyDataDocumentRegistry.personalDocuments(
                replacing: documentID,
                title: document.entry?.displayName
                    ?? NSLocalizedString("MyData document", comment: "vault document detail title"))
        let controller = MyDataOnboardViewController(documentType: type)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func confirmShare() {
        let alert = UIAlertController(
            title: NSLocalizedString("Export a copy?", comment: "MyData vault share confirmation"),
            message: NSLocalizedString(
                "The copy you choose to share is no longer protected by this vault. Check the recipient and destination before continuing.",
                comment: "MyData vault share confirmation"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""),
                                      style: .default) { [weak self] _ in self?.shareCopy() })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func shareCopy() {
        guard let document,
              let original = archive.originalURL(id: documentID) else {
            presentError(MyDataVaultPreviewError.originalMissing.localizedDescription)
            return
        }
        do {
            let exportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MyDataVaultExport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: exportDirectory,
                                                    withIntermediateDirectories: true)
            var excludedDirectory = exportDirectory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excludedDirectory.setResourceValues(values)

            let fileExtension = Self.safeFileExtension(document.entry?.fileExtension)
            let baseName = Self.safeExportName(document.entry?.displayName
                ?? MyDataDocumentRegistry.lookup(id: documentID)?.title
                ?? NSLocalizedString("MyData document", comment: "vault document detail title"))
            let output = exportDirectory.appendingPathComponent(baseName)
                .appendingPathExtension(fileExtension)
            try Data(contentsOf: original).write(
                to: output, options: [.atomic, .completeFileProtectionUnlessOpen])

            let activity = UIActivityViewController(activityItems: [output], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: exportDirectory)
            }
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(
                x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
            present(activity, animated: true)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    static func safeExportName(_ candidate: String) -> String {
        let scalars = candidate.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-" || scalar == "_" || scalar == " "
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "MyData-document" : String(cleaned.prefix(80))
    }

    static func safeFileExtension(_ candidate: String?) -> String {
        let cleaned = (candidate ?? "").lowercased().filter { $0.isASCII && $0.isLetter }
        return cleaned.isEmpty ? "data" : String(cleaned.prefix(8))
    }

    private func showCredentialUseCases() {
        navigationController?.pushViewController(
            MyDataCredentialUseCasesViewController(documentTitle: title ?? ""), animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(
            title: NSLocalizedString("Delete this document?", comment: ""),
            message: NSLocalizedString(
                "The protected original and its saved fingerprint will be removed from this phone. You can import it again later from MyData.",
                comment: ""),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""),
                                      style: .destructive) { [weak self] _ in self?.deleteDocument() })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func deleteDocument() {
        do {
            try archive.delete(id: documentID)
            onDeleted?()
            navigationController?.popViewController(animated: true)
        } catch {
            presentError(NSLocalizedString("The document could not be deleted from this phone.", comment: ""))
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: NSLocalizedString("Could not open the document", comment: ""),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }
}

/// In-app PDF rendering keeps a MyData original out of Documents, share sheets
/// and Quick Look's filename-based handoff. The `PDFDocument` owns in-memory
/// bytes; no extracted preview file survives the push.
final class MyDataVaultPDFViewController: UIViewController {
    private let document: PDFDocument

    init(title: String, document: PDFDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let pdfView = PDFView(frame: .zero)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
