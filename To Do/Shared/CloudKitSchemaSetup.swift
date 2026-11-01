#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Debug-only: writes every record type and every field of the SwiftData schema to the
/// CloudKit Development environment, so it can be deployed to Production in one go.
///
/// Opening the tabs isn't enough: CloudKit only learns a field once a value is saved in
/// it, and a field that was never filled (sleep debt on a night WHOOP didn't report it)
/// would be missing from Production, where later saves would fail silently.
///
/// It runs against a throwaway store in the temporary folder, so the real data on the
/// device is never opened. Launch a debug build with the argument INIT_CLOUDKIT_SCHEMA
/// (RELEASING.md §2).
enum CloudKitSchemaSetup {
    static func run(models: [any PersistentModel.Type], containerID: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-setup-\(UUID().uuidString).store")
        do {
            try autoreleasepool {
                let description = NSPersistentStoreDescription(url: url)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
                description.shouldAddStoreAsynchronously = false
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else {
                    throw SetupError.noModel
                }
                let container = NSPersistentCloudKitContainer(name: "SchemaSetup", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }
                try container.initializeCloudKitSchema()
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            let message = "CloudKit schema written to Development: \(models.count) record types. Check CloudKit Console, then deploy."
            print("SCHEMA_SETUP_OK \(message)")
            return message
        } catch {
            let message = "Schema setup failed: \(error.localizedDescription)"
            print("SCHEMA_SETUP_FAILED \(error)")
            return message
        }
    }

    enum SetupError: Error { case noModel }
}
#endif
