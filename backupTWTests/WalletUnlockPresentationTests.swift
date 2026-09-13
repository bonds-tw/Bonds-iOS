import Testing
import UIKit
@testable import backupTW

@MainActor
@Suite(.serialized)
struct WalletUnlockPresentationTests {
    @Test func unlockingPreservesThePresentedDialogAndItsContents() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let root = UIViewController()
        let main = UIWindow(windowScene: scene)
        main.rootViewController = root
        main.makeKeyAndVisible()
        defer { main.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        let dialog = UIAlertController(title: "MyData", message: "Continue verification", preferredStyle: .alert)
        dialog.addTextField { $0.text = "fixture form value" }
        dialog.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(dialog, animated: false)
        let delegate = SceneDelegate()
        delegate.window = main
        // Resolve against this test's scene owner, not the host app's initial
        // login screen, which belongs to a different SceneDelegate instance.
        let previousDelegate = scene.delegate
        scene.delegate = delegate
        defer { scene.delegate = previousDelegate }
        delegate.sceneDidBecomeActive(scene)
        let overlay = try #require(scene.windows.first { $0.isKeyWindow })
        let unlock = try #require(overlay.rootViewController as? WalletUnlockViewController)
        #expect(overlay !== main)
        #expect(overlay.windowLevel > main.windowLevel)
        #expect(root.presentedViewController === dialog)
        #expect(dialog.presentedViewController == nil)
        #expect(ErrorCatcher.resolvePresenter(explicit: root) === dialog)
        #expect(!(ErrorCatcher.resolvePresenter(explicit: nil) is WalletUnlockViewController),
                "A background error result must never cover the unlock controls")
        delegate.sceneDidBecomeActive(scene)
        #expect(scene.windows.first { $0.isKeyWindow } === overlay)
        // Exercise completion without invoking a real biometric request.
        unlock.onUnlocked?()
        #expect(overlay.isHidden)
        #expect(main.isKeyWindow)
        #expect(root.presentedViewController === dialog)
        #expect(dialog.textFields?.first?.text == "fixture form value")
        root.dismiss(animated: false)
    }
}
