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
        
    }
    
    private func syncEvents() {
        
    }
    
}
