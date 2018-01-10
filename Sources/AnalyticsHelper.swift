//
//  AnalyticsHelper.swift
//  KumulosSDK
//
//  Copyright © 2018 Kumulos. All rights reserved.
//

import Foundation
import CoreData

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
            print("Failed to set up persistent store")
            return
        }
        
        analyticsContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        analyticsContext?.persistentStoreCoordinator = storeCoordinator
    }
    
    private func registerListeners() {
        // TODO
    }

    // MARK: Event Tracking

    func trackEvent(eventType: String, properties: AnyObject?) {
        trackEvent(eventType: eventType, happenedAt: Date(), properties: properties)
    }
    
    func trackEvent(eventType: String, happenedAt: Date, properties: AnyObject?) {
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
            
            let propsJson = try? JSONSerialization.data(withJSONObject: properties as Any, options: JSONSerialization.WritingOptions(rawValue: 0))
            
            event.setValue(uuid, forKey: "uuid")
            event.setValue(happenedAtMillis, forKey: "happenedAt")
            event.setValue(eventType, forKey: "eventType")
            event.setValue(propsJson, forKey: "properties")
            
            do {
                try context.save()
            }
            catch {
                print("Failed to record event")
            }
        }
    }
    
    private func syncEvents() {
        
    }
    
}
