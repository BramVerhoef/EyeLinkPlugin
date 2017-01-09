//
//  LLEyeLinkMonitor.m
//  Lablib
//
//  Created by John Maunsell on Wed Jan 29 2003.
//  Modified by Bram Verhoef 08/03/2012
//  Copyright (c) 2003. All rights reserved.
//

#import "LLEyeLinkMonitor.h"
#import <Lablib/LLSystemUtil.h>

NSString *doWarnDriftKey = @"LL EyeLink Do Warn Drift";
NSString *driftLimitKey = @"LL EyeLink Drift Limit";

@implementation LLEyeLinkMonitor

- (void)checkWarnings {

    double eyelinkSampleTimeMS, CPUMS, driftParts;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (![defaults boolForKey:[self uniqueKey:doWarnDriftKey]] || previous.sequences < 1) {
        return;
    }
	
	CPUMS = previous.cumulativeTimeMS;
	eyelinkSampleTimeMS = previous.samples * previous.samplePeriodMS;
    
	driftParts = ((eyelinkSampleTimeMS + CPUMS) / 2)/(CPUMS - eyelinkSampleTimeMS);
    if (fabs(driftParts) < [defaults integerForKey:[self uniqueKey:driftLimitKey]]) {
		NSLog(@"Warning: EyeLink clock drift is %d:%.0f relative to computer.", 
					driftParts >= 0 ? 1 : -1, driftParts);
		NSLog(@"previous.samples: %ld", previous.samples);
		NSLog(@"previous.samplePeriodMS: %f", previous.samplePeriodMS);
		NSLog(@"previous.sequences: %ld", previous.sequences);
		NSLog(@"previous.cumulativeTimeMS: %f", previous.cumulativeTimeMS);
        [self doAlarm:[NSString stringWithFormat:@"Warning: EyeLink clock drift is %d:%.0f relative to computer.",
				driftParts >= 0 ? 1 : -1, driftParts]];
	}
}

- (void)configure {

	[settings showWindow:self];
}

- (void)dealloc {

	[descriptionString release];
	[IDString release];
	[settings release];
	[super dealloc];
}

- (void)doAlarm:(NSString *)message {

	long choice;
	
	alarmActive = YES;
	choice = NSRunAlertPanel( [NSString stringWithFormat:@"LLEyeLinkMonitor (%@)", [self IDString]],
		message, @"OK", @"Disarm Alarm", @"Change Settings");
	switch (choice) {
	case NSAlertAlternateReturn:						// disarm alarms
		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:[self uniqueKey:doWarnDriftKey]];
		break;
	case NSAlertOtherReturn:
		[self configure];								// configure alarms
		break;
	case NSAlertDefaultReturn:							// OK button, do nothing
	default:
		break;
	}
	alarmActive = NO;
}


- (NSString *)IDString {

	return IDString;
}

- (id)initWithID:(NSString *)ID description:(NSString *)description {

    NSMutableDictionary *defaultSettings;

    if ((self = [super init]) != Nil) {

// ID must be set up before doing the default settings

		[ID retain];
		IDString = ID;
		[description retain];
		descriptionString = description;

// Set up all the default settings

		defaultSettings = [[NSMutableDictionary alloc] init];
		[defaultSettings setObject:[NSNumber numberWithBool:YES] forKey:[self uniqueKey:doWarnDriftKey]];
		[defaultSettings setObject:[NSNumber numberWithInt:100] forKey:[self uniqueKey:driftLimitKey]];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaultSettings];
		[defaultSettings release];

// Default settings should be done before initializing values

		settings = [[LLEyeLinkMonitorSettings alloc] initWithID:IDString monitor:self];
		[self initValues:&cumulative];
	}
    return self;
}

- (void)initValues:(EyeLinkMonitorValues *)pValues {

	long index;
	
 	pValues->samples = pValues->sequences = 0;
    pValues->cumulativeTimeMS = 0.0;

//	for (index = 0; index < 3; index++) {
//		pValues->ADMaxValues[index] = SHRT_MIN;
//		pValues->ADMinValues[index] = SHRT_MAX;
//	}
}

- (BOOL)isConfigurable {

	return YES;
}

- (NSAttributedString *)report {

	NSMutableString *textString;
    NSDictionary *attr;

	textString = [[[NSMutableString alloc] initWithString:descriptionString] autorelease];

	if (cumulative.sequences == 0) {
		[textString appendString:@"\n\n(No data sequences have been compiled)"];
	}
	else {
		[textString appendString:[NSString stringWithFormat:@"\n\n%ld sampling sequences completed\n\n", 
			cumulative.sequences]];
		if (previous.samples > 0) {
			[textString appendString:@"Last Sequence:\n\n"];
			[textString appendString:[self valueString:&previous]];
		}
		[textString appendString:@"All Sequences:\n\n"];
		[textString appendString:[self valueString:&cumulative]];
	}
    attr = [[[NSDictionary alloc] initWithObjectsAndKeys:
                    [NSFont userFixedPitchFontOfSize:10], NSFontAttributeName,
                    nil] autorelease];
	return [[[NSAttributedString alloc] initWithString:textString attributes:attr] autorelease];
}

- (void)resetCounters {

    [self initValues:&cumulative];
	[[NSNotificationCenter defaultCenter] postNotificationName:LLMonitorUpdated object:self];
}

- (NSString *)valueString:(EyeLinkMonitorValues *)pValues {

    long index;
    double eyelinkSampleTimeMS, CPUMS;
    NSMutableString *string = [[[NSMutableString alloc] init] autorelease];
    
    CPUMS = pValues->cumulativeTimeMS;
	eyelinkSampleTimeMS = pValues->samples * pValues->samplePeriodMS;
    [string appendString:[NSString stringWithFormat:
                @" Did %.0f ms of samples in %.0f ms (%.1f ms difference, 1:%.0f; ", 
                eyelinkSampleTimeMS, CPUMS, CPUMS - eyelinkSampleTimeMS, ((eyelinkSampleTimeMS + CPUMS) / 2)/(CPUMS - eyelinkSampleTimeMS)]];
	[string appendString:[NSString stringWithFormat:
                @"%.3f-%.3f ms period)\n\n Channel:", 
                pValues->cumulativeTimeMS / (pValues->samples + pValues->sequences), 
                pValues->cumulativeTimeMS / pValues->samples]];

    [string appendString:@"\n  Counts:"];

    [string appendString:@"\n   Per S:"];

    [string appendString:@"\n\n"];

    return [NSString stringWithString:string];
}

// Record the occurrence of an event.  This is the method that should be called 
// when the event being monitored occurs.

- (void)sequenceValues:(EyeLinkMonitorValues)current {

    long index;
    
	previous = current;									// Save for the report
    cumulative.samplePeriodMS = current.samplePeriodMS;
     
	cumulative.sequences += current.sequences;
	cumulative.cumulativeTimeMS += current.cumulativeTimeMS;
	cumulative.samples += current.samples;
    

//	for (index = 0; index < kLLITC18ADChannels; index++) {
//		cumulative.ADMaxValues[index] = MAX(cumulative.ADMaxValues[index], current.ADMaxValues[index]);
//		cumulative.ADMinValues[index] = MIN(cumulative.ADMinValues[index], current.ADMinValues[index]);
//	}

	[self checkWarnings];
	[[NSNotificationCenter defaultCenter] postNotificationName:LLMonitorUpdated object:self];
}

// Because there may be many instances of some objects, we save using keys that are made
// unique by prepending the IDString

- (NSString *)uniqueKey:(NSString *)commonKey {

	return [NSString stringWithFormat:@"%@ %@", IDString, commonKey]; 
}

@end
