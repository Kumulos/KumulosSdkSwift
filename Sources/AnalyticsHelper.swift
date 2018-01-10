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
    private var startNewSession : Bool
    private var sessionIdleTimer : Timer?
    private var bgTask : UIBackgroundTaskIdentifier
    
    init(kumulos:Kumulos) {
        self.kumulos = kumulos;
        startNewSession = true
        sessionIdleTimer = nil
        bgTask = UIBackgroundTaskInvalid
        
        initContext()
        registerListeners()
        
        DispatchQueue.global(qos: .background).async {
            self.syncEvents()
        }
    }
    
    private func initContext() {
        
    }
    
    private func registerListeners() {
        
    }
    
    private func syncEvents() {
        
    }
    
}
