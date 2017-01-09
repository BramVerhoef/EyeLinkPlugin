//
//  LLEyeLinkMonitor.h
//  Lablib
//
//  Created by John Maunsell on Wed Jan 29 2003.
//  Copyright (c) 2003 . All rights reserved.
//

#import "LLEyeLinkMonitorSettings.h"
#import <Lablib/LLMonitor.h>
#import <Lablib/LLIODevice.h>

extern NSString	*doWarnDriftKey;
extern NSString	*driftLimitKey;

typedef struct {
	double	cumulativeTimeMS;							// duration of sequence based on CPU clock
	long	samples;									// number of sample sets collected
    double	samplePeriodMS;								// period for one sample set
    long 	sequences;
} EyeLinkMonitorValues;

@interface  LLEyeLinkMonitor : NSObject <LLMonitor> {
@private
	BOOL						alarmActive;
	EyeLinkMonitorValues 		cumulative;
	NSString					*descriptionString;				// First line in report
	NSString					*IDString;						// Short string for menu entry
	EyeLinkMonitorValues 		previous;
	double						samplePeriodMS;
	double						sequenceStartTimeMS;			// start of current sequence
	LLEyeLinkMonitorSettings	*settings;
}

- (void)doAlarm:(NSString *)message;
- (void)initValues:(EyeLinkMonitorValues *)pValues;
- (id)initWithID:(NSString *)ID description:(NSString *)description;
- (void)resetCounters;
- (void)sequenceValues:(EyeLinkMonitorValues)current;
- (NSString *)valueString:(EyeLinkMonitorValues *)pValues;
- (NSString *)uniqueKey:(NSString *)commonKey;

@end


