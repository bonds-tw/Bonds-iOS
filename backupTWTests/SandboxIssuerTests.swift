//
//  SandboxIssuerTests.swift
//  backupTWTests
//
//  The 請收下卡片 sandbox issuer (issuer.mashbean.net) pinned as a DEBUG-only
//  trust exception: its offer must pass both collection gates, its DID must be
//  a key this wallet can resolve, its host must be a trusted presentation
//  response host, and the cards it mints must read as test cards of the kind
//  they imitate. See docs/sandbox-issuer.md.
//

import Foundation
import Testing
@testable import backupTW

@Suite("請收下卡片 沙盒發卡站的信任釘定")
struct SandboxIssuerTests {

    // The literal QR the issuer page renders for the 有備而來 wallet — the
    // standard scheme, offer by reference. Measured 2026-09-08 (scripts/smoke.mjs
    // in mashbean/twdiw-vc-issuer-lite prints this line).
    static let scannedQR = "openid-credential-offer://?credential_offer_uri=https%3A%2F%2Fissuer.mashbean.net%2Fapi%2Foffer%2Fe25dce3e-56e2-4164-a75f-59af88893e53"

    // The offer object the issuer returns: the identifier is the bare origin,
    // one configuration id, a pre-authorised code, no tx_code.
    static let offerJSON = Data("""
    {"credential_issuer":"https://issuer.mashbean.net",
     "credential_configuration_ids":["sandbox_driverlicense_car_v1"],
     "grants":{"urn:ietf:params:oauth:grant-type:pre-authorized_code":{"pre-authorized_code":"e25dce3e-56e2-4164-a75f-59af88893e53.ff0579c6"}}}
    """.utf8)

    static let sandboxTypes = [
        "sandbox_driverlicense_car_v1", "sandbox_telecom_msisdn_v1", "sandbox_student_card_v1",
        "sandbox_employee_badge_v1", "sandbox_library_card_v1", "sandbox_membership_card_v1",
    ]

    @Test func step1_theScannedQRParsesByReference() throws {
        let link = try CredentialOfferLink.parse(scanned: Self.scannedQR)
        guard case .byReference(let fetchURL) = link else {
            Issue.record("parsed to \(link), not byReference")
            return
        }
        #expect(fetchURL == "https://issuer.mashbean.net/api/offer/e25dce3e-56e2-4164-a75f-59af88893e53")
    }

    @Test func step2_gate1AuthorisesTheOfferHostFromThePinnedEntryAlone() throws {
        guard case .byReference(let fetchURL) = try CredentialOfferLink.parse(scanned: Self.scannedQR) else {
            Issue.record("not byReference"); return
        }
        let verdict = IssuerAuthorization.authorise(fetchURL: fetchURL, against: TWDIWIssuer.trustedSandboxes)
        guard case .allowed(let issuers, let host) = verdict else {
            Issue.record("gate 1 refused: \(verdict)")
            return
        }
        #expect(host == "issuer.mashbean.net")
        #expect(issuers.count == 1)
        #expect(issuers.first?.did == TWDIWIssuer.mashbeanSandbox.did)
    }

    @Test func step3_gate2ConfirmsTheCredentialIssuer() throws {
        let offer = try CredentialOffer.parse(json: Self.offerJSON)
        #expect(offer.requiresTransactionCode == false)
        let result = IssuerAuthorization.confirm(credentialIssuer: offer.credentialIssuer,
                                                 matched: [.mashbeanSandbox])
        switch result {
        case .success(let issuer): #expect(issuer.did == TWDIWIssuer.mashbeanSandbox.did)
        case .failure(let refusal): Issue.record("gate 2 refused: \(refusal)")
        }
    }

    /// The pin is only as good as the string: the post-issuance check compares
    /// the card's `iss` to it verbatim, and `TWDIWCredentialReader` takes the
    /// signing key out of it. A typo here would fail every card at the last step.
    @Test func thePinnedDIDIsAResolvableJWKJCSPubKey() throws {
        let did = TWDIWIssuer.mashbeanSandbox.did
        #expect(did.hasPrefix("did:key:z2dmz"))
        #expect(throws: Never.self) { _ = try JWKDIDKey.p256PublicKey(fromDID: did) }
        // Canonical spelling: re-encoding the resolved key must give the same DID,
        // so string equality in the collector is the same test as key equality.
        let key = try JWKDIDKey.p256PublicKey(fromDID: did)
        #expect(try JWKDIDKey.did(fromP256PublicKeyX963: key.x963Representation) == did)
    }

    @Test func theSandboxHostIsATrustedPresentationResponseHost() {
        let hosts = OID4VPPresentation.verifierHosts(from: [])
        #expect(hosts.contains("issuer.mashbean.net"))
        // The existing exceptions are untouched by the new entry.
        #expect(hosts.contains("verifier.mashbean.net"))
        #expect(hosts.contains("issuer-oid4vci.wallet.gov.tw"))
    }

    @Test func aLookalikeHostIsStillRefused() {
        for fetchURL in ["https://issuer.mashbean.net.evil.example/api/offer/x",
                         "https://evil-issuer.mashbean.net/api/offer/x",
                         "http://issuer.mashbean.net/api/offer/x"] {
            let verdict = IssuerAuthorization.authorise(fetchURL: fetchURL, against: TWDIWIssuer.trustedSandboxes)
            guard case .refused = verdict else {
                Issue.record("gate 1 allowed \(fetchURL): \(verdict)")
                continue
            }
        }
    }

    @Test func sandboxCardsReadAsTestCardsOfTheKindTheyImitate() {
        let expectedKinds = ["駕照電子卡", "門號電子卡", "學生證", "員工識別證", "圖書借閱證", "會員卡"]
        for (type, kind) in zip(Self.sandboxTypes, expectedKinds) {
            let d = IssuerDirectory.describe(credentialType: type, issuerDID: TWDIWIssuer.mashbeanSandbox.did)
            #expect(d.issuerName == TWDIWIssuer.mashbeanSandbox.displayName, "type: \(type)")
            #expect(d.cardKind == kind, "type: \(type)")
            #expect(d.trustSource == "沙盒/測試", "type: \(type)")
        }
        // The same types from any other sandbox keep the generic honest name.
        let other = IssuerDirectory.describe(credentialType: "sandbox_student_card_v1", issuerDID: "did:key:zSomeoneElse")
        #expect(other.issuerName == "沙盒系統")
        #expect(other.cardKind == "學生證")
    }

    @Test func everySandboxClaimKeyHasACuratedLabel() {
        let keys = ["name", "id_number", "birthdate", "address", "license_type", "license_conditions", "issue_date", "expiry_date",
                    "phonel5", "phonel3", "phone_number", "carrier",
                    "student_id", "school", "department", "enrollment_year",
                    "employee_id", "organization", "role", "email", "valid_from",
                    "card_number", "library", "member_id", "tier"]
        for key in keys {
            let hit = StoredNationalID.fieldLabelTable.first { $0.keys.contains(key) }
            #expect(hit != nil, "no label row for \(key)")
        }
    }

    /// The sandbox ships in Release: the simulated-card issuer is trusted in
    /// every build, and only the moda demo is DEBUG-gated. This is the decision
    /// that lets a TestFlight tester exercise the wallet without a real card.
    @Test func theSimulatedIssuerIsTrustedInEveryBuild() {
        #expect(TWDIWIssuer.trustedSandboxes.contains { $0.did == TWDIWIssuer.mashbeanSandbox.did })
        #expect(OID4VPPresentation.verifierHosts(from: []).contains("issuer.mashbean.net"))
    }

    /// Grouping detection: a card is 模擬卡 when its issuer is the pinned sandbox
    /// DID or its type is `sandbox`-marked, and — crucially — the production
    /// `…_demo_drivinglicense_…` government fixture is NOT caught, so real cards
    /// are never misfiled into the simulated group.
    @Test func simulatedDetectionCatchesSandboxCardsButNotRealOnes() {
        #expect(TWDIWIssuer.isSimulatedCredential(issuerDID: TWDIWIssuer.mashbeanSandbox.did,
                                                  credentialType: "sandbox_driverlicense_car_v1"))
        #expect(TWDIWIssuer.isSimulatedCredential(issuerDID: "did:key:zStranger",
                                                  credentialType: "sandbox_membership_card_v1"))
        // A real government fixture: neither the pinned DID nor a sandbox type.
        #expect(!TWDIWIssuer.isSimulatedCredential(issuerDID: "did:key:zRealGov",
                                                   credentialType: "00000000_demo_drivinglicense_202504251418"))
        #expect(!TWDIWIssuer.isSimulatedCredential(issuerDID: "did:key:zRealGov",
                                                   credentialType: "2-16-886-101-20003-20008-20082_driverlicense_car_1211"))
    }
}
