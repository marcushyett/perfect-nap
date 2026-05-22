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

    /// Creates (or returns) a CKShare for the baby so it can be presented in a share sheet.
    /// The completion delivers the share + container needed by UICloudSharingController.
    func makeShare(for baby: Baby) async throws -> (CKShare, CKContainer) {
        if let existing = existingShare(for: baby) {
            return (existing, CKContainer(identifier: CoreDataStack.cloudContainerID))
        }
        let (_, share, ckContainer) = try await container.share([baby], to: nil)
        share[CKShare.SystemFieldKey.title] = "\(baby.displayName)'s sleep" as CKRecordValue
        // Make it a link anyone can open + edit, so the invite can go via WhatsApp/any channel
        // without needing the partner's Apple ID. The link itself is the access control.
        share.publicPermission = .readWrite
        return (share, ckContainer)
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
