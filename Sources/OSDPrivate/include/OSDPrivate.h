#pragma once

#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Displays Apple's private system volume OSD.
void DVKShowVolumeOSD(CGDirectDisplayID displayID, float level, bool muted);

#ifdef __cplusplus
}
#endif
