//
//  Observer.h
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 25/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^ KSBadgeChangedCallback)(int newBadgeCount);

@interface KSBadgeObserver : NSObject

- (id) init: (KSBadgeChangedCallback)callback;

@end
