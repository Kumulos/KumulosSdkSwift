//
//  AnalyticsHelper.swift
//  KumulosSDK
//
//  Copyright © 2018 Kumulos. All rights reserved.
//

import Foundation
import CoreData



class KSEventModel : NSManagedObject {
    @NSManaged var uuid : String
    @NSManaged var userIdentifier : String
    @NSManaged var happenedAt : NSNumber
    @NSManaged var eventType : String
    @NSManaged var properties : Data?
}

typealias SyncCompletedBlock = (Error?) -> Void

internal class AnalyticsHelper {
 
    private var analyticsContext : NSManagedObjectContext?
    private var migrationAnalyticsContext : NSManagedObjectContext?
    private var eventsHttpClient:KSHttpClient

    // MARK: Initialization

    init(apiKey: String, secretKey: String, baseEventsUrl: String) {
        analyticsContext = nil
        migrationAnalyticsContext = nil

        eventsHttpClient = KSHttpClient(baseUrl: URL(string: baseEventsUrl)!, requestFormat: .json, responseFormat: .json)
        eventsHttpClient.setBasicAuth(user: apiKey, password: secretKey)
        
        initContext()

        DispatchQueue.global().async {
            if (self.migrationAnalyticsContext != nil){
                self.syncEvents(context: self.migrationAnalyticsContext)
            }
            self.syncEvents(context: self.analyticsContext)
        }
    }

    deinit {
        eventsHttpClient.invalidateSessionCancellingTasks(false)
    }

    private func getMainStoreUrl(appGroupExists: Bool) -> URL? {
        if (!appGroupExists){
           return getAppDbUrl()
        }

        return getSharedDbUrl()
    }

    private func getAppDbUrl() -> URL? {
        let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last
        let appDbUrl = URL(string: "KAnalyticsDb.sqlite", relativeTo: docsUrl)

        return appDbUrl
    }

    private func getSharedDbUrl() -> URL? {
        let sharedContainerPath: URL? = AppGroupsHelper.getSharedContainerPath()
        if (sharedContainerPath == nil){
            return nil
        }

        return URL(string: "KAnalyticsDbShared.sqlite", relativeTo: sharedContainerPath)
    }

    private func initContext() {
        let appDbUrl = getAppDbUrl()
        let appDbExists = appDbUrl == nil ? false : FileManager.default.fileExists(atPath: appDbUrl!.path)
        let appGroupExists = AppGroupsHelper.isKumulosAppGroupDefined()

        let storeUrl = getMainStoreUrl(appGroupExists: appGroupExists)

        if (appGroupExists && appDbExists){
            migrationAnalyticsContext = getManagedObjectContext(storeUrl: appDbUrl)
        }

        analyticsContext = getManagedObjectContext(storeUrl: storeUrl)
    }

    private func getManagedObjectContext(storeUrl : URL?) -> NSManagedObjectContext? {
        let objectModel = getCoreDataModel()
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)
        let opts = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]

        do {
            try storeCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeUrl, options: opts)
        }
        catch {
            print("Failed to set up persistent store: " + error.localizedDescription)
            return nil
        }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            context.persistentStoreCoordinator = storeCoordinator
        }

        return context
    }

    // MARK: Event Tracking
    func trackEvent(eventType: String, properties: [String:Any]?, immediateFlush: Bool) {
        trackEvent(eventType: eventType, atTime: Date(), properties: properties, immediateFlush: immediateFlush)
    }

    func trackEvent(eventType: String, atTime: Date, properties: [String:Any]?, immediateFlush: Bool, onSyncComplete: SyncCompletedBlock? = nil) {
        if eventType == "" || (properties != nil && !JSONSerialization.isValidJSONObject(properties as Any)) {
            print("Ignoring invalid event with empty type or non-serializable properties")
            return
        }

        let work = {
            guard let context = self.analyticsContext else {
                print("No context, aborting")
                return
            }

            guard let entity = NSEntityDescription.entity(forEntityName: "Event", in: context) else {
                print("Can't create entity, aborting")
                return
            }

            let event = KSEventModel(entity: entity, insertInto: nil)

            event.uuid = UUID().uuidString.lowercased()
            event.happenedAt = NSNumber(value: Int64(atTime.timeIntervalSince1970 * 1000))
            event.eventType = eventType
            event.userIdentifier = KumulosHelper.currentUserIdentifier

            if properties != nil {
                let propsJson = try? JSONSerialization.data(withJSONObject: properties as Any, options: JSONSerialization.WritingOptions(rawValue: 0))

                event.properties = propsJson
            }

            context.insert(event)
            do {
                try context.save()

                if (immediateFlush) {
                    DispatchQueue.global().async {
                        self.syncEvents(context: self.analyticsContext, onSyncComplete)
                    }
                }
            }
            catch {
                print("Failed to record event")
                print(error)
            }
        }

        analyticsContext?.perform(work)
    }

    private func syncEvents(context: NSManagedObjectContext?, _ onSyncComplete: SyncCompletedBlock? = nil) {
        context?.performAndWait {
            let results = fetchEventsBatch(context)

            if (results.count == 0) {
                onSyncComplete?(nil)

                if (context === migrationAnalyticsContext){
                    removeAppDatabase()
                }
            }
            else if results.count > 0 {
                syncEventsBatch(context, events: results, onSyncComplete)
                return
            }
        }
    }
    
    private func removeAppDatabase() {
        if (migrationAnalyticsContext == nil){
            return
        }
     
        guard let persStoreCoord = migrationAnalyticsContext!.persistentStoreCoordinator else {
            return
        }
        
        guard let store = persStoreCoord.persistentStores.last else {
            return
        }
        
        let storeUrl = persStoreCoord.url(for: store)
        
        migrationAnalyticsContext!.performAndWait {
            migrationAnalyticsContext!.reset()
            do{
                try persStoreCoord.remove(store)
                try FileManager.default.removeItem(at: storeUrl)
            }
            catch{}
        }
        migrationAnalyticsContext = nil
    }

    private func syncEventsBatch(_ context: NSManagedObjectContext?, events: [KSEventModel], _ onSyncComplete:SyncCompletedBlock? = nil) {
        var data = [] as [[String : Any?]]
        var eventIds = [] as [NSManagedObjectID]

        for event in events {
            var jsonProps = nil as Any?
            if let props = event.properties {
                jsonProps = try? JSONSerialization.jsonObject(with: props, options: JSONSerialization.ReadingOptions.init(rawValue: 0))
            }

            data.append([
                "type": event.eventType,
                "uuid": event.uuid,
                "timestamp": event.happenedAt,
                "data": jsonProps,
                "userId": event.userIdentifier
            ])
            eventIds.append(event.objectID)
        }

        let path = "/v1/app-installs/\(KumulosHelper.installId)/events"

        self.eventsHttpClient.sendRequest(.POST, toPath: path, data: data, onSuccess: { (response, data) in
            if let err = self.pruneEventsBatch(context, eventIds) {
                print("Failed to prune events batch: " + err.localizedDescription)
                onSyncComplete?(err)
                return
            }
            self.syncEvents(context: context, onSyncComplete)
        }) { (response, error, data) in
            print("Failed to send events")
            onSyncComplete?(error)
        }
    }

    private func pruneEventsBatch(_ context: NSManagedObjectContext?, _ eventIds: [NSManagedObjectID]) -> Error? {
        var err : Error? = nil

        context?.performAndWait {
            let request = NSBatchDeleteRequest(objectIDs: eventIds)

            do {
                try context?.execute(request)
            }
            catch {
                err = error
            }
        }

        return err
    }

    private func fetchEventsBatch(_ context: NSManagedObjectContext?) -> [KSEventModel] {
        guard let context = context else {
            return []
        }

        let request = NSFetchRequest<KSEventModel>(entityName: "Event")
        request.returnsObjectsAsFaults = false
        request.sortDescriptors = [ NSSortDescriptor(key: "happenedAt", ascending: true) ]
        request.fetchLimit = 100
        request.includesPendingChanges = false

        do {
            let results = try context.fetch(request)
            return results
        }
        catch {
            print("Failed to fetch events batch: " + error.localizedDescription)
            return []
        }
    }

    // MARK: CoreData model definition
    fileprivate func getCoreDataModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let eventEntity = NSEntityDescription()
        eventEntity.name = "Event"
        eventEntity.managedObjectClassName = NSStringFromClass(KSEventModel.self)

        var eventProps : Array<NSAttributeDescription> = []

        let eventTypeProp = NSAttributeDescription()
        eventTypeProp.name = "eventType"
        eventTypeProp.attributeType = .stringAttributeType
        eventTypeProp.isOptional = false
        eventProps.append(eventTypeProp)

        let happenedAtProp = NSAttributeDescription()
        happenedAtProp.name = "happenedAt"
        happenedAtProp.attributeType = .integer64AttributeType
        happenedAtProp.isOptional = false
        happenedAtProp.defaultValue = 0
        eventProps.append(happenedAtProp)

        let propertiesProp = NSAttributeDescription()
        propertiesProp.name = "properties"
        propertiesProp.attributeType = .binaryDataAttributeType
        propertiesProp.isOptional = true
        eventProps.append(propertiesProp)

        let uuidProp = NSAttributeDescription()
        uuidProp.name = "uuid"
        uuidProp.attributeType = .stringAttributeType
        uuidProp.isOptional = false
        eventProps.append(uuidProp);

        let userIdProp = NSAttributeDescription()
        userIdProp.name = "userIdentifier"
        userIdProp.attributeType = .stringAttributeType
        userIdProp.isOptional = true
        eventProps.append(userIdProp);

        eventEntity.properties = eventProps
        model.entities = [eventEntity]

        return model;
    }
}
