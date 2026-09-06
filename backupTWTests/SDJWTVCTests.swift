//
//  SDJWTVCTests.swift
//  backupTWTests
//
//  A flat SD-JWT VC, minted, presented with a key-binding JWT, and read back.
//

import CryptoKit
import Foundation
import Testing
@testable import backupTW

@Suite("SD-JWT VC：鑄造、出示、驗回")
struct SDJWTVCTests {

    static let vct = "https://bonds-tw.github.io/vct/mydata-income/v1.json"

    private func mint(key: EphemeralSigningKey = .init()) throws -> (SDJWTVCDocument, EphemeralSigningKey) {
        let document = try SDJWTVCIssuance.mint(
            vct: Self.vct,
            disclosable: [("tax_year", "2024"), ("income_within_ceiling", "true"), ("payer_count", "2")],
            plain: ["assurance": "holder-derived",
                    "source": ["kind": "mydata-downloaded-document", "sha256": "ab", "parser": "income-pdf/v1"],
                    "rule": ["id": "income-ceiling/v1", "params": ["tax_year": "2024", "ceiling_twd": "500000"]]],
            key: key,
            now: Date(timeIntervalSince1970: 1_800_000_000))
        return (document, key)
    }

    @Test func theIssuerJWTHasTheSDJWTVCShape() throws {
        let (document, key) = try mint()
        let payload = try SDJWTVCReader.rawPayload(document.serialized())
        #expect(payload["vct"] as? String == Self.vct)
        #expect(payload["iss"] as? String == (try JWKDIDKey.did(fromP256PublicKeyX963: key.publicKeyX963)))
        #expect(payload["_sd_alg"] as? String == "sha-256")
        #expect((payload["_sd"] as? [String])?.count == 3)
        #expect((payload["_sd"] as? [String]) == (payload["_sd"] as? [String])?.sorted())
        #expect((payload["cnf"] as? [String: Any])?["jwk"] != nil)
        #expect(payload["assurance"] as? String == "holder-derived")
        #expect(payload["tax_year"] == nil, "a disclosable claim never appears in clear")
        let header = try #require(Data(base64URLEncoded: String(document.issuerJWT.split(separator: ".")[0])))
        let typ = (try JSONSerialization.jsonObject(with: header) as? [String: Any])?["typ"] as? String
        #expect(typ == "dc+sd-jwt")
    }

    @Test func aPresentationCarriesOnlyTheChosenClaimsAndAValidKeyBinding() throws {
        let (document, key) = try mint()
        let presentation = try SDJWTVCPresentation.present(
            document, disclosing: ["income_within_ceiling", "tax_year"],
            audience: "did:key:zVerifier", nonce: "N-1", key: key)
        #expect(presentation.hasSuffix("~") == false, "the KB-JWT is the last segment")
        let read = try SDJWTVCReader.read(presentation, expectedAudience: "did:key:zVerifier", expectedNonce: "N-1")
        #expect(read.keyBound)
        #expect(Set(read.claims.map(\.name)) == ["income_within_ceiling", "tax_year"])
        #expect(read.claims.first { $0.name == "income_within_ceiling" }?.value == "true")
        #expect(read.payload["assurance"] == "holder-derived")
    }

    @Test func theWrongNonceOrAudienceIsRefused() throws {
        let (document, key) = try mint()
        let presentation = try SDJWTVCPresentation.present(
            document, disclosing: ["tax_year"], audience: "did:key:zVerifier", nonce: "N-1", key: key)
        #expect(throws: SDJWTVCError.keyBindingInvalid("nonce")) {
            _ = try SDJWTVCReader.read(presentation, expectedAudience: "did:key:zVerifier", expectedNonce: "N-2")
        }
        #expect(throws: SDJWTVCError.keyBindingInvalid("aud")) {
            _ = try SDJWTVCReader.read(presentation, expectedAudience: "did:key:zOther", expectedNonce: "N-1")
        }
    }

    @Test func aDisclosureAddedAfterSigningIsRefused() throws {
        let (document, key) = try mint()
        let forged = Disclosure(claimName: "income_within_ceiling", claimValue: "true")
        let presentation = document.serialized(disclosing: ["tax_year"]) + forged.encoded + "~"
        let withKB = presentation + (try SDJWTVCPresentation.keyBindingJWT(
            over: presentation, audience: "a", nonce: "n", key: key))
        #expect(throws: SDJWTVCError.undisclosedDigest(forged.digest)) {
            _ = try SDJWTVCReader.read(withKB, expectedAudience: "a", expectedNonce: "n")
        }
    }

    @Test func aKeyBindingFromAnotherKeyIsRefused() throws {
        let (document, _) = try mint()
        let stranger = EphemeralSigningKey()
        let presentation = try SDJWTVCPresentation.present(
            document, disclosing: ["tax_year"], audience: "a", nonce: "n", key: stranger)
        #expect(throws: SDJWTVCError.signatureInvalid) {
            _ = try SDJWTVCReader.read(presentation, expectedAudience: "a", expectedNonce: "n")
        }
    }

    @Test func aPresentationWithoutKeyBindingIsRefusedWhenOneIsExpected() throws {
        let (document, _) = try mint()
        #expect(throws: SDJWTVCError.keyBindingMissing) {
            _ = try SDJWTVCReader.read(document.serialized(), expectedAudience: "a", expectedNonce: "n")
        }
        // …and read fine when the caller is only inspecting the issuer half.
        #expect(try SDJWTVCReader.read(document.serialized()).keyBound == false)
    }

    @Test func swappingDisclosuresAfterKeyBindingBreaksTheSDHash() throws {
        let (document, key) = try mint()
        let presented = try SDJWTVCPresentation.present(
            document, disclosing: ["tax_year"], audience: "a", nonce: "n", key: key)
        let kb = String(presented.split(separator: "~").last!)
        let swapped = document.serialized(disclosing: ["payer_count"]) + kb
        #expect(throws: SDJWTVCError.keyBindingInvalid("sd_hash")) {
            _ = try SDJWTVCReader.read(swapped, expectedAudience: "a", expectedNonce: "n")
        }
    }

    @Test func reservedNamesCannotBeSmuggledAsClaims() {
        #expect(throws: SDJWTVCError.malformed) {
            _ = try SDJWTVCIssuance.mint(vct: Self.vct, disclosable: [("iss", "did:key:zEvil")],
                                         plain: [:], key: EphemeralSigningKey())
        }
        #expect(throws: SDJWTVCError.malformed) {
            _ = try SDJWTVCIssuance.mint(vct: Self.vct, disclosable: [],
                                         plain: ["cnf": ["jwk": [:]]], key: EphemeralSigningKey())
        }
    }

    @Test func anExpiredCredentialIsRefused() throws {
        let key = EphemeralSigningKey()
        let document = try SDJWTVCIssuance.mint(vct: Self.vct, disclosable: [("a", "1")], plain: [:],
                                                key: key, now: Date(timeIntervalSince1970: 1_000),
                                                validForSeconds: 60)
        #expect(throws: SDJWTVCError.expired) {
            _ = try SDJWTVCReader.read(document.serialized(), now: Date(timeIntervalSince1970: 2_000))
        }
    }
}
