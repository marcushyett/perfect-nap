import SwiftUI
import UIKit
import CloudKit

/// Identifiable wrapper carrying the invite text + link, so it can drive a SwiftUI `.sheet(item:)`.
struct ShareInvite: Identifiable {
    let id = UUID()
    let message: String
    let url: URL
    /// We share the link as **plain text**, never as a `URL`/`CKShare` object. iOS recognises a
    /// CKShare URL handed to `UIActivityViewController` and hijacks the flow into its own multi-step
    /// "Create Link → add people" collaboration sheet (the thing we're trying to avoid). A plain
    /// string is treated as ordinary text, so the recipient just gets a tappable link — which still
    /// routes through `userDidAcceptCloudKitShareWith` when they open it.
    var activityItems: [Any] { ["\(message)\n\(url.absoluteString)"] }
}

/// A plain one-step iOS share sheet for the invite link. Tap once → pick WhatsApp / Messages / Copy
/// → send. The link is "anyone with the link can view & log", so there's no per-person invite step
/// (which is what was failing before).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let invite: ShareInvite
    var onDismiss: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: invite.activityItems, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
            onDismiss()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Hooks the CloudKit share-acceptance callback (fired when the partner taps the invite link) into
/// the sharing coordinator. SwiftUI's App lifecycle has no native hook, so we route it through a
/// scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareAcceptSceneDelegate.self
        return config
    }
}

final class ShareAcceptSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            SharingCoordinator.shared.acceptShare(cloudKitShareMetadata)
        }
    }
}
