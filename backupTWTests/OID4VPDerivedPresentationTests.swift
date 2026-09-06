//
//  OID4VPDerivedPresentationTests.swift
//  backupTWTests
//
//  A verifier asks a question of a vault original. What goes back is one
//  freshly signed answer, nothing else.
//

import CryptoKit
import Foundation
import Testing
@testable import backupTW

// MARK: - Fixtures

/// Signs OpenID4VP 1.0 requests in DCQL, the way verifier.mashbean.net asks
/// for a vault-derived credential.
private struct DerivedTestVerifier {
    let privateKey = P256.Signing.PrivateKey()

    var clientID: String {
        (try? JWKDIDKey.did(fromP256PublicKeyX963: privateKey.publicKey.x963Representation)) ?? ""
    }

    func dcqlRequest(responseURI: String,
                     nonce: String = "N-DERIVED",
                     state: String = "S-DERIVED",
                     credentialID: String = "income",
                     vct: String = MyDataDerivedCredentialType.income.vct,
                     claims: [String] = ["tax_year", "income_within_ceiling"],
                     rule: [String: Any]? = ["id": "income-ceiling/v1",
                                             "params": ["tax_year": "2024", "ceiling_twd": "1500000"]]) -> String {
        var payload: [String: Any] = [
            "response_type": "vp_token",
            "response_mode": "direct_post",
            "response_uri": responseURI,
            "client_id": clientID,
            "nonce": nonce,
            "state": state,
            "dcql_query": ["credentials": [[
                "id": credentialID,
                "format": "dc+sd-jwt",
                "meta": ["vct_values": [vct]],
                "claims": claims.map { ["path": [$0]] },
            ]]],
        ]
        if let rule { payload["bonds_rule"] = rule }
        return sign(payload)
    }

    /// The same ask in Presentation Exchange, for a verifier that has not
    /// moved to DCQL: `format` names `dc+sd-jwt`, `$.vct` names the type.
    func presentationExchangeRequest(responseURI: String) -> String {
        let payload: [String: Any] = [
            "response_type": "vp_token",
            "response_mode": "direct_post",
            "response_uri": responseURI,
            "client_id": clientID,
            "nonce": "N-PE",
            "state": "S-PE",
            "bonds_rule": ["id": "income-ceiling/v1", "params": ["tax_year": "2024", "ceiling_twd": "1500000"]],
            "presentation_definition": [
                "id": "mashbean-vp",
                "input_descriptors": [[
                    "id": "income",
                    "format": ["dc+sd-jwt": ["sd-jwt_alg_values": ["ES256"], "kb-jwt_alg_values": ["ES256"]]],
                    "constraints": ["fields": [
                        ["path": ["$.vct"], "filter": ["type": "string", "const": MyDataDerivedCredentialType.income.vct]],
                        ["path": ["$.income_within_ceiling"]],
                    ]],
                ]],
            ],
        ]
        return sign(payload)
    }

    private func sign(_ payload: [String: Any]) -> String {
        let header: [String: Any] = ["kid": "verifier-did", "typ": "oauth-authz-req+jwt", "alg": "ES256"]
        func json(_ o: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        }
        let h = json(header).base64URLEncodedString()
        let p = json(payload).base64URLEncodedString()
        let sig = (try? privateKey.signature(for: Data("\(h).\(p)".utf8)))?.rawRepresentation ?? Data()
        return "\(h).\(p).\(sig.base64URLEncodedString())"
    }
}

/// A vault with whatever originals a test puts in it — page text, not PDFs.
private struct MemoryVault: MyDataVaultDocumentSource {
    var documents: [MyDataVaultSourceDocument] = []
    var opened: [String] = []

    static func with(_ entries: [(id: String, type: String?, text: String)]) -> MemoryVault {
        MemoryVault(documents: entries.map { entry in
            MyDataVaultSourceDocument(
                id: entry.id, documentTypeID: entry.type,
                sha256: SHA256.hash(data: Data(entry.text.utf8)).map { String(format: "%02x", $0) }.joined(),
                text: { entry.text })
        })
    }

    func derivableDocuments() throws -> [MyDataVaultSourceDocument] { documents }
}

/// This suite's own transport stub — its own class so Swift Testing's
/// concurrent suites cannot clear each other's routes (see OID4VPTests).
final class OID4VPDerivedStubURLProtocol: URLProtocol {
    struct Exchange {
        let url: URL
        let body: Data
        var form: [String: String] {
            Dictionary(uniqueKeysWithValues: String(decoding: body, as: UTF8.self)
                .split(separator: "&").compactMap { pair -> (String, String)? in
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return nil }
                    return (parts[0], parts[1].removingPercentEncoding ?? parts[1])
                })
        }
    }
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var exchanges: [Exchange] = []
    static func reset() { status = 200; exchanges = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                guard read > 0 else { break }
                body.append(buffer, count: read)
            }
        }
        Self.exchanges.append(Exchange(url: request.url!, body: body))
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// MARK: - Request

@Suite("DCQL 請求：讀得出型別、欄位與規則")
struct OID4VPDCQLRequestTests {

    static let trusted: Set<String> = ["verifier.mashbean.net"]
    static let responseURI = "https://verifier.mashbean.net/api/response/abc"

    @Test func aDCQLRequestReducesToOneDescriptorPerCredentialQuery() throws {
        let verifier = DerivedTestVerifier()
        let request = try OID4VPRequest.verify(compactJWS: verifier.dcqlRequest(responseURI: Self.responseURI),
                                               clientID: verifier.clientID,
                                               trustedResponseHosts: Self.trusted)
        #expect(request.queryLanguage == .dcql)
        #expect(request.definitionID == "")
        #expect(request.inputDescriptors.map(\.id) == ["income"])
        #expect(request.inputDescriptors.first?.credentialFormat == .sdJWTVC)
        #expect(request.inputDescriptors.first?.credentialType == MyDataDerivedCredentialType.income.vct)
        #expect(request.requestedFields.compactMap(\.claimName) == ["tax_year", "income_within_ceiling"])
        #expect(request.rule == MyDataDisclosureRule(id: "income-ceiling/v1",
                                                     params: ["tax_year": "2024", "ceiling_twd": "1500000"]))
    }

    @Test func aPresentationExchangeAskForTheSameTypeReadsTheSame() throws {
        let verifier = DerivedTestVerifier()
        let request = try OID4VPRequest.verify(
            compactJWS: verifier.presentationExchangeRequest(responseURI: Self.responseURI),
            clientID: verifier.clientID, trustedResponseHosts: Self.trusted)
        #expect(request.queryLanguage == .presentationExchange)
        #expect(request.inputDescriptors.first?.credentialFormat == .sdJWTVC)
        #expect(request.inputDescriptors.first?.credentialType == MyDataDerivedCredentialType.income.vct)
        #expect(request.requestedFields.compactMap(\.claimName) == ["income_within_ceiling"])
        #expect(request.rule?.id == "income-ceiling/v1")
    }

    @Test func envelopeFieldsAreNeverSwitches() {
        #expect(OID4VPRequestedField(path: "$.vct").claimName == nil)
        #expect(OID4VPRequestedField(path: "$.cnf").claimName == nil)
        #expect(OID4VPRequestedField(path: "$.source.sha256").claimName == nil)
        #expect(OID4VPRequestedField(path: "$.tax_year").claimName == "tax_year")
        #expect(OID4VPRequestedField(path: "$.vc.credentialSubject.name").claimName == "name")
        #expect(OID4VPRequestedField(path: "$.credentialSubject.name").claimName == "name")
    }

    @Test func aRuleWhoseParamsAreNotStringsIsDropped() throws {
        let verifier = DerivedTestVerifier()
        let jwt = verifier.dcqlRequest(responseURI: Self.responseURI,
                                       rule: ["id": "income-ceiling/v1", "params": ["ceiling_twd": 1]])
        let request = try OID4VPRequest.verify(compactJWS: jwt, clientID: verifier.clientID,
                                               trustedResponseHosts: Self.trusted)
        #expect(request.rule == nil)
    }
}

// MARK: - Response

@Suite("衍生憑證出示：只簽這個問題的答案", .serialized)
struct OID4VPDerivedResponseTests {

    static let responseURI = "https://verifier.mashbean.net/api/response/abc"
    static let trusted: Set<String> = ["verifier.mashbean.net"]

    private let store: CredentialStore
    private let keyring: HolderKeyring

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oid4vp-derived-\(UUID().uuidString)")
        store = try CredentialStore(directory: dir)
        keyring = HolderKeyring(namespace: "tw.bonds.backupTW.tests.derived\(UUID().uuidString.prefix(8)).",
                                legacyTags: [], installID: "test", legacyInstallRecord: nil)
    }

    private func responder(vault: MyDataVaultDocumentSource?) -> OID4VPResponder {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OID4VPDerivedStubURLProtocol.self]
        var responder = OID4VPResponder(session: URLSession(configuration: config), store: store, keyring: keyring)
        responder.vault = vault
        return responder
    }

    private func incomeVault() -> MemoryVault {
        .with([("mydata-income", "mydata-income", MyDataIncomeParserTests.statement),
               ("mydata-household", "mydata-household", MyDataHouseholdParserTests.record)])
    }

    private func request(_ verifier: DerivedTestVerifier, _ jwt: String) throws -> OID4VPRequest {
        try OID4VPRequest.verify(compactJWS: jwt, clientID: verifier.clientID, trustedResponseHosts: Self.trusted)
    }

    @Test func aDCQLAnswerIsAnObjectKeyedByCredentialQueryIdWithNoSubmission() async throws {
        OID4VPDerivedStubURLProtocol.reset()
        defer { OID4VPDerivedStubURLProtocol.reset() }
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI))
        let vault = incomeVault()

        let receipt = try await responder(vault: vault).respondWithReceipt(
            to: request, disclosing: ["income_within_ceiling", "tax_year"])
        #expect(receipt.statusCode == 200)
        #expect(receipt.holderKey == nil)

        let exchange = try #require(OID4VPDerivedStubURLProtocol.exchanges.first)
        #expect(exchange.url.absoluteString == Self.responseURI)
        let form = exchange.form
        #expect(form["state"] == "S-DERIVED")
        #expect(form["presentation_submission"] == nil)
        let token = try #require(form["vp_token"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(token.utf8)) as? [String: String])
        let presentation = try #require(object["income"])

        // What the verifier will do with it: read it back against its own
        // nonce and audience.
        let read = try SDJWTVCReader.read(presentation, expectedAudience: verifier.clientID,
                                          expectedNonce: "N-DERIVED")
        #expect(read.keyBound)
        #expect(read.vct == MyDataDerivedCredentialType.income.vct)
        #expect(read.issuer == receipt.holderDID)
        #expect(Set(read.claims.map(\.name)) == ["income_within_ceiling", "tax_year"])
        #expect(read.claims.first { $0.name == "income_within_ceiling" }?.value == "true")
        #expect(read.payload["assurance"] == "holder-derived")

        let payload = try SDJWTVCReader.rawPayload(presentation)
        let source = try #require(payload["source"] as? [String: Any])
        #expect(source["sha256"] as? String == vault.documents[0].sha256)
        #expect(source["parser"] as? String == "income-pdf/v1")
        #expect(source["document_type"] as? String == "mydata-income")
        let rule = try #require(payload["rule"] as? [String: Any])
        #expect(rule["id"] as? String == "income-ceiling/v1")
        #expect((rule["params"] as? [String: String]) == ["tax_year": "2024", "ceiling_twd": "1500000"])
        // Every claim of the type is committed, so a claim not chosen is still
        // withheld rather than absent.
        #expect((payload["_sd"] as? [String])?.count == 3)
        #expect(payload["vct#integrity"] as? String == MyDataDerivedCredentialType.income.vctIntegrity)
    }

    @Test func withholdingAClaimKeepsItOutOfTheToken() async throws {
        OID4VPDerivedStubURLProtocol.reset()
        defer { OID4VPDerivedStubURLProtocol.reset() }
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI))
        _ = try await responder(vault: incomeVault()).respond(to: request, disclosing: ["income_within_ceiling"])
        let token = try #require(OID4VPDerivedStubURLProtocol.exchanges.first?.form["vp_token"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(token.utf8)) as? [String: String])
        let presentation = try #require(object["income"])
        let read = try SDJWTVCReader.read(presentation)
        #expect(read.claims.map(\.name) == ["income_within_ceiling"])
    }

    @Test func twoPresentationsShareNoKey() async throws {
        OID4VPDerivedStubURLProtocol.reset()
        defer { OID4VPDerivedStubURLProtocol.reset() }
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI))
        let first = try await responder(vault: incomeVault()).respondWithReceipt(to: request, disclosing: ["tax_year"])
        let second = try await responder(vault: incomeVault()).respondWithReceipt(to: request, disclosing: ["tax_year"])
        #expect(first.holderDID != second.holderDID)
        // The presenter never touches the keyring: the key lived in memory for
        // the duration of one mint. (`entries()` itself needs a Keychain
        // entitlement the simulator test host lacks, so residue is asserted by
        // construction — `MyDataDerivedPresenter` takes no keyring at all.)
    }

    @Test func aPresentationExchangeAskGetsABareTokenAndADCSDJWTSubmission() async throws {
        OID4VPDerivedStubURLProtocol.reset()
        defer { OID4VPDerivedStubURLProtocol.reset() }
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.presentationExchangeRequest(responseURI: Self.responseURI))
        _ = try await responder(vault: incomeVault()).respond(to: request, disclosing: ["income_within_ceiling"])
        let form = try #require(OID4VPDerivedStubURLProtocol.exchanges.first?.form)
        let token = try #require(form["vp_token"])
        #expect(token.hasPrefix("ey"), "a bare SD-JWT VC, not a JSON object")
        let submissionText = try #require(form["presentation_submission"])
        let submission = try #require(JSONSerialization.jsonObject(
            with: Data(submissionText.utf8)) as? [String: Any])
        #expect(submission["definition_id"] as? String == "mashbean-vp")
        let map = try #require((submission["descriptor_map"] as? [[String: Any]])?.first)
        #expect(map["id"] as? String == "income")
        #expect(map["format"] as? String == "dc+sd-jwt")
        #expect(map["path"] as? String == "$")
        #expect(try SDJWTVCReader.read(token, expectedAudience: verifier.clientID, expectedNonce: "N-PE").keyBound)
    }

    @Test func noOriginalOfThatKindIsSaidPlainly() async throws {
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI))
        let vault = MemoryVault.with([("mydata-household", "mydata-household", MyDataHouseholdParserTests.record)])
        await #expect(throws: OID4VPResponseError.sourceDocumentUnavailable) {
            _ = try await responder(vault: vault).respond(to: request, disclosing: ["tax_year"])
        }
        await #expect(throws: OID4VPResponseError.sourceDocumentUnavailable) {
            _ = try await responder(vault: nil).respond(to: request, disclosing: ["tax_year"])
        }
        #expect(OID4VPDerivedStubURLProtocol.exchanges.isEmpty, "nothing was posted")
    }

    @Test func aRequestWithoutARuleIsRefused() async throws {
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI, rule: nil))
        await #expect(throws: OID4VPResponseError.ruleMissing) {
            _ = try await responder(vault: incomeVault()).respond(to: request, disclosing: ["tax_year"])
        }
    }

    @Test func aRuleTheDocumentDoesNotCoverIsRefusedNotAnsweredFalse() async throws {
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(
            responseURI: Self.responseURI,
            rule: ["id": "income-ceiling/v1", "params": ["tax_year": "2023", "ceiling_twd": "1"]]))
        await #expect(throws: OID4VPResponseError.derivation(.documentDoesNotCoverRule("tax_year"))) {
            _ = try await responder(vault: incomeVault()).respond(to: request, disclosing: ["income_within_ceiling"])
        }
    }

    @Test func anOriginalThatDoesNotParseIsRefused() async throws {
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI))
        let vault = MemoryVault.with([("mydata-income", "mydata-income", "這是一份別的文件，沒有任何所得欄位")])
        await #expect(throws: OID4VPResponseError.sourceDocumentUnreadable(.notThisDocument)) {
            _ = try await responder(vault: vault).respond(to: request, disclosing: ["tax_year"])
        }
    }

    @Test func aClaimOutsideTheTypeIsRefused() async throws {
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(responseURI: Self.responseURI,
                                                                 claims: ["tax_year", "income_total_twd"]))
        await #expect(throws: OID4VPResponseError.requestedClaimNotAvailable("income_total_twd")) {
            _ = try await responder(vault: incomeVault()).respond(to: request, disclosing: ["tax_year"])
        }
    }

    @Test func anInsuranceQuestionUsesTheInsuranceOriginal() async throws {
        OID4VPDerivedStubURLProtocol.reset()
        defer { OID4VPDerivedStubURLProtocol.reset() }
        let verifier = DerivedTestVerifier()
        let request = try request(verifier, verifier.dcqlRequest(
            responseURI: Self.responseURI, credentialID: "insurance",
            vct: MyDataDerivedCredentialType.laborInsurance.vct,
            claims: ["on_date", "insured_on_date"],
            rule: ["id": "insurance-active/v1", "params": ["on_date": "2026-09-01"]]))
        let vault = MemoryVault.with([
            ("mydata-income", "mydata-income", MyDataIncomeParserTests.statement),
            ("mydata-labor-insurance", "mydata-labor-insurance", MyDataLaborInsuranceParserTests.record),
        ])
        _ = try await responder(vault: vault).respond(to: request, disclosing: ["on_date", "insured_on_date"])
        let token = try #require(OID4VPDerivedStubURLProtocol.exchanges.first?.form["vp_token"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(token.utf8)) as? [String: String])
        let presentation = try #require(object["insurance"])
        let read = try SDJWTVCReader.read(presentation)
        #expect(read.vct == MyDataDerivedCredentialType.laborInsurance.vct)
        #expect(read.claims.first { $0.name == "insured_on_date" }?.value == "true")
    }
}
