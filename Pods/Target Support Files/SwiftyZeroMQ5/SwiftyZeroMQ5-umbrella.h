#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import <SwiftyZeroMQ5/SwiftyZeroMQ.h>
#import <SwiftyZeroMQ5/zmq.h>

FOUNDATION_EXPORT double SwiftyZeroMQ5VersionNumber;
FOUNDATION_EXPORT const unsigned char SwiftyZeroMQ5VersionString[];

