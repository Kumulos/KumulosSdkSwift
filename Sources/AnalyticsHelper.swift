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
    private var invalidated : Bool
    
    init(_ helper : AnalyticsHelper, timeout: UInt) {
        self.invalidated = false
        self.helper = helper
        
        DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(Int(timeout))) {
            if self.invalidated {
                return
            }
            
            helper.sessionDidEnd()
        }
    }
    
    internal func invalidate() {
        self.invalidated = true
    }
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
        bgTask = UIBackgroundTaskInvalid
        analyticsContext = nil
        becameInactiveAt = nil
        
        initContext()
        registerListeners()
        
        DispatchQueue.global(qos: .background).async {
            self.syncEvents()
        }
    }
    
    private func initContext() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "KAnalyticsModel", withExtension:"momd") else {
            print("Failed to find analytics models")
            return
        }
        
        guard let objectModel = NSManagedObjectModel(contentsOf: url) else {
            print("Failed to create object model")
            return
        }
        
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)
        
        let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last
        let storeUrl = URL(string: "KAnalyticsDb.sqlite", relativeTo: docsUrl)
        
        do {
            try storeCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeUrl, options: nil)
        }
        catch {
            print("Failed to set up persistent store: " + error.localizedDescription)
            return
        }

        analyticsContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        analyticsContext?.persistentStoreCoordinator = storeCoordinator
    }
    
    private func registerListeners() {
        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appBecameActive), name: .UIApplicationDidBecomeActive, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appBecameInactive), name: .UIApplicationWillResignActive, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appBecameBackground), name: .UIApplicationDidEnterBackground, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(AnalyticsHelper.appWillTerminate), name: .UIApplicationWillTerminate, object: nil)
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
            
            let event = NSManagedObject(entity: entity, insertInto: context)
            
            let happenedAtMillis = atTime.timeIntervalSince1970 * 1000
            let uuid = UUID().uuidString.lowercased()
            
            event.setValue(uuid, forKey: "uuid")
            event.setValue(happenedAtMillis, forKey: "happenedAt")
            event.setValue(eventType, forKey: "eventType")

            if properties != nil {
                let propsJson = try? JSONSerialization.data(withJSONObject: properties as Any, options: JSONSerialization.WritingOptions(rawValue: 0))

                event.setValue(propsJson, forKey: "properties")
            }
            
            do {
                try context.save()
                
                if (immediateFlush) {
                    DispatchQueue.global(qos: .background).async {
                        self.syncEvents()
                    }
                }
            }
            catch {
                print("Failed to record event")
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
        let results = fetchEventsBatch()
        
        if results.count > 0 {
            syncEventsBatch(events: results)
        }
        else if bgTask != UIBackgroundTaskInvalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = UIBackgroundTaskInvalid
        }
    }
    
    private func syncEventsBatch(events: [NSManagedObject]) {
        var data = [] as [[String : Any?]]
        
        for event in events {
            var jsonProps = nil as Any?
            if let props = event.value(forKey: "properties") as? Data {
                jsonProps = try? JSONSerialization.jsonObject(with: props, options: JSONSerialization.ReadingOptions.init(rawValue: 0))
            }
            
            data.append([
                "type": event.value(forKey: "eventType"),
                "uuid": event.value(forKey: "uuid"),
                "timestamp": event.value(forKey: "happenedAt"),
                "data": jsonProps
            ])
        }
        
        let url = "\(kumulos.baseEventsUrl)app-installs/\(Kumulos.installId)/events"
        
        let request = kumulos.makeJsonNetworkRequest(.post, url: url, parameters: ["events": data], encoding: EventsParameterEncoding())
        
        request.validate(statusCode: 200..<300).responseJSON { response in
            switch response.result {

            case .success:
                if let err = self.pruneEventsBatch(events) {
                    print("Failed to prune events batch: " + err.localizedDescription)
                    return
                }
                self.syncEvents()

            case .failure:
                // Failed so assume will be retried some other time
                if self.bgTask != UIBackgroundTaskInvalid {
                    UIApplication.shared.endBackgroundTask(self.bgTask)
                    self.bgTask = UIBackgroundTaskInvalid
                }
            }
        }
    }
    
    private func pruneEventsBatch(_ events: [NSManagedObject]) -> Error? {
        let ids = events.map { (event) -> NSManagedObjectID in
            return event.objectID
        }
        
        let request = NSBatchDeleteRequest(objectIDs: ids)
        
        do {
            try self.analyticsContext?.execute(request)
        }
        catch {
            return error
        }
        
        return nil
    }
    
    private func fetchEventsBatch() -> [NSManagedObject] {
        guard let context = analyticsContext else {
            return []
        }
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Event")
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
        
        if bgTask != UIBackgroundTaskInvalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = UIBackgroundTaskInvalid
        }
    }
    
    @objc private func appBecameInactive() {
        becameInactiveAt = Date()
        
        sessionIdleTimer = SessionIdleTimer(self, timeout: kumulos.config.sessionIdleTimeout)
    }
    
    @objc private func appBecameBackground() {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "sync", expirationHandler: {
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = UIBackgroundTaskInvalid
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
        
        trackEvent(eventType: KumulosEvent.STATS_BACKGROUND.rawValue, atTime: becameInactiveAt!, properties: nil, asynchronously: false)
        becameInactiveAt = nil
        
        DispatchQueue.global(qos: .background).async {
            self.syncEvents()
        }
    }
    
}
