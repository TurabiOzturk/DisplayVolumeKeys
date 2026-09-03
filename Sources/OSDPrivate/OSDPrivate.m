#import "OSDPrivate.h"
#import <Foundation/Foundation.h>

@protocol DVKOSDUIHelperProtocol
- (void)showImage:(long long)image
       onDisplayID:(unsigned int)displayID
          priority:(unsigned int)priority
     msecUntilFade:(unsigned int)msecUntilFade
    filledChiclets:(unsigned int)filledChiclets
     totalChiclets:(unsigned int)totalChiclets
            locked:(BOOL)locked;
@end

@interface OSDManager : NSObject
+ (instancetype)sharedManager;
- (void)showImage:(long long)image
       onDisplayID:(unsigned int)displayID
          priority:(unsigned int)priority
     msecUntilFade:(unsigned int)msecUntilFade
    filledChiclets:(unsigned int)filledChiclets
     totalChiclets:(unsigned int)totalChiclets
            locked:(BOOL)locked;
@end

void DVKShowVolumeOSD(CGDirectDisplayID displayID, float level, bool muted) {
    const unsigned int totalChiclets = 16;
    const float clampedLevel = fmaxf(0.0f, fminf(1.0f, level));
    const unsigned int filledChiclets = muted ? 0 : (unsigned int)lroundf(clampedLevel * totalChiclets);
    const long long image = (muted || clampedLevel == 0.0f) ? 4 : 3;

    [[OSDManager sharedManager]
        showImage:image
        onDisplayID:displayID
        priority:0x1F4
        msecUntilFade:1000
        filledChiclets:filledChiclets
        totalChiclets:totalChiclets
        locked:NO];
}
