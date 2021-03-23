
//
//  MobileProvision.h
//  From https://github.com/OneSignal/OneSignal-iOS-SDK/tree/master/iOS_SDK/OneSignalMobileProvision
//  Renamed from UIApplication+BSMobileProvision.h to prevent conflicts
//
//  Created by kaolin fire on 2013-06-24.
//  Copyright (c) 2013 The Blindsight Corporation. All rights reserved.
//  Released under the BSD 2-Clause License (see LICENSE)

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, UIApplicationReleaseMode) {
    UIApplicationReleaseUnknown,
    UIApplicationReleaseDev,
    UIApplicationReleaseAdHoc,
    UIApplicationReleaseWildcard,
    UIApplicationReleaseAppStore,
    UIApplicationReleaseSim,
    UIApplicationReleaseEnterprise
};

@interface MobileProvision : NSObject

+ (UIApplicationReleaseMode) releaseMode;

@end