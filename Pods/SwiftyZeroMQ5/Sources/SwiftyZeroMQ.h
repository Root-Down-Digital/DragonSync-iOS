//
// Copyright (c) 2016-2017 Ahmad M. Zawawi (azawawi)
//
// This package is distributed under the terms of the MIT license.
// Please see the accompanying LICENSE file for the full text of the license.
//

// Provides target conditional macros
#import <TargetConditionals.h>

// Import appropriate library depending on target being iOS/tvOS/watchOS or
// macOS
#if TARGET_OS_IPHONE
    #import <UIKit/UIKit.h>
#else
    #import <Cocoa/Cocoa.h>
#endif

// Import libzmq functions and constants into Swift
#import <SwiftyZeroMQ5/zmq.h>

//! Project version number for SwiftySwiftyZeroMQ.
FOUNDATION_EXPORT double SwiftyZeroMQVersionNumber;

//! Project version string for SwiftySwiftyZeroMQ.
FOUNDATION_EXPORT const unsigned char SwiftyZeroMQVersionString[];
