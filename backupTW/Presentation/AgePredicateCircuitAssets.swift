//
//  AgePredicateCircuitAssets.swift
//  backupTW
//
//  Immutable runtime files for the OpenAC field-predicate profile. Downloads use
//  the app's existing resumable, pinned CircuitAssets implementation; this file
//  only defines the independently reviewable manifest and holder/checker split.
//

import Foundation

enum AgePredicateAssetRole: Sendable {
    case prover
    case verifier
}

enum AgePredicateCircuitAssetCatalog {
    static let releaseTag = "openac-field-v2"

    private static let release = URL(
        string: "https://github.com/bonds-tw/backupTW-iOS/releases/download/\(releaseTag)")!

    private static func asset(name: String,
                              remoteFilename: String,
                              localFilename: String,
                              compressedByteCount: Int64,
                              installedByteCount: Int64,
                              compressedSHA256: String,
                              installedSHA256: String) -> CircuitAsset {
        CircuitAsset(
            name: name,
            remoteURL: release.appendingPathComponent(remoteFilename),
            localFilename: localFilename,
            sha256: compressedSHA256,
            compressedByteCount: compressedByteCount,
            installedByteCount: installedByteCount,
            installedSHA256: installedSHA256)
    }

    // Filled only from the release-gate vector's generated manifest. Both the
    // compressed transport and the exact bytes opened by the native verifier
    // are pinned so a republished GitHub asset cannot silently change policy.
    static let jwtR1CS = asset(
        name: "openac_age_jwt_r1cs",
        remoteFilename: "jwt_2k.r1cs.gz",
        localFilename: "circom/build/jwt/jwt_js/jwt.r1cs",
        compressedByteCount: 28_373_678,
        installedByteCount: 374_893_516,
        compressedSHA256: "e60d73921d1935789a6d237949be72500cda0b3b39e196ae87016be26e68de3b",
        installedSHA256: "1ef44eb4889b19c71f6cec0f9cf91da04588346b2a262fb67739ff2ab691f0ad")

    static let showR1CS = asset(
        name: "openac_age_show_r1cs",
        remoteFilename: "show.r1cs.gz",
        localFilename: "circom/build/show/show_js/show.r1cs",
        compressedByteCount: 590_996,
        installedByteCount: 4_025_780,
        compressedSHA256: "0e537a97c34eea829fc945f5287853eaf576fc1963c51c607209f71eef1e010c",
        installedSHA256: "683162facd8636e062835cad414775fe2569f4e946493d1d55bfa56589858fba")

    static let prepareProvingKey = asset(
        name: "openac_age_prepare_proving",
        remoteFilename: "prepare_proving.key.gz",
        localFilename: "circom/keys/prepare_proving.key",
        compressedByteCount: 23_772_560,
        installedByteCount: 432_432_554,
        compressedSHA256: "6518606f1f6ae38bfbda1a19727748902c2c0b51aa545adef251a129701fb3df",
        installedSHA256: "167eb76c59505bd50b8a061bc5005960011e0877a4f663d6ddd395c0502119f4")

    static let prepareVerifyingKey = asset(
        name: "openac_age_prepare_verifying",
        remoteFilename: "prepare_verifying.key.gz",
        localFilename: "circom/keys/prepare_verifying.key",
        compressedByteCount: 23_772_504,
        installedByteCount: 432_432_522,
        compressedSHA256: "8fe4867ea95094b06c484862f3af8b0271f41088482bf495ae76b76c7da8fbe5",
        installedSHA256: "81f29f3a11e45a2e1b728c290f8af87ac8c8548fd049ac176897a583d83f5347")

    static let showProvingKey = asset(
        name: "openac_age_show_proving",
        remoteFilename: "show_proving.key.gz",
        localFilename: "circom/keys/show_proving.key",
        compressedByteCount: 576_612,
        installedByteCount: 4_871_018,
        compressedSHA256: "cf74a3e8f58be86d0e6faf68786e5b28952d4548485e394843b8e0340039d32d",
        installedSHA256: "8008c16e150736e595e0a3f9ebe31e57a56c7603e3348efa09618f696e275c61")

    static let showVerifyingKey = asset(
        name: "openac_age_show_verifying",
        remoteFilename: "show_verifying.key.gz",
        localFilename: "circom/keys/show_verifying.key",
        compressedByteCount: 576_575,
        installedByteCount: 4_870_986,
        compressedSHA256: "ae9df7e79ae7cabd8c87cfc7b27d39117618a6aeec459d1bb5c985f4bc0ff988",
        installedSHA256: "f112a4953b4af7f1aca5c561671cff6f11860b0d727b47418f30ed45f0e10258")

    /// A phone producing a proof needs the two constraints and both key pairs.
    /// Keeping the verifying keys here also lets it fail closed by checking its
    /// own newly created linked proof before anything is sent.
    static let proverAssets = [jwtR1CS, showR1CS,
                               prepareProvingKey, prepareVerifyingKey,
                               showProvingKey, showVerifyingKey]

    /// The iPad opens only public verification keys. It never downloads the
    /// holder's R1CS or proving keys merely to check a received proof.
    static let verifierAssets = [prepareVerifyingKey, showVerifyingKey]

    static func assets(for role: AgePredicateAssetRole) -> [CircuitAsset] {
        switch role {
        case .prover: proverAssets
        case .verifier: verifierAssets
        }
    }

    static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        return base.appendingPathComponent("OpenACField-v2", isDirectory: true)
    }
}

actor AgePredicateCircuitAssetPreparer {
    typealias Progress = @Sendable (Double) -> Void

    private let directory: URL

    init(directory: URL? = nil) throws {
        self.directory = try directory ?? AgePredicateCircuitAssetCatalog.defaultDirectory()
    }

    /// Returns the `documentsPath` expected by the Mopro mobile binding.
    func prepare(_ role: AgePredicateAssetRole,
                 allowDownloads: Bool = true,
                 progress: @escaping Progress = { _ in }) async throws -> URL {
        let assets = AgePredicateCircuitAssetCatalog.assets(for: role)
        let store = CircuitAssets.makeNetworkStore(directory: directory, assets: assets)
        let inspections = await store.inspectInstalledAssets()
        let needed = inspections.filter { !$0.integrity.isValid }
        if needed.isEmpty {
            progress(1)
            return directory.appendingPathComponent("circom", isDirectory: true)
        }

        // Once a local request is being answered, missing/corrupt material must
        // never trigger a repair download in the middle of an offline check.
        guard allowDownloads else { throw AgePredicateProofError.offlineAssetsMissing }

        let total = max(Int64(1), needed.reduce(0) { $0 + max(Int64(1), $1.asset.compressedByteCount) })
        var completed: Int64 = 0
        for inspection in needed {
            let asset = inspection.asset
            if inspection.integrity.needsRepair {
                let isolated = CircuitAssets.makeNetworkStore(directory: directory, assets: [asset])
                try await isolated.deleteAll()
            }
            let weight = max(Int64(1), asset.compressedByteCount)
            let completedBeforeAsset = completed
            _ = try await store.download(asset) { fraction in
                progress((Double(completedBeforeAsset) + Double(weight) * fraction) / Double(total))
            }
            completed += weight
            progress(Double(completed) / Double(total))
        }

        let final = await store.inspectInstalledAssets()
        guard final.allSatisfy(\.integrity.isValid) else {
            throw AgePredicateProofError.nativeEngineUnavailable
        }
        return directory.appendingPathComponent("circom", isDirectory: true)
    }
}
