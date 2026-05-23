import Foundation
import CoreData
import CloudKit

/// Manages CloudKit sharing of the baby + its sessions between two parents.
/// Built on NSPersistentCloudKitContainer's share APIs: the first parent creates a CKShare for the
/// Baby record (sessions follow via the same record zone), hands the partner a share link, and the
/// partner accepts it into their shared store. Both then read/write the same records.
@MainActor
final class SharingCoordinator {
    static let shared = SharingCoordinator()
    private init() {}

    private var container: NSPersistentCloudKitContainer { CoreDataStack.shared.container }

    enum ShareState {
        case notShared
        case shared(participantCount: Int, isOwner: Bool)
    }

    /// Existing share for the baby, if any.
    func existingShare(for baby: Baby) -> CKShare? {
        try? container.fetchShares(matching: [baby.objectID])[baby.objectID]
    }

    /// Name of the person who shared this baby with us (nil if not shared / unknown).
    func ownerDisplayName(for baby: Baby) -> String? {
        guard let share = existingShare(for: baby),
              let owner = share.participants.first(where: { $0.role == .owner }),
              let components = owner.userIdentity.nameComponents else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: components)
        return formatted.isEmpty ? nil : formatted
    }

    func shareState(for baby: Baby) -> ShareState {
        guard let share = existingShare(for: baby) else { return .notShared }
        let isOwner = share.currentUserParticipant?.role == .owner
        // Participants beyond the owner = people actually invited/joined.
        let others = share.participants.filter { $0.role != .owner }.count
        return .shared(participantCount: others, isOwner: isOwner)
    }

    enum SharingError: LocalizedError {
        case linkUnavailable
        var errorDescription: String? { "Couldn't create the invite link. Check your iCloud sign-in and try again." }
    }

    /// One-step invite: creates (or reuses) a **public read-write** CKShare for the baby and returns
    /// its link. The link itself is the access control — anyone who opens it joins and can view + log,
    /// so it can be sent through *any* channel (WhatsApp, Messages, …) with no Apple-ID lookup and no
    /// per-person invite step. We persist `publicPermission` via `persistUpdatedShare` so the URL is
    /// materialised before we hand it to the share sheet.
    func shareURL(for baby: Baby) async throws -> URL {
        #if targetEnvironment(simulator)
        // CloudKit is disabled in the simulator (unsigned, no entitlement) — return a demo link so the
        // share-sheet UX is still exercisable. Real links are produced on device.
        return URL(string: "https://www.icloud.com/share/perfectnap-demo")!
        #else
        if let existing = existingShare(for: baby), let url = existing.url { return url }
        let (_, share, _) = try await container.share([baby], to: nil)
        share[CKShare.SystemFieldKey.title] = "\(baby.displayName)'s sleep on Perfect Nap" as CKRecordValue
        share.publicPermission = .readWrite
        guard let privateStore = CoreDataStack.shared.privatePersistentStore else {
            throw SharingError.linkUnavailable
        }
        let updated = try await container.persistUpdatedShare(share, in: privateStore)
        guard let url = updated.url else { throw SharingError.linkUnavailable }
        return url
        #endif
    }

    /// Stop sharing entirely (owner) — removes the share so the partner loses access.
    func stopSharing(_ baby: Baby) async throws {
        guard let share = existingShare(for: baby) else { return }
        let ckContainer = CKContainer(identifier: CoreDataStack.cloudContainerID)
        try await ckContainer.privateCloudDatabase.deleteRecord(withID: share.recordID)
    }

    /// Accept an incoming share invitation (called from the scene delegate when the partner taps the
    /// link). Records land in the local `.shared` persistent store.
    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let sharedStore = CoreDataStack.shared.sharedPersistentStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            #if DEBUG
            if let error { print("acceptShareInvitations failed: \(error)") }
            #endif
            NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        }
    }
}
