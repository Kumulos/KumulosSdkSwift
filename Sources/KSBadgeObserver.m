//
//  MobileProvision.m
//  From https://github.com/OneSignal/OneSignal-iOS-SDK/tree/master/iOS_SDK/OneSignalMobileProvision
//  Renamed from UIApplication+BSMobileProvision.m to prevent conflicts
//
//  Created by kaolin fire on 2013-06-24.
//  Copyright (c) 2013 The Blindsight Corporation. All rights reserved.
//  Released under the BSD 2-Clause License (see LICENSE)

#import "KSBadgeObserver.h"
#import <UIKit/UIKit.h>

@implementation KSBadgeObserver : NSObject

BadgeChangedCallback _callback;


- (id) init: (BadgeChangedCallback)callback {
    if (self = [super init]) {
        _callback = callback;
      
        [[UIApplication sharedApplication] addObserver:self forKeyPath:@"applicationIconBadgeNumber" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
    
    if ([keyPath isEqualToString:@"applicationIconBadgeNumber"]) {
        NSNumber* newBadgeCount = change[@"new"];

        _callback([newBadgeCount intValue]);
    }
}


@end
