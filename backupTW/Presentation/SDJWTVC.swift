//
//  SDJWTVC.swift
//  backupTW
//
//  The IETF SD-JWT VC shape: a flat credential, its disclosures, and the
//  key-binding JWT that proves who is presenting it.
//

import CryptoKit
import Foundation

/// A key that can sign a JWS the way this file needs: raw `r‖s`, P-256.
///
/// `DeviceKey` (Secure Enclave) and `P256.Signing.PrivateKey` (in memory) both
/// qualify. A derived credential is minted per presentation with an in-memory
/// key that lives only as long as the response — nothing about it is worth a
/// Keychain item, and a key that is never stored is never left behind.
protocol SDJWTSigningKey {
    var publicKeyX963: Data { get }
    func signature(for data: Data) throws -> Data
}

extension DeviceKey: SDJWTSigningKey {}

/// An in-memory P-256 key that exists for one presentation.
///
/// A wrapper rather than a conformance on `P256.Signing.PrivateKey` itself:
/// CryptoKit's own `signature(for:)` returns an `ECDSASignature`, and adding a
/// same-named method returning `Data` made every existing call site ambiguous.
struct EphemeralSigningKey: SDJWTSigningKey {
    private let privateKey = P256.Signing.PrivateKey()

    init() {}

    var publicKeyX963: Data { privateKey.publicKey.x963Representation }
    var publicKey: P256.Signing.PublicKey { privateKey.publicKey }

    func signature(for data: Data) throws -> Data {
        try privateKey.signature(for: data).rawRepresentation
    }
}

enum SDJWTVCError: Error, Equatable {
    case malformed
    case unsupportedAlgorithm(String)
    case issuerNotResolvable
    case signatureInvalid
    case undisclosedDigest(String)
    case keyBindingMissing
    case keyBindingInvalid(String)
    case expired
}

enum SDJWTVC {
    /// The media type of the issuer-signed JWT. Earlier drafts said
    /// `vc+sd-jwt`; the current draft says `dc+sd-jwt`, and the verifier
    /// accepts both.
    static let typ = "dc+sd-jwt"
    static let keyBindingTyp = "kb+jwt"
    static let digestAlgorithm = "sha-256"

    /// A P-256 JWK from an X9.63 public key: `0x04 ‖ X ‖ Y`.
    static func jwk(x963: Data) -> [String: Any] {
        let coordinates = x963.dropFirst()
        return [
            "kty": "EC",
            "crv": "P-256",
            "x": Data(coordinates.prefix(32)).base64URLEncodedString(),
            "y": Data(coordinates.dropFirst(32)).base64URLEncodedString(),
        ]
    }

    static func base64URL(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]) else {
            throw SDJWTVCError.malformed
        }
        return data.base64URLEncodedString()
    }

    static func sign(header: [String: Any], payload: [String: Any],
                     key: SDJWTSigningKey) throws -> String {
        let signingInput = try base64URL(header) + "." + base64URL(payload)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return signingInput + "." + signature.base64URLEncodedString()
    }

    /// `base64url(SHA-256(presentation))`, over the bytes up to and including
    /// the last `~` — what a KB-JWT's `sd_hash` commits to.
    static func sdHash(of presentation: String) -> String {
        Data(SHA256.hash(data: Data(presentation.utf8))).base64URLEncodedString()
    }
}

/// An issuer-signed SD-JWT VC and every disclosure it committed to.
struct SDJWTVCDocument: Equatable {
    let issuerJWT: String
    let disclosures: [Disclosure]

    /// `<jwt>~<d1>~…~` carrying only the chosen claims. `nil` keeps them all.
    func serialized(disclosing chosen: Set<String>? = nil) -> String {
        let kept = disclosures.filter { chosen?.contains($0.claimName) ?? true }
        return ([issuerJWT] + kept.map(\.encoded)).joined(separator: "~") + "~"
    }
}

enum SDJWTVCIssuance {

    /// Mints a credential whose `iss` and `cnf` are the same key — the holder
    /// vouching for a claim about themselves, bound to the key that will
    /// present it.
    ///
    /// - Parameters:
    ///   - disclosable: the claims committed under `_sd`, each its own disclosure.
    ///   - plain: claims visible to every reader (`source`, `rule`, `assurance`).
    ///     Reserved names (`iss`, `vct`, `cnf`, `_sd`, …) are refused.
    static func mint(vct: String,
                     disclosable: [(name: String, value: String)],
                     plain: [String: Any],
                     key: SDJWTSigningKey,
                     now: Date = Date(),
                     validForSeconds: Int? = nil) throws -> SDJWTVCDocument {
        let reserved: Set<String> = ["iss", "iat", "exp", "nbf", "vct", "cnf", "_sd", "_sd_alg", "sub"]
        if plain.keys.contains(where: reserved.contains) { throw SDJWTVCError.malformed }
        if disclosable.contains(where: { reserved.contains($0.name) || plain[$0.name] != nil }) {
            throw SDJWTVCError.malformed
        }

        let issuer = try JWKDIDKey.did(fromP256PublicKeyX963: key.publicKeyX963)
        let (digests, disclosures) = SelectiveDisclosure.commit(disclosable)
        var payload: [String: Any] = plain
        payload["iss"] = issuer
        payload["iat"] = Int(now.timeIntervalSince1970)
        if let validForSeconds { payload["exp"] = Int(now.timeIntervalSince1970) + validForSeconds }
        payload["vct"] = vct
        payload["cnf"] = ["jwk": SDJWTVC.jwk(x963: key.publicKeyX963)]
        payload["_sd"] = digests
        payload["_sd_alg"] = SDJWTVC.digestAlgorithm

        let header: [String: Any] = ["alg": "ES256", "typ": SDJWTVC.typ]
        let jwt = try SDJWTVC.sign(header: header, payload: payload, key: key)
        return SDJWTVCDocument(issuerJWT: jwt, disclosures: disclosures)
    }
}

enum SDJWTVCPresentation {

    /// The full presentation: chosen disclosures, then a KB-JWT over them.
    static func present(_ document: SDJWTVCDocument,
                        disclosing chosen: Set<String>,
                        audience: String,
                        nonce: String,
                        key: SDJWTSigningKey,
                        now: Date = Date()) throws -> String {
        let presentation = document.serialized(disclosing: chosen)
        return presentation + (try keyBindingJWT(over: presentation, audience: audience,
                                                 nonce: nonce, key: key, now: now))
    }

    /// `typ: kb+jwt`, with `sd_hash` over the presentation it follows, so the
    /// proof cannot be lifted onto a different set of disclosures.
    static func keyBindingJWT(over presentation: String,
                              audience: String,
                              nonce: String,
                              key: SDJWTSigningKey,
                              now: Date = Date()) throws -> String {
        guard presentation.hasSuffix("~") else { throw SDJWTVCError.malformed }
        let header: [String: Any] = ["alg": "ES256", "typ": SDJWTVC.keyBindingTyp]
        let payload: [String: Any] = [
            "iat": Int(now.timeIntervalSince1970),
            "aud": audience,
            "nonce": nonce,
            "sd_hash": SDJWTVC.sdHash(of: presentation),
        ]
        return try SDJWTVC.sign(header: header, payload: payload, key: key)
    }
}

/// A presented SD-JWT VC, read back and checked.
struct SDJWTVCVerified: Equatable {
    let vct: String
    let issuer: String
    let payload: [String: String]
    let claims: [(name: String, value: String)]
    let keyBound: Bool

    static func == (lhs: SDJWTVCVerified, rhs: SDJWTVCVerified) -> Bool {
        lhs.vct == rhs.vct && lhs.issuer == rhs.issuer && lhs.keyBound == rhs.keyBound
            && lhs.claims.map(\.name) == rhs.claims.map(\.name)
            && lhs.claims.map(\.value) == rhs.claims.map(\.value)
    }
}

enum SDJWTVCReader {

    /// Verifies the issuer signature against the key in `iss`, reveals the
    /// disclosures against `_sd`, and — when a KB-JWT is present — checks it
    /// against `cnf` with the expected audience and nonce.
    ///
    /// `payload` in the result carries only string-valued top-level claims;
    /// nested objects (`source`, `rule`) are read by the caller from the raw
    /// JSON when needed.
    static func read(_ serialized: String,
                     expectedAudience: String? = nil,
                     expectedNonce: String? = nil,
                     now: Date = Date()) throws -> SDJWTVCVerified {
        let parts = serialized.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard let jwt = parts.first, !jwt.isEmpty else { throw SDJWTVCError.malformed }
        let keyBinding = serialized.hasSuffix("~") ? nil : parts.last
        let disclosureStrings = Array(parts.dropFirst().dropLast()).filter { !$0.isEmpty }

        let (header, payload) = try decode(jwt)
        guard header["alg"] as? String == "ES256" else {
            throw SDJWTVCError.unsupportedAlgorithm(header["alg"] as? String ?? "")
        }
        guard let issuer = payload["iss"] as? String else { throw SDJWTVCError.malformed }
        let issuerKey: P256.Signing.PublicKey
        if let key = try? JWKDIDKey.p256PublicKey(fromDID: issuer) {
            issuerKey = key
        } else if let key = try? DIDKey.p256PublicKey(fromDID: issuer) {
            issuerKey = key
        } else {
            throw SDJWTVCError.issuerNotResolvable
        }
        try verify(jwt, with: issuerKey)
        if let exp = payload["exp"] as? Int, Date(timeIntervalSince1970: TimeInterval(exp)) < now {
            throw SDJWTVCError.expired
        }
        guard let vct = payload["vct"] as? String else { throw SDJWTVCError.malformed }
        if let alg = payload["_sd_alg"] as? String, alg != SDJWTVC.digestAlgorithm {
            throw SDJWTVCError.unsupportedAlgorithm(alg)
        }
        let committed = payload["_sd"] as? [String] ?? []
        let claims: [(name: String, value: String)]
        do {
            claims = try SelectiveDisclosure.reveal(disclosures: disclosureStrings, committedDigests: committed)
        } catch SelectiveDisclosure.DisclosureError.undisclosedDigest(let digest) {
            throw SDJWTVCError.undisclosedDigest(digest)
        } catch {
            throw SDJWTVCError.malformed
        }

        var keyBound = false
        if let keyBinding {
            guard let cnf = payload["cnf"] as? [String: Any], let jwk = cnf["jwk"] as? [String: Any],
                  let jwkData = try? JSONSerialization.data(withJSONObject: jwk),
                  let holderKey = try? JWKDIDKey.p256PublicKey(fromJWKBytes: jwkData) else {
                throw SDJWTVCError.keyBindingInvalid("cnf")
            }
            let (kbHeader, kbPayload) = try decode(keyBinding)
            guard kbHeader["typ"] as? String == SDJWTVC.keyBindingTyp else {
                throw SDJWTVCError.keyBindingInvalid("typ")
            }
            try verify(keyBinding, with: holderKey)
            let presented = String(serialized[..<serialized.index(after: serialized.lastIndex(of: "~")!)])
            guard kbPayload["sd_hash"] as? String == SDJWTVC.sdHash(of: presented) else {
                throw SDJWTVCError.keyBindingInvalid("sd_hash")
            }
            if let expectedAudience, kbPayload["aud"] as? String != expectedAudience {
                throw SDJWTVCError.keyBindingInvalid("aud")
            }
            if let expectedNonce, kbPayload["nonce"] as? String != expectedNonce {
                throw SDJWTVCError.keyBindingInvalid("nonce")
            }
            keyBound = true
        } else if expectedNonce != nil || expectedAudience != nil {
            throw SDJWTVCError.keyBindingMissing
        }

        let strings = payload.compactMapValues { $0 as? String }
        return SDJWTVCVerified(vct: vct, issuer: issuer, payload: strings, claims: claims, keyBound: keyBound)
    }

    /// The raw JSON payload of the issuer JWT, for nested claims such as
    /// `source` and `rule`. Does **not** verify; call `read` first.
    static func rawPayload(_ serialized: String) throws -> [String: Any] {
        guard let jwt = serialized.split(separator: "~", omittingEmptySubsequences: false).first else {
            throw SDJWTVCError.malformed
        }
        return try decode(String(jwt)).payload
    }

    private static func decode(_ jwt: String) throws -> (header: [String: Any], payload: [String: Any]) {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Data(base64URLEncoded: parts[0]),
              let payloadData = Data(base64URLEncoded: parts[1]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw SDJWTVCError.malformed
        }
        return (header, payload)
    }

    private static func verify(_ jwt: String, with key: P256.Signing.PublicKey) throws {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let raw = Data(base64URLEncoded: parts[2]),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: raw) else {
            throw SDJWTVCError.malformed
        }
        guard key.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)) else {
            throw SDJWTVCError.signatureInvalid
        }
    }
}
