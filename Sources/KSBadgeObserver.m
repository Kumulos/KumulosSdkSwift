#import "KSBadgeObserver.h"
#import <UIKit/UIKit.h>

@implementation KSBadgeObserver : NSObject

KSBadgeChangedCallback _callback;


- (id) init: (KSBadgeChangedCallback)callback {
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
