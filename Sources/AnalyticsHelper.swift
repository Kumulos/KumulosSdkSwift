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

class AnalyticsHelper {
    private var kumulos : Kumulos
    private var analyticsContext : NSManagedObjectContext?
    private var startNewSession : Bool
    private var sessionIdleTimer : Timer?
    private var bgTask : UIBackgroundTaskIdentifier
    
    // MARK: Initialization
    
    init(kumulos:Kumulos) {
        self.kumulos = kumulos;
        startNewSession = true
        sessionIdleTimer = nil
        bgTask = UIBackgroundTaskInvalid
        analyticsContext = nil
        
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
        // TODO
    }

    // MARK: Event Tracking

    func trackEvent(eventType: String, properties: [String:Any]?) {
        trackEvent(eventType: eventType, happenedAt: Date(), properties: properties)
    }
    
    func trackEvent(eventType: String, happenedAt: Date, properties: [String:Any]?) {
        if eventType == "" || (properties != nil && !JSONSerialization.isValidJSONObject(properties as Any)) {
            print("Ignoring invalid event with empty type or non-serializable properties")
            return
        }
        
        analyticsContext?.perform {
            guard let context = self.analyticsContext else {
                return
            }
            
            guard let entity = NSEntityDescription.entity(forEntityName: "Event", in: context) else {
                return
            }
            
            let event = NSManagedObject(entity: entity, insertInto: context)
            
            let happenedAtMillis = happenedAt.timeIntervalSince1970 * 1000
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
            }
            catch {
                print("Failed to record event")
            }
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
        
        let url = "\(kumulos.baseStatsUrl)app-installs/\(Kumulos.installId)/events"
        
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
        
        do {
            let results = try context.fetch(request)
            return results
        }
        catch {
            print("Failed to fetch events batch: " + error.localizedDescription)
            return []
        }
    }
    
}
