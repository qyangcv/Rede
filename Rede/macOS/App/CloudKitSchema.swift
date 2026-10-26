#if DEBUG
import CoreData
import SwiftData

enum CloudKitSchema {
    static let argument = "--initialize-cloudkit-schema"

    enum Failure: Error {
        case managedObjectModel
    }

    static func initialize() throws {
        let directory = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let description = NSPersistentStoreDescription(url: directory.appending(component: "schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudSync.container)
        description.shouldAddStoreAsynchronously = false

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: LibrarySchema.models) else {
            throw Failure.managedObjectModel
        }
        let container = NSPersistentCloudKitContainer(name: "Rede", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
