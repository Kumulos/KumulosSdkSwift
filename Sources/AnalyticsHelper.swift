//
//  AnalyticsHelper.swift
//  KumulosSDK
//
//  Copyright © 2018 Kumulos. All rights reserved.
//

import Foundation
import CoreData
import Alamofire

struct EventsParameterEncoding : ParameterEncoding {
    
    func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()
        guard let events = parameters?["events"] else {
            return urlRequest
        }
        
        let data = try JSONSerialization.data(withJSONObject: events, options: [])

        urlRequest.httpBody = data
        
        return urlRequest
    }
}

class SessionIdleTimer {
    private let helper : AnalyticsHelper
    private var invalidationLock : DispatchSemaphore
    private var invalidated : Bool
    
    init(_ helper : AnalyticsHelper, timeout: UInt) {
        self.invalidationLock = DispatchSemaphore(value: 1)
        self.invalidated = false
        self.helper = helper
        
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Int(timeout))) {
            self.invalidationLock.wait()

            if self.invalidated {
                self.invalidationLock.signal()
                return
            }
            
            self.invalidationLock.signal()
            
            helper.sessionDidEnd()
        }
    }
    
    internal func invalidate() {
        invalidationLock.wait()
        invalidated = true
        invalidationLock.signal()
    }
}

class KSEventModel : NSManagedObject {
    @NSManaged var uuid : String
    @NSManaged var userIdentifier : String
    @NSManaged var happenedAt : NSNumber
    @NSManaged var eventType : String
    @NSManaged var properties : Data?
}

class AnalyticsHelper {
    private var kumulos : Kumulos
    private var analyticsContext : NSManagedObjectContext?
    private var startNewSession : Bool
    private var sessionIdleTimer : SessionIdleTimer?
    private var becameInactiveAt : Date?
    private var bgTask : UIBackgroundTaskIdentifier
    
    // MARK: Initialization
    
    init(kumulos:Kumulos) {
        self.kumulos = kumulos;
        startNewSession = true
        sessionIdleTimer = nil
        bgTask = UIBackgroundTaskIdentifier.invalid
        analyticsContext = nil
        becameInactiveAt = nil
        
        initContext()
        registerListeners()
        
        DispatchQueue.global().async {
            self.syncEvents()
        }
    }
    
    private func initContext() {
        let objectModel = getCoreDataModel()
        
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)
        
        let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last
        let storeUrl = URL(string: "KAnalyticsDb.sqlite", relativeTo: docsUrl)
        let opts = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        
        do {
            try storeCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeUrl, options: opts)
        }
        catch {
            print("Failed to set up persistent store: " + error.localizedDescription)
            return
        }

        analyticsContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        analyticsContext?.performAndWait {
            analyticsContext?.persistentStoreCoordinator = storeCoordinator
        }
    }
    
    private func registerListeners() {
        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appBecameInactive), name: UIApplication.willResignActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appBecameBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    // MARK: Event Tracking
    func trackEvent(eventType: String, properties: [String:Any]?, immediateFlush: Bool = false) {
        trackEvent(eventType: eventType, atTime: Date(), properties: properties, immediateFlush: immediateFlush)
    }
    
    func trackEvent(eventType: String, atTime: Date, properties: [String:Any]?, asynchronously : Bool = true, immediateFlush: Bool = false) {
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
            event.userIdentifier = Kumulos.currentUserIdentifier

            if properties != nil {
                let propsJson = try? JSONSerialization.data(withJSONObject: properties as Any, options: JSONSerialization.WritingOptions(rawValue: 0))

                event.properties = propsJson
            }

            context.insert(event)
            do {
                try context.save()
                
                if (immediateFlush) {
                    DispatchQueue.global().async {
                        self.syncEvents()
                    }
                }
            }
            catch {
                print("Failed to record event")
                print(error)
            }
        }
        
        if asynchronously {
            analyticsContext?.perform(work)
        }
        else {
            analyticsContext?.performAndWait(work)
        }
    }
    
    private func syncEvents() {
        analyticsContext?.performAndWait {
            let results = fetchEventsBatch()

            if results.count > 0 {
                syncEventsBatch(events: results)
            }
            else if bgTask != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(convertToUIBackgroundTaskIdentifier(bgTask.rawValue))
                bgTask = UIBackgroundTaskIdentifier.invalid
            }
        }
    }
    
    private func syncEventsBatch(events: [KSEventModel]) {
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
        
        let url = "\(kumulos.baseEventsUrl)/app-installs/\(Kumulos.installId)/events"
        
        let request = kumulos.makeJsonNetworkRequest(.post, url: url, parameters: ["events": data], encoding: EventsParameterEncoding())
        
        request.validate(statusCode: 200..<300).responseJSON { response in
            switch response.result {

            case .success:
                if let err = self.pruneEventsBatch(eventIds) {
                    print("Failed to prune events batch: " + err.localizedDescription)
                    return
                }
                self.syncEvents()

            case .failure:
                // Failed so assume will be retried some other time
                if self.bgTask != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(convertToUIBackgroundTaskIdentifier(self.bgTask.rawValue))
                    self.bgTask = UIBackgroundTaskIdentifier.invalid
                }
            }
        }
    }
    
    private func pruneEventsBatch(_ eventIds: [NSManagedObjectID]) -> Error? {
        var err : Error? = nil

        analyticsContext?.performAndWait {
            let request = NSBatchDeleteRequest(objectIDs: eventIds)

            do {
                try self.analyticsContext?.execute(request)
            }
            catch {
                err = error
            }
        }

        return err
    }
    
    private func fetchEventsBatch() -> [KSEventModel] {
        guard let context = analyticsContext else {
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
    
    // MARK: App lifecycle delegates
    
    @objc private func appBecameActive() {
        if startNewSession {
            trackEvent(eventType: KumulosEvent.STATS_FOREGROUND.rawValue, properties: nil)
            startNewSession = false
            return
        }
        
        if sessionIdleTimer != nil {
            sessionIdleTimer?.invalidate()
            sessionIdleTimer = nil
        }
        
        if bgTask != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(convertToUIBackgroundTaskIdentifier(bgTask.rawValue))
            bgTask = UIBackgroundTaskIdentifier.invalid
        }
    }
    
    @objc private func appBecameInactive() {
        becameInactiveAt = Date()
        
        sessionIdleTimer = SessionIdleTimer(self, timeout: kumulos.config.sessionIdleTimeout)
    }
    
    @objc private func appBecameBackground() {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "sync", expirationHandler: {
            UIApplication.shared.endBackgroundTask(convertToUIBackgroundTaskIdentifier(self.bgTask.rawValue))
            self.bgTask = UIBackgroundTaskIdentifier.invalid
        })
    }
    
    @objc private func appWillTerminate() {
        if sessionIdleTimer != nil {
            sessionIdleTimer?.invalidate()
            sessionDidEnd()
        }
    }

    fileprivate func sessionDidEnd() {
        startNewSession = true
        sessionIdleTimer = nil
        
        trackEvent(eventType: KumulosEvent.STATS_BACKGROUND.rawValue, atTime: becameInactiveAt!, properties: nil, asynchronously: false, immediateFlush: true)
        becameInactiveAt = nil
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

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUIBackgroundTaskIdentifier(_ input: Int) -> UIBackgroundTaskIdentifier {
	return UIBackgroundTaskIdentifier(rawValue: input)
}
