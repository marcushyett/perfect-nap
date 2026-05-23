import Foundation
import CoreData
import CloudKit
import OSLog

let perfectNapLog = Logger(subsystem: "com.marcushyett.perfectnap", category: "cloudkit")

/// CloudKit-backed Core Data stack shared by the app and its App Intents.
/// Private store = this user's own data (syncs across their devices); shared store = data shared
/// *to* them by a partner via CKShare. One container, two database scopes.
final class CoreDataStack {
    static let shared = CoreDataStack()

    static let cloudContainerID = "iCloud.com.marcushyett.perfectnap"
    static let appGroupID = "group.com.marcushyett.perfectnap.shared"

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// The `.shared` persistent store (data shared *to* this user) — needed when accepting a CKShare.
    var sharedPersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first {
            $0.url?.lastPathComponent == "PerfectNap.shared.sqlite"
        }
    }

    /// True when an iCloud account is available. CloudKit mirroring is only attached then —
    /// otherwise the app runs on a plain local store (and never crashes setting up CloudKit without
    /// an account, e.g. in the simulator or for users not signed into iCloud).
    let cloudKitEnabled: Bool

    /// Checks the real CloudKit account status (NOT ubiquityIdentityToken, which needs the iCloud
    /// Documents entitlement we don't have and is nil even when signed into iCloud). Bounded wait so
    /// app launch can't hang on it.
    private static func detectCloudKitAvailable() -> Bool {
        #if targetEnvironment(simulator)
        // Simulator builds in this project are unsigned and have no CloudKit entitlement — even
        // constructing a CKContainer traps. Run on a plain local store in the simulator.
        return false
        #else
        let semaphore = DispatchSemaphore(value: 0)
        var available = false
        CKContainer(identifier: cloudContainerID).accountStatus { status, error in
            available = (status == .available)
            if let error { perfectNapLog.error("accountStatus error: \(String(describing: error), privacy: .public)") }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 4)
        return available
        #endif
    }

    /// UI tests launch with `-uiTesting`: a clean in-memory store (no persistence across launches,
    /// no CloudKit) so each test starts from a deterministic, seeded state.
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    private init() {
        let uiTesting = CoreDataStack.isUITesting
        cloudKitEnabled = uiTesting ? false : CoreDataStack.detectCloudKitAvailable()
        perfectNapLog.notice("CoreDataStack init: cloudKitEnabled=\(self.cloudKitEnabled, privacy: .public) uiTesting=\(uiTesting, privacy: .public)")
        container = NSPersistentCloudKitContainer(name: "PerfectNap", managedObjectModel: CoreDataStack.model)

        let baseURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: CoreDataStack.appGroupID)
            ?? NSPersistentContainer.defaultDirectoryURL()

        let privateDesc: NSPersistentStoreDescription
        if uiTesting {
            privateDesc = NSPersistentStoreDescription()
            privateDesc.type = NSInMemoryStoreType
        } else {
            privateDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("PerfectNap.private.sqlite"))
            privateDesc.shouldMigrateStoreAutomatically = true
            privateDesc.shouldInferMappingModelAutomatically = true
            privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        var descriptions = [privateDesc]

        if cloudKitEnabled {
            privateDesc.cloudKitContainerOptions = {
                let o = NSPersistentCloudKitContainerOptions(containerIdentifier: CoreDataStack.cloudContainerID)
                o.databaseScope = .private
                return o
            }()

            let sharedDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("PerfectNap.shared.sqlite"))
            sharedDesc.shouldMigrateStoreAutomatically = true
            sharedDesc.shouldInferMappingModelAutomatically = true
            sharedDesc.cloudKitContainerOptions = {
                let o = NSPersistentCloudKitContainerOptions(containerIdentifier: CoreDataStack.cloudContainerID)
                o.databaseScope = .shared
                return o
            }()
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            descriptions.append(sharedDesc)
        }

        container.persistentStoreDescriptions = descriptions

        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { desc, error in
            guard let error else { return }
            #if DEBUG
            print("Core Data store load failed (\(desc.url?.lastPathComponent ?? "?")): \(error)")
            #endif
            // Resilience: never run storeless (that crashes on the first save). If a store fails to
            // load — e.g. a CloudKit hiccup — retry it as a plain local SQLite store.
            guard let url = desc.url,
                  !coordinator.persistentStores.contains(where: { $0.url == url }) else { return }
            try? coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: url,
                options: [
                    NSMigratePersistentStoresAutomaticallyOption: true,
                    NSInferMappingModelAutomaticallyOption: true
                ]
            )
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try? container.viewContext.setQueryGenerationFrom(.current)
    }

    /// Single shared model instance. Core Data maps each NSManagedObject subclass to exactly one
    /// entity description, so the model must be built once — multiple instances cause
    /// "Failed to find a unique match" warnings.
    static let model: NSManagedObjectModel = buildModel()

    /// Programmatic model — avoids a .xcdatamodeld bundle. All attributes are optional / have
    /// defaults (a CloudKit requirement) and there are no unique constraints or relationships.
    private static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        func attr(_ name: String, _ type: NSAttributeType, optional: Bool = true, default def: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            // CloudKit requires every non-optional attribute to carry a default value.
            if let def { a.defaultValue = def }
            return a
        }

        let baby = NSEntityDescription()
        baby.name = "Baby"
        baby.managedObjectClassName = "Baby"
        baby.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("birthDate", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("adaptationFactor", .doubleAttributeType, optional: false, default: 1.0),
            attr("adaptationConfidence", .doubleAttributeType, optional: false, default: 0.0),
            attr("targetBedtimeMinutes", .integer64AttributeType, optional: false, default: 0),
            attr("weeksPremature", .integer64AttributeType, optional: false, default: 0),
            attr("customScheduleMinutes", .stringAttributeType),
            attr("ownerHasPremium", .booleanAttributeType, optional: false, default: false),
        ]

        let nap = NSEntityDescription()
        nap.name = "NapSession"
        nap.managedObjectClassName = "NapSession"
        nap.properties = [
            attr("id", .UUIDAttributeType),
            attr("startedAt", .dateAttributeType),
            attr("endedAt", .dateAttributeType),
            attr("kindRaw", .stringAttributeType),
            attr("note", .stringAttributeType),
            attr("babyID", .UUIDAttributeType),
        ]

        // Travel / jet-lag trip. Additive + all-optional (no migration or data loss for existing
        // users; absence of a Trip simply means "not travelling").
        let trip = NSEntityDescription()
        trip.name = "Trip"
        trip.managedObjectClassName = "Trip"
        trip.properties = [
            attr("id", .UUIDAttributeType),
            attr("originTZ", .stringAttributeType),
            attr("destinationTZ", .stringAttributeType),
            attr("departureDate", .dateAttributeType),
            attr("arrivalDate", .dateAttributeType),
            attr("returnDate", .dateAttributeType),
            attr("strategyRaw", .stringAttributeType),
            attr("alreadyLanded", .booleanAttributeType, optional: false, default: false),
            attr("createdAt", .dateAttributeType),
        ]

        model.entities = [baby, nap, trip]
        return model
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    #if DEBUG
    /// One-off: pushes the Core Data → CloudKit record types (CD_Baby, CD_NapSession, …) to the
    /// **Development** CloudKit environment so they can then be deployed to **Production** in the
    /// CloudKit Console. Run once from a debug build with an iCloud account signed in. Idempotent.
    func initializeCloudKitSchemaForDevelopment() {
        guard cloudKitEnabled else {
            perfectNapLog.error("⚠️ Schema init skipped — CloudKit not enabled (no iCloud account detected).")
            return
        }
        DispatchQueue.global(qos: .utility).async { [container] in
            do {
                try container.initializeCloudKitSchema(options: [])
                perfectNapLog.notice("✅ CloudKit schema pushed to DEVELOPMENT. Next: CloudKit Console → Deploy Schema Changes → Production.")
            } catch {
                perfectNapLog.error("❌ CloudKit schema init failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
    #endif
}
