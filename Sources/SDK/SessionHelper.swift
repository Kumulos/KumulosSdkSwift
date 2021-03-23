//
//  SessionHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 20/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

class SessionIdleTimer {
    private let helper : SessionHelper
    private var invalidationLock : DispatchSemaphore
    private var invalidated : Bool
    
    init(_ helper : SessionHelper, timeout: UInt) {
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

internal class SessionHelper {
    private var startNewSession : Bool
    private var becameInactiveAt : Date?
    private var sessionIdleTimer : SessionIdleTimer?
    private var bgTask : UIBackgroundTaskIdentifier
    private var sessionIdleTimeout : UInt
    private let syncBarrier = DispatchSemaphore(value: 0)
    
    init(sessionIdleTimeout: UInt) {
        startNewSession = true
        sessionIdleTimer = nil
        bgTask = UIBackgroundTaskIdentifier.invalid
        becameInactiveAt = nil
        self.sessionIdleTimeout = sessionIdleTimeout
    }
    
    func initialize() {
        registerListeners()
    }
    
    private func registerListeners() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.appBecameInactive), name: UIApplication.willResignActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.appBecameBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    // MARK: App lifecycle delegates

    @objc private func appBecameActive() {
        if startNewSession {
            Kumulos.trackEvent(eventType: KumulosEvent.STATS_FOREGROUND, properties: nil)
            startNewSession = false
            return
        }

        if sessionIdleTimer != nil {
            sessionIdleTimer?.invalidate()
            sessionIdleTimer = nil
        }

        if bgTask != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = UIBackgroundTaskIdentifier.invalid
        }
    }

    @objc private func appBecameInactive() {
        becameInactiveAt = Date()

        sessionIdleTimer = SessionIdleTimer(self, timeout: self.sessionIdleTimeout)
    }

    @objc private func appBecameBackground() {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ksession", expirationHandler: {
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = UIBackgroundTaskIdentifier.invalid
        })

        if becameInactiveAt == nil {
            becameInactiveAt = Date()
        }
    }

    @objc private func appWillTerminate() {
        if becameInactiveAt == nil {
            becameInactiveAt = Date()
        }

        if sessionIdleTimer != nil {
            sessionIdleTimer?.invalidate()
            sessionDidEnd()
        }
    }

    fileprivate func sessionDidEnd() {
        guard let sessionEndTime = becameInactiveAt else {
            return
        }

        startNewSession = true
        sessionIdleTimer = nil

        Kumulos.trackEvent(eventType: KumulosEvent.STATS_BACKGROUND.rawValue, atTime: sessionEndTime, properties: nil, immediateFlush: true, onSyncComplete: {err in
            self.becameInactiveAt = nil

            if self.bgTask != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = UIBackgroundTaskIdentifier.invalid
            }

            self.syncBarrier.signal()
        })

        _ = syncBarrier.wait(timeout: .now() + .seconds(10))
    }
    
}
