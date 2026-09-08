//
//  SimulatedCardHomeTests.swift
//  backupTWTests
//
//  A simulated (sandbox) card is shown in its own home group, below the MyData
//  vault, and never among the real government cards. See docs/sandbox-issuer.md
//  and HomeViewController.simulatedSection.
//

import Foundation
import Testing
import UIKit
@testable import backupTW

@MainActor
struct SimulatedCardHomeTests {

    private final class MemoryStore: CredentialStoring, @unchecked Sendable {
        private var items: [String: String] = [:]
        func save(jws: String, id: String) throws { items[id] = jws }
        func load(id: String) throws -> String? { items[id] }
        func allIDs() throws -> [String] { Array(items.keys).sorted() }
        func delete(id: String) throws { items.removeValue(forKey: id) }
        func deleteAll() throws { items.removeAll() }
    }

    private func tempVault() throws -> MyDataVaultArchive {
        try MyDataVaultArchive(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("SimCardVaultTests-\(UUID().uuidString)", isDirectory: true))
    }

    private func mountedHome(store: CredentialStoring, archive: MyDataVaultArchive)
        -> (HomeViewController, UINavigationController) {
        let controller = HomeViewController(
            makeStore: { store },
            makeVaultArchive: { archive },
            makeOfficialDocumentInbox: { nil })
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.isHidden = false
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        window.layoutIfNeeded()
        return (controller, navigation)
    }

    /// A simulated card is classified as such by `CardInventory`, its face named
    /// for the pinned sandbox issuer, while a real government fixture is not.
    @Test func cardInventoryFlagsOnlyTheSandboxTypedCard() throws {
        let store = MemoryStore()
        try store.save(jws: TWDIWFixture().withCredentialType("sandbox_membership_card_v1"), id: "sim-1")
        try store.save(jws: TWDIWFixture().serialized, id: "gov-1") // production `…_demo_…` type
        let rows = CardInventory.rows(from: store)
        let sim = try #require(rows.first { $0.id == "sim-1" })
        let gov = try #require(rows.first { $0.id == "gov-1" })
        #expect(sim.isSimulated)
        #expect(!gov.isSimulated)
    }

    /// The home screen puts the simulated card in a group of its own that sits
    /// below the MyData vault, keeps the real government card in the government
    /// group above, and does not add the group when no simulated card is held.
    @Test func aSimulatedCardGetsItsOwnGroupBelowTheVault() throws {
        let store = MemoryStore()
        let archive = try tempVault()

        // With no simulated card, the section is absent: five sections, exactly
        // as before this feature (national ID / government / vault / import /
        // official documents).
        try store.save(jws: TWDIWFixture().serialized, id: "gov-1")
        let (before, _) = mountedHome(store: store, archive: archive)
        #expect(before.collectionView.numberOfSections == 5)

        // Add a simulated card: a sixth section appears, and it is below the
        // vault and its import row (index 4), above official documents (index 5).
        try store.save(jws: TWDIWFixture().withCredentialType("sandbox_driverlicense_car_v1"), id: "sim-1")
        let (after, _) = mountedHome(store: store, archive: archive)
        #expect(after.collectionView.numberOfSections == 6)
        #expect(after.collectionView.numberOfItems(inSection: 1) == 1) // government: the real card only
        #expect(after.collectionView.numberOfItems(inSection: 4) == 1) // simulated: the sandbox card only
    }
}
