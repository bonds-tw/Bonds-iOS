//
//  MyDataDerivedPresentation.swift
//  backupTW
//
//  Turning a vault original into the one signed answer a verifier asked for,
//  at the moment of asking.
//

import CryptoKit
import Foundation
import PDFKit

/// One original the vault holds, as the presenter needs it: which kind it is,
/// its fingerprint, and a way to read its text only when actually chosen.
struct MyDataVaultSourceDocument {
    let id: String
    /// `MyDataDocumentRegistry` id, when the vault knows the kind.
    let documentTypeID: String?
    /// Lowercase-hex SHA-256 of the stored bytes — the `source.sha256` the
    /// credential binds to.
    let sha256: String
    /// The page text of the original. Called at most once, for the document
    /// the request selects; the others are never opened.
    let text: () throws -> String
}

/// Where the presenter reads originals from. `MyDataVaultArchive` in the app,
/// an in-memory list in tests.
protocol MyDataVaultDocumentSource {
    func derivableDocuments() throws -> [MyDataVaultSourceDocument]
}

extension MyDataVaultArchive: MyDataVaultDocumentSource {

    /// Every archived original with its recorded fingerprint. A document whose
    /// metadata is missing has no fingerprint to bind to and is left out — it is
    /// still on the detail screen, just not presentable.
    func derivableDocuments() throws -> [MyDataVaultSourceDocument] {
        try documents().compactMap { document in
            guard let entry = document.entry else { return nil }
            let known = MyDataDocumentRegistry.lookup(id: document.id)
                ?? entry.displayName.flatMap(MyDataDocumentRegistry.knownDocument(in:))
            return MyDataVaultSourceDocument(
                id: document.id,
                documentTypeID: known?.id,
                sha256: entry.sha256,
                text: { [self] in try MyDataVaultText.extract(id: document.id, archive: self) })
        }
    }
}

/// The text of a vault original, whatever container MyData delivered it in:
/// a PDF's text layer, a CSV or TXT decoded as UTF-8 (Big5 as the fallback
/// the older agency exports use), or the first such entry inside a ZIP.
enum MyDataVaultText {

    static func extract(id: String, archive: MyDataVaultArchive, password: String? = nil) throws -> String {
        guard let original = archive.originalURL(id: id) else {
            throw MyDataDocumentParserError.notThisDocument
        }
        let format = archive.entry(id: id)?.fileExtension.lowercased() ?? ""
        let data: Data
        let ext: String
        switch format {
        case "zip":
            let scratch = MyDataScratch(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MyDataVaultText-\(UUID().uuidString)", isDirectory: true))
            defer { try? scratch.purge() }
            let zip = try scratch.downloadDestination()
            try Data(contentsOf: original).write(to: zip, options: [.atomic, .completeFileProtectionUnlessOpen])
            (data, ext) = try scratch.readableEntry(fromArchiveAt: zip)
        default:
            data = try Data(contentsOf: original)
            ext = format
        }
        return try text(of: data, fileExtension: ext, password: password)
    }

    /// MyData seals its PDFs with the holder's national ID number. The stored
    /// national ID card carries that number, so a phone that has made its
    /// national ID can open its own vault documents without asking; a caller
    /// may also pass the number explicitly (the DEBUG parse preview does).
    static func text(of data: Data, fileExtension: String, password: String? = nil) throws -> String {
        if fileExtension == "pdf" || data.starts(with: Array("%PDF".utf8)) {
            guard let pdf = PDFDocument(data: data) else { throw MyDataDocumentParserError.notThisDocument }
            if pdf.isLocked {
                let candidates = [password, StoredNationalID.load()?.claims.first { $0.key == "unifiedNo" }?.value]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                guard candidates.contains(where: { pdf.unlock(withPassword: $0) || pdf.unlock(withPassword: $0.uppercased()) }) else {
                    throw MyDataDocumentParserError.locked
                }
            }
            let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw MyDataDocumentParserError.notThisDocument }
            return text
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        if let text = String(data: data, encoding: String.Encoding(rawValue: big5)) { return text }
        throw MyDataDocumentParserError.notThisDocument
    }
}

/// What the presenter produced: the presentation string and where it came from.
struct MyDataDerivedPresentationResult {
    /// The DCQL credential query id, or the input descriptor id.
    let descriptorID: String
    /// `<jwt>~<chosen disclosures>~<kb-jwt>`.
    let presentation: String
    let vct: String
    let sourceDocumentID: String
}

/// Builds a vault-derived SD-JWT VC for one request.
///
/// # What is signed, and by what
///
/// The credential is minted here, now, for this verifier: the rule from the
/// request, the claims the rule produces, the fingerprint of the original, the
/// parser version — all under one signature from a **fresh in-memory P-256
/// key**. The same key signs the KB-JWT, so `iss`, `cnf` and the presenter are
/// one key, and the key is gone when this call returns. Two presentations of
/// the same document therefore share nothing a verifier could join on; the
/// claim's standing rests on `assurance: holder-derived` plus the fingerprint,
/// which is exactly what the scenarios document says it should rest on.
enum MyDataDerivedPresenter {

    static let assurance = "holder-derived"
    static let sourceKind = "mydata-downloaded-document"

    /// - Parameters:
    ///   - chosenClaims: what the holder left switched on. Must be a subset of
    ///     the request's fields; the credential still commits to every claim
    ///     of the type, and only these travel.
    static func present(_ request: OID4VPRequest,
                        chosenClaims: Set<String>,
                        source: MyDataVaultDocumentSource,
                        now: Date = Date()) throws -> MyDataDerivedPresentationResult {
        guard let descriptor = request.inputDescriptors.first(where: {
            $0.credentialFormat == .sdJWTVC || request.queryLanguage == .dcql
        }) else { throw OID4VPResponseError.noMatchingCredential }
        guard let vct = descriptor.credentialType,
              let type = MyDataDerivedCredentialType.lookup(vct: vct) else {
            throw OID4VPResponseError.noMatchingCredential
        }
        guard let rule = request.rule else { throw OID4VPResponseError.ruleMissing }
        if let problem = rule.validationProblem() { throw OID4VPResponseError.derivation(problem) }

        let requested = Set(descriptor.requestedFields.compactMap(\.claimName))
        if let unrequested = chosenClaims.first(where: { !requested.contains($0) }) {
            throw OID4VPResponseError.requestedClaimNotAvailable(unrequested)
        }
        if let unknown = requested.first(where: { !type.claimNames.contains($0) }) {
            throw OID4VPResponseError.requestedClaimNotAvailable(unknown)
        }

        guard let parser = MyDataDocumentParsers.parser(for: type.documentTypeID) else {
            throw OID4VPResponseError.noMatchingCredential
        }
        // The original of the right kind: by its registered id or display name
        // first, then — for an import the vault could not name — by what its
        // own first page says. Only untyped originals are opened for that, and
        // only until one matches; the archive keeps one original per id.
        let documents = try source.derivableDocuments()
        var document = documents.first(where: { $0.documentTypeID == type.documentTypeID })
        var text: String?
        if document == nil {
            for candidate in documents where candidate.documentTypeID == nil {
                guard let candidateText = try? candidate.text(),
                      MyDataDocumentRegistry.knownDocument(in: candidateText)?.id == type.documentTypeID else { continue }
                document = candidate
                text = candidateText
                break
            }
        }
        guard let document else { throw OID4VPResponseError.sourceDocumentUnavailable }
        let parsed: MyDataParsedDocument
        do { parsed = try parser.parse(text: try text ?? document.text()) }
        catch let error as MyDataDocumentParserError { throw OID4VPResponseError.sourceDocumentUnreadable(error) }
        catch { throw OID4VPResponseError.sourceDocumentUnreadable(.notThisDocument) }

        let derived: [String: String]
        do { derived = try type.derive(from: parsed, rule: rule) }
        catch let error as MyDataDerivationError { throw OID4VPResponseError.derivation(error) }
        if let missing = chosenClaims.first(where: { derived[$0] == nil }) {
            throw OID4VPResponseError.requestedClaimNotAvailable(missing)
        }

        let key = EphemeralSigningKey()
        let credential = try SDJWTVCIssuance.mint(
            vct: vct,
            disclosable: type.claimNames.compactMap { name in derived[name].map { (name: name, value: $0) } },
            plain: [
                "source": [
                    "kind": sourceKind,
                    "sha256": document.sha256,
                    "document_type": type.documentTypeID,
                    "parser": parsed.parserVersion,
                ],
                "rule": rule.json,
                "assurance": assurance,
                "vct#integrity": type.vctIntegrity,
            ],
            key: key,
            now: now,
            // Minted for this exchange; a verifier reading it an hour later is
            // reading something the holder did not present to it.
            validForSeconds: 60 * 10)
        let presentation = try SDJWTVCPresentation.present(
            credential, disclosing: chosenClaims,
            audience: request.clientID, nonce: request.nonce, key: key, now: now)
        return MyDataDerivedPresentationResult(descriptorID: descriptor.id,
                                               presentation: presentation,
                                               vct: vct,
                                               sourceDocumentID: document.id)
    }
}
