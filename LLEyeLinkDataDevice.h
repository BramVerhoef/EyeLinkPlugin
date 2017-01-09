//
//  LLEyeLinkDataDevice.h 
//  Lablib
//
//  Created by Jon Hendry on 9/18/07.
//  Modified by Bram Verhoef 08/03/2012
//  Copyright 2005-2011 All rights reserved.
//
#import <Lablib/LLDataDevice.h>
#import "LLEyeLinkMonitor.h"

enum {kRXChannel = 0, kRYChannel, kRPChannel, kLXChannel, kLYChannel, kLPChannel, kEyeLinkChannels};

@interface LLEyeLinkDataDevice : LLDataDevice {

	int						eye_used;
	double					nextSampleTimeS;
	double					EyeLinkSamplePeriodS;
	double					sampleTimeS;
	double					monitorStartTimeS;
	double					lastReadDataTimeS;
	BOOL					justStartedEyeLink;
	NSMutableData			*sampleData[kEyeLinkChannels];
	NSMutableData			*lXData, *lYData, *lPData;
	NSMutableData			*rXData, *rYData, *rPData;
	NSLock					*dataLock;
	NSLock					*deviceLock;
	NSThread				*pollThread;
	LLEyeLinkMonitor		*monitor;
	EyeLinkMonitorValues	values;
}

- (void)disableSampleChannels:(NSNumber *)bitPattern;
- (void)enableSampleChannels:(NSNumber *)bitPattern;
- (NSString *)name;
- (long)sampleChannels;
- (NSData **)sampleData;
- (float)samplePeriodMSForChannel:(long)channel;
- (void)setDataEnabled:(NSNumber *)state;
- (void)setDeviceEnabled:(NSNumber *)state;
- (BOOL)setSamplePeriodMS:(float)newPeriodMS channel:(long)channel;
- (UInt32)current_tracker_time;

@end