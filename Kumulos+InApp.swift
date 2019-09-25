//
//  Kumulos+InApp.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation

public extension Kumulos {
    func getInboxItems() -> [InAppMessage] {
        
        if (self.inAppHelper.messagesContext == nil) {
            return []
        }
        
        //- TODO fetch / map
        
        return []
        
    }
    

    func updateConsent(forUser consentGiven: Bool) {
        if self.inAppConsentStrategy != InAppConsentStrategy.ExplicitByUser {
            NSException.raise("Kumulos: Invalid In-app consent strategy", format: "You can only manage in-app messaging consent when the feature is enabled and strategy is set to KSInAppConsentStrategyExplicitByUser")
            return
        }

        self.inAppHelper.updateUserConsent(consentGiven: consentGiven)
    }
    
    class func presentInboxMessage(_ item: InAppInboxItem?) -> InAppMessagePresentationResult {
        if item?.isAvailable() == nil {
            return InAppMessagePresentationResult.EXPIRED
        }

        let result = self.inAppHelper.presentMessage(withId: item?.id)

        return result ? InAppMessagePresentationPresented : InAppMessagePresentation.FAILED as! InAppMessagePresentationResult
    }
}
