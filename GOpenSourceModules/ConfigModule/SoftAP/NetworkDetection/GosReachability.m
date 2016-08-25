/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Basic demonstration of how to use the SystemConfiguration Reachablity APIs.
 */

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <sys/socket.h>

#import <CoreFoundation/CoreFoundation.h>

#import "GosReachability.h"

#import "GizLog.h"


NSString *kGizReachabilityChangedNotification = @"kGizNetworkReachabilityChangedNotification";


#pragma mark - Supporting functions

#define kShouldPrintReachabilityFlags 1

static void PrintReachabilityFlags(SCNetworkReachabilityFlags flags, const char* comment) {
#if kShouldPrintReachabilityFlags

    GIZ_LOG_DEBUG("Reachability Flag Status: %c%c %c%c%c%c%c%c%c %s\n",
          (flags & kSCNetworkReachabilityFlagsIsWWAN)				? 'W' : '-',
          (flags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-',

          (flags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-',
          (flags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-',
          (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-',
          (flags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-',
          (flags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-',
          (flags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-',
          (flags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-',
          comment
          );
#endif
}


static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
#pragma unused (target, flags)
	NSCAssert(info != NULL, @"info was NULL in ReachabilityCallback");
	NSCAssert([(__bridge NSObject *) info isKindOfClass: [GosReachability class]], @"info was wrong class in ReachabilityCallback");

    GosReachability* noteObject = (__bridge GosReachability *)info;
    // Post a notification to notify the client that the network reachability changed.
    [[NSNotificationCenter defaultCenter] postNotificationName: kGizReachabilityChangedNotification object: noteObject];
}


#pragma mark - Reachability implementation

@implementation GosReachability {
	BOOL _alwaysReturnLocalWiFiStatus; //default is NO
	SCNetworkReachabilityRef _reachabilityRef;
}

+ (instancetype)reachabilityWithHostName:(NSString *)hostName {
	GosReachability* returnValue = NULL;
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, [hostName UTF8String]);
	if (reachability != NULL) {
		returnValue= [[self alloc] init];
		if (returnValue != NULL) {
			returnValue->_reachabilityRef = reachability;
			returnValue->_alwaysReturnLocalWiFiStatus = NO;
		} else {
            CFRelease(reachability);
        }
	}
	return returnValue;
}


+ (instancetype)reachabilityWithAddress:(const struct sockaddr_in *)hostAddress {
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)hostAddress);

	GosReachability* returnValue = NULL;

	if (reachability != NULL) {
		returnValue = [[self alloc] init];
		if (returnValue != NULL) {
			returnValue->_reachabilityRef = reachability;
			returnValue->_alwaysReturnLocalWiFiStatus = NO;
		} else {
            CFRelease(reachability);
        }
	}
	return returnValue;
}



+ (instancetype)reachabilityForInternetConnection {
	struct sockaddr_in zeroAddress;
	bzero(&zeroAddress, sizeof(zeroAddress));
	zeroAddress.sin_len = sizeof(zeroAddress);
	zeroAddress.sin_family = AF_INET;
    
	return [self reachabilityWithAddress:&zeroAddress];
}


+ (instancetype)reachabilityForLocalWiFi {
	struct sockaddr_in localWifiAddress;
	bzero(&localWifiAddress, sizeof(localWifiAddress));
	localWifiAddress.sin_len = sizeof(localWifiAddress);
	localWifiAddress.sin_family = AF_INET;

	// IN_LINKLOCALNETNUM is defined in <netinet/in.h> as 169.254.0.0.
	localWifiAddress.sin_addr.s_addr = htonl(IN_LINKLOCALNETNUM);

	GosReachability* returnValue = [self reachabilityWithAddress: &localWifiAddress];
	if (returnValue != NULL) {
		returnValue->_alwaysReturnLocalWiFiStatus = YES;
	}
    
	return returnValue;
}


#pragma mark - Start and stop notifier

- (BOOL)startNotifier {
	BOOL returnValue = NO;
	SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};

	if (SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context)) {
		if (SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)) {
			returnValue = YES;
		}
	}
    
	return returnValue;
}


- (void)stopNotifier {
	if (_reachabilityRef != NULL) {
        SCNetworkReachabilitySetCallback(_reachabilityRef, nil, nil);
		SCNetworkReachabilityUnscheduleFromRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	}
}


- (void)dealloc {
	[self stopNotifier];
	if (_reachabilityRef != NULL) {
		CFRelease(_reachabilityRef);
	}
}


#pragma mark - Network Flag Handling

- (GizNetworkStatus)localWiFiStatusForFlags:(SCNetworkReachabilityFlags)flags {
	PrintReachabilityFlags(flags, "localWiFiStatusForFlags");
	GizNetworkStatus returnValue = GizNotReachable;

	if ((flags & kSCNetworkReachabilityFlagsReachable) && (flags & kSCNetworkReachabilityFlagsIsDirect)) {
		returnValue = GizReachableViaWiFi;
	}
    
	return returnValue;
}


- (GizNetworkStatus)networkStatusForFlags:(SCNetworkReachabilityFlags)flags {
	PrintReachabilityFlags(flags, "networkStatusForFlags");
	if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
		// The target host is not reachable.
		return GizNotReachable;
	}

    GizNetworkStatus returnValue = GizNotReachable;

	if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
		/*
         If the target host is reachable and no connection is required then we'll assume (for now) that you're on Wi-Fi...
         */
		returnValue = GizReachableViaWiFi;
	}

	if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) ||
        (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0)) {
        /*
         ... and the connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs...
         */

        if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
            /*
             ... and no [user] intervention is needed...
             */
            returnValue = GizReachableViaWiFi;
        }
    }

	if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
		/*
         ... but WWAN connections are OK if the calling application is using the CFNetwork APIs.
         */
		returnValue = GizReachableViaWWAN;
	}
    
	return returnValue;
}


- (BOOL)connectionRequired {
	NSAssert(_reachabilityRef != NULL, @"connectionRequired called with NULL reachabilityRef");
	SCNetworkReachabilityFlags flags;

	if (SCNetworkReachabilityGetFlags(_reachabilityRef, &flags)) {
		return (flags & kSCNetworkReachabilityFlagsConnectionRequired);
	}

    return NO;
}


- (GizNetworkStatus)currentReachabilityStatus {
	NSAssert(_reachabilityRef != NULL, @"currentNetworkStatus called with NULL SCNetworkReachabilityRef");
	GizNetworkStatus returnValue = GizNotReachable;
	SCNetworkReachabilityFlags flags;
    
	if (SCNetworkReachabilityGetFlags(_reachabilityRef, &flags)) {
		if (_alwaysReturnLocalWiFiStatus) {
			returnValue = [self localWiFiStatusForFlags:flags];
		} else {
			returnValue = [self networkStatusForFlags:flags];
		}
	}
    
	return returnValue;
}

- (BOOL)isConnectingWiFi {
    SCNetworkReachabilityFlags flags;
    
    if (SCNetworkReachabilityGetFlags(_reachabilityRef, &flags)) {
        PrintReachabilityFlags(flags, "isConnectingWiFi");
        if (flags & kSCNetworkReachabilityFlagsReachable) {
            if (flags & kSCNetworkReachabilityFlagsIsWWAN && flags & kSCNetworkReachabilityFlagsTransientConnection) {
                return YES;
            }
        } else if (!(flags & kSCNetworkReachabilityFlagsIsWWAN) && !(flags & kSCNetworkReachabilityFlagsTransientConnection)) {
            return YES;
        }
    }
    return NO;
}

@end
