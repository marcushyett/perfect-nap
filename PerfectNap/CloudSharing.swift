import SwiftUI
import UIKit
import CloudKit

/// Identifiable wrapper so a CKShare + container can drive a SwiftUI `.sheet(item:)`.
struct SharePackage: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Presents the system share sheet for a CKShare — this is what produces the "send them a link"
/// invitation (Messages, AirDrop, copy link, etc.).
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // Allow the "anyone with the link" option as well as private invites — so a link can be sent
        // through any channel (WhatsApp, etc.) without needing the recipient's Apple ID.
        controller.availablePermissions = [.allowReadWrite, .allowPublic, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(share: share) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let share: CKShare
        init(share: CKShare) { self.share = share }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            share[CKShare.SystemFieldKey.title] as? String ?? "Baby's sleep"
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            #if DEBUG
            print("CKShare save failed: \(error)")
            #endif
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        }
    }
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
