//
//  CredentialCollection.swift
//  backupTW
//
//  One place that runs a collection, so the two entry points cannot drift.
//

import Foundation
import os

/// Coordinates one OID4VCI collection from a parsed offer link.
///
/// # Why this is not on `SceneDelegate`
///
/// A credential offer reaches this app two ways: the OS routing a
/// `openid-credential-offer://` / `modadigitalwallet://` deep link to
/// `SceneDelegate`, and the holder scanning a QR from inside the app (the
/// official flow's step 2 — 「使用數位憑證皮夾 App 掃描 QR-Code，來加入卡片」).
/// Both must fetch the same trust list, run the same two gates, and mint the
/// same one-key-per-card. A copy of that in each place is a copy that drifts —
/// the exact failure `HolderKeyring` and `CardInventory` were written to avoid,
/// arrived at from the UI side. So the sequence lives here once.
enum CredentialCollection {

    /// Runs a collection and returns a human-facing outcome line.
    ///
    /// Returns rather than presents: the caller owns a view hierarchy this type
    /// does not, and a scan screen dismisses to a different place than a
    /// deep-link launch. The string is already localized. On failure it is a
    /// person-facing sentence from `UserFacingError` — what happened and what to
    /// do — never the error's own `description`, which used to put a Swift type
    /// name on screen.
    ///
    /// The raw error is still logged for a developer; only the screen is
    /// translated. The measurement value of the exact case (which gate, which
    /// status) lives in the log, not in front of the cardholder.
    /// Success and failure carried as what they are, not as two strings that
    /// look alike — the caller decides how each is shown (a success is a moment,
    /// a failure is an alert; the two used to share one identical alert).
    enum Outcome {
        case stored(id: String, message: String)
        case failed(message: String)

        var message: String {
            switch self {
            case .stored(_, let message), .failed(let message): return message
            }
        }
        var isSuccess: Bool {
            if case .stored = self { return true }
            return false
        }
    }

    @MainActor
    static func run(from link: CredentialOfferLink) async -> Outcome {
        do {
            var trustList = try await TrustListFetcher(session: .shared).fetchAll()
            // The list is in hand anyway — write the DID→name pairs down so
            // card faces can name a trust-listed issuer offline. Before the
            // DEBUG sandbox append: the demo issuer must not enter the book.
            IssuerNameBook.remember(trustList)
            // The 請收下卡片 simulated-card issuer is trusted in every build; the
            // moda demo joins it only in DEBUG (see `TWDIWIssuer.trustedSandboxes`
            // and docs/sandbox-issuer.md). Neither is on the production list, so
            // this is the one explicit sandbox exception — the gates below are not
            // loosened for anyone else.
            trustList.append(contentsOf: TWDIWIssuer.trustedSandboxes)
            let registryVerifier = TWDIWOnChainVerifier(session: .shared)
            let collector = OID4VCICollector(session: .shared,
                                             trustList: trustList,
                                             verifyRegistry: { issuers in
                                                 var results = await registryVerifier.verify(issuers)
                                                 // The sandboxes are separate trust domains with no
                                                 // production Arbitrum row. Marking them keeps the
                                                 // exception explicit and never calls a clearly-labelled
                                                 // simulated card chain-verified.
                                                 let sandboxDIDs = Set(TWDIWIssuer.trustedSandboxes.map(\.did))
                                                 for issuer in issuers where sandboxDIDs.contains(issuer.did) {
                                                     results[issuer.did] = .developmentSandbox
                                                 }
                                                 return results
                                             },
                                             keyring: .app(),
                                             store: try CredentialStore(),
                                             saveTrustSnapshot: { snapshot in
                                                 try OfflineIssuerTrustStore().save(snapshot)
                                             })
            let receipt = try await collector.collect(from: link)
            return .stored(id: receipt.storedID,
                           message: String(format: NSLocalizedString("Stored as %@.", comment: "collection success"),
                                           receipt.storedID))
        } catch {
            log.error("collection failed: \(String(describing: error), privacy: .public)")
            return .failed(message: UserFacingError.collectionMessage(for: error))
        }
    }

    private static let log = Logger(subsystem: "tw.bonds.backupTW", category: "collection")
}
