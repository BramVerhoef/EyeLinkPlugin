//
//  LLEyeLinkDataDevice.m
//  Lablib
//
//  Created by Jon Hendry on 9/18/07.
//  Modified by Bram Verhoef 08/03/2012
//  Copyright 2007. All rights reserved.
//

#import <eyelink_core/eyelink.h>
#import <eyelink_core/core_expt.h>
#import <Lablib/LLPluginController.h>
#import <Lablib/LLSystemUtil.h>
#import "LLEyeLinkDataDevice.h"

#define maxELTime 0x7fffffff

//#define kUseLLDataDevices        // needed for versioning

volatile int shouldKillThread = 0;
BOOL firstTrialSample;
UINT32 ELTrialStartTimeMS;
long ELTrialStopTimeMS,firstSampleTime, lastSampleTime;
double previousMonitorStartTimeS = 0;

@implementation LLEyeLinkDataDevice

void handler(int signal) {
	stop_recording();
	printf("received signal: %d\n",signal);
	[[NSApplication sharedApplication] terminate:nil];
}

+ (int)version;
{
	return kLLPluginVersion;
}

- (void)dealloc;
{
    int index;
	if (eyelink_is_connected()) {
		set_offline_mode();					// place EyeLink tracker in off-line (idle) mode
		eyecmd_printf("close_data_file");    // close data file
		eyelink_close(1);					 // disconnect from tracker
	}
	close_eyelink_system();					// shut down system (MUST do before exiting)
	[dataLock lock];
	[lXData release];
	[lYData release];
	[lPData release];
	[rXData release];
	[rYData release];
	[rPData release];
	[dataLock unlock];
    [dataLock release];
	[deviceLock release];
	[monitor release];
	[super dealloc];
}

// If the link to the EyeLink computer is not opening, check that the IP address for the Mac port that connects to t
// the EyeLink has been set to Manual and 100.1.1.2 and subnet mask 255.255.255.0

- (id)init;
{ 
	int index, error;

	if ((self = [super init]) != nil) {
		
		NSLog(@"EyeLink Device init");

		lXData = [[NSMutableData alloc] init];
		lYData = [[NSMutableData alloc] init];
		lPData = [[NSMutableData alloc] init];
		rXData = [[NSMutableData alloc] init];
		rYData = [[NSMutableData alloc] init];
		rPData = [[NSMutableData alloc] init];

		pollThread = nil;
		deviceEnabled = NO;
		dataEnabled = NO;
		devicePresent = YES;
		EyeLinkSamplePeriodS = 0.002;
			
		dataLock = [[NSLock alloc] init];
		deviceLock = [[NSLock alloc] init];

// The NSMutableArry samplePeriodMS contains one entry for each possible channel.  We initialize it for 6
// (X, Y, and P for left and right eyes).  Default to 500 Hz (2 ms) sampling.
        
        for (index = 0; index < kEyeLinkChannels; index++) {
            [samplePeriodMS addObject:[NSNumber numberWithFloat:2.0F]];
		}
		monitor = [[LLEyeLinkMonitor alloc] initWithID:@"EyeLink" description:@"EyeLink Eye Monitor"];
		
		nextSampleTimeS += [[samplePeriodMS objectAtIndex:0] floatValue] * EyeLinkSamplePeriodS;
				
		if ((index = open_eyelink_connection(0))) {
			deviceEnabled = devicePresent = NO;            
		}
		else {
			deviceEnabled = devicePresent = YES;
			stop_recording();// make sure we're stopped
            NSLog(@"eyelink connection made");
		}
		if (deviceEnabled) {                            // find out which eyes are in play
			error = start_recording(0, 0, 1, 1);
			if (error != 0) {
				deviceEnabled = devicePresent = NO;
			}
			else {
				eye_used = eyelink_eye_available();
				if (eye_used == BINOCULAR) {
					eye_used = LEFT_EYE;
				}		
				stop_recording();
			}
		}
	}
	return self;
}

- (id <LLMonitor>)monitor;
{
	return monitor;
}

- (void)disableSampleChannels:(NSNumber *)bitPattern;
{
	if ([bitPattern unsignedLongValue] >= (0x01 << ([samplePeriodMS count] + 1))) { 
		NSRunAlertPanel(@"LLEyeLinkDataDevice",  
				@"Request to disable non-existent channel for device %@ (only %d channels)",
				@"OK", nil, nil, [self name], [samplePeriodMS count]);
		exit(0);
	}
	sampleChannels &= ~[bitPattern unsignedLongValue];
}

- (void)enableSampleChannels:(NSNumber *)bitPattern;
{
	if ([bitPattern unsignedLongValue] >= (0x01 << ([samplePeriodMS count] + 1))) { 
		NSRunAlertPanel(@"LLEyeLinkDataDevice",  
				@"Request to enable non-existent channel for device %@ (only %d channels)",
				@"OK", nil, nil, [self name], [samplePeriodMS count]);
		exit(0);
	}
	sampleChannels |= [bitPattern unsignedLongValue];
}

- (NSString *)name;
{
	return @"EyeLink";
}

- (float)samplePeriodMSForChannel:(long)channel;
{
	if (channel >= [samplePeriodMS count]) {
		NSRunAlertPanel(@"LLEyeLinkDataDevice", @"Requested sample period %ld of %d for device %@",
				@"OK", nil, nil, channel, [samplePeriodMS count], [self name]);
		exit(0);
	}
	return [[samplePeriodMS objectAtIndex:channel] floatValue];
}

- (long)sampleChannels;
{
	return [samplePeriodMS count];
}

- (void)pollSamples
{
	int index = 0;
    short difference;
	short sample = 0;
	FSAMPLE oldSample, newSample;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
	pollThread = [NSThread currentThread];
	
	while (YES) {
		if (shouldKillThread) {
            [pool release];
			pollThread = nil;
			[NSThread exit];
		}
		while (dataEnabled && 0 != eyelink_get_next_data(NULL)) {
            index= eyelink_get_float_data(&newSample);
            if (index == SAMPLE_TYPE && newSample.time >= ELTrialStartTimeMS) {
                [dataLock lock];
                difference = newSample.time - ELTrialStartTimeMS;
                if (firstTrialSample) {                                      
                    firstSampleTime = newSample.time;
                    firstTrialSample = NO;
                }
                else if (newSample.time - oldSample.time != [[samplePeriodMS objectAtIndex:0] floatValue]){
                    NSLog(@"Warning: Unexpected time interval between EyeLink samples, measured interval= %li ms",newSample.time - oldSample.time);
                }
                lastSampleTime = newSample.time;
                
                // At trial end, if pollSamples: does not return fast enough, an extra sample beyond 
                // ELTrialsStopTimeMs is fetched, so we prevent this here:
                
                if (ELTrialStopTimeMS - lastSampleTime >= [[samplePeriodMS objectAtIndex: 0] floatValue]){                    
                    sample = (short)(newSample.px[RIGHT_EYE]);
                    [rXData appendBytes:&sample length:sizeof(sample)];
                    sample = (short)(-newSample.py[RIGHT_EYE]);
                    [rYData appendBytes:&sample length:sizeof(sample)];
                    sample = (short)(newSample.pa[RIGHT_EYE]);
                    [rPData appendBytes:&sample length:sizeof(sample)];
                    sample = (short)(newSample.px[LEFT_EYE]);
                    [lXData appendBytes:&sample length:sizeof(sample)];
                    sample = (short)(-newSample.py[LEFT_EYE]);
                    [lYData appendBytes:&sample length:sizeof(sample)];
                    sample = (short)(newSample.pa[LEFT_EYE]);
                    [lPData appendBytes:&sample length:sizeof(sample)];
                    values.samples++;
                }
                oldSample = newSample;
                [dataLock unlock];
            }
        }
        if (!dataEnabled && values.samples != 0) {
            [pool release];
             pool = [[NSAutoreleasePool alloc] init];
        }
        usleep(1000);// sleep 1 ms
    }
}


- (NSData **)sampleData;
{
    //if (!pauseSampleData) {
        short sample, index;
        NSMutableData  *lXDataCopy, *lYDataCopy, *lPDataCopy, *rXDataCopy, *rYDataCopy, *rPDataCopy;
        NSMutableData *samples;
        NSArray *sampleArray;
        
        // Lock, then copy pointers to the sample data
        
        [dataLock lock];
        sampleArray = [NSArray arrayWithObjects:lXData, lYData, lPData, rXData, rYData, rPData, nil];
        
        //Now alloc/init new data instances and swap those in
        //(For performance reasons, it might be worthwhile to preallocate two sets of these, and swap them in and out)
        
        lXData = [[NSMutableData alloc] init];
        lYData = [[NSMutableData alloc] init];
        lPData = [[NSMutableData alloc] init];
        rXData = [[NSMutableData alloc] init];
        rYData = [[NSMutableData alloc] init];
        rPData = [[NSMutableData alloc] init];
        
        [dataLock unlock];
        
        // Bundle the data pointers into an array.  If the channel is disabled, nil is returned.  If the
        // data length is zero, nil is returned.
        
        for (index = 0; index < kEyeLinkChannels; index++) {
            samples = [sampleArray objectAtIndex:index];
            if (!(sampleChannels & (0x1 << index))) {                   // disabled channel
                sampleData[index] = nil;                                // not enabled or no samples
            }
            else if ([samples length] == 0) {                           // no data samples
                sampleData[index] = nil;                                // not enabled or no samples
            }
            else {
                sampleData[index] = samples;
            }
            [samples autorelease];
        }
        return sampleData;
    //}
//    else {
//        return nil;
//    }
}

- (void)setDataEnabled:(NSNumber *)state;
{
    int available, error;
	long channel;
	double channelPeriodMS;
	long maxSamplingRateHz = 1000;
	
	if ([state boolValue] && !dataEnabled) {						// toggle from OFF to ON
//        [deviceLock lock];
		if (maxSamplingRateHz != 0) {
            // no channels enabled            
            ELTrialStartTimeMS = [self current_tracker_time];
            ELTrialStopTimeMS = maxELTime;
			monitorStartTimeS = [LLSystemUtil getTimeS];
            firstTrialSample = YES;
			sampleTimeS = EyeLinkSamplePeriodS;						// one period complete on first sample
			justStartedEyeLink = YES;
			//[deviceLock lock];
			//start_recording(0,0,1,0);                               // tell device to start recording
			//[deviceLock unlock];
			[monitor initValues:&values];
			values.samplePeriodMS = EyeLinkSamplePeriodS * 1000.0;
            lastReadDataTimeS = 0;
			dataEnabled = YES;
		}
//        [deviceLock unlock];
	} 
	else if (![state boolValue] && dataEnabled) {					// toggle from ON to OFF
		lastReadDataTimeS = 0;
		//[deviceLock lock];
		//stop_recording();
		//[deviceLock unlock];
        values.sequences = 1;
        ELTrialStopTimeMS = eyelink_tracker_msec();
        values.cumulativeTimeMS = ([LLSystemUtil getTimeS] - monitorStartTimeS) * 1000.0;
        while (ELTrialStopTimeMS - lastSampleTime >= [[samplePeriodMS objectAtIndex:0] floatValue]) {  //Generally, the EyeLink queue fills slowly, so we wait until all scheduled samples are collected
            usleep(1000);
        }
        dataEnabled = NO;
        [monitor sequenceValues:values];
        previousMonitorStartTimeS = monitorStartTimeS;
	}
}

- (void)setDeviceEnabled:(NSNumber *)state;
{
    int error;
    
	if (![state boolValue] && deviceEnabled) {						// Disable the device
		[self setDataEnabled:NO];
        stop_recording();
        deviceEnabled = NO;
		shouldKillThread = YES;
		while (pollThread != nil) {
			usleep(100);
		}
		//stop_recording();
//		signal(SIGKILL, SIG_DFL);
//		//signal(SIGINT, SIG_DFL);
//		signal(SIGQUIT, SIG_DFL);
//		signal(SIGILL, SIG_DFL);
//		signal(SIGABRT, SIG_DFL);
//		signal(SIGSEGV, SIG_DFL);
//		signal(SIGTERM, SIG_DFL);
	}
	
	if ([state boolValue] && !deviceEnabled) {						// Enable the device
		deviceEnabled = YES;
		signal(SIGKILL, handler);
		//signal(SIGINT, handler);
		signal(SIGQUIT, handler);
		signal(SIGILL, handler);
		signal(SIGABRT, handler);
		signal(SIGSEGV, handler);
		signal(SIGTERM, handler);
		if (pollThread == nil) {
			shouldKillThread = NO;
			[NSThread detachNewThreadSelector:@selector(pollSamples) toTarget:self withObject:nil];
			//error = start_recording(0, 0, 1, 0);                    // Eyelink: link, not file, samples, no events
		}
	}
}

- (BOOL)setSamplePeriodMS:(float)newPeriodMS channel:(long)channel;
{
	if (channel >= [samplePeriodMS count]) {
		NSRunAlertPanel(@"LLEyeLinkDataDevice", @"Attempt to set sample period %ld of %d for device %@",
				@"OK", nil, nil, channel, [samplePeriodMS count], [self name]);
		exit(0);
	}
	[samplePeriodMS replaceObjectAtIndex:channel 
					withObject:[NSNumber numberWithFloat:newPeriodMS]];
	return YES;
}

- (void)startDevice;
{
    
    if (check_recording() != 0) {
        NSLog(@"*************EyeLink startDevice");
        [deviceLock lock];
        start_recording(0,0,1,0);                               // tell device to start recording
        [deviceLock unlock];
    }
}

- (void)stopDevice;
{
    if (check_recording() == 0) {
        NSLog(@"*************EyeLink stopDevice");
        [deviceLock lock];
        stop_recording();
        [deviceLock unlock];
    }
}


/* This program replaces the eyelink_tracker_msec function, which gave often wrong values, to retrieve the
 current tracker time */
/* This routine is used to retrieve the concurrent tracker PC time. */
/* If successful, this function returns the tracker PC time, else 0; */
/* Note, the waiting time is set as 50 msec, although normally the */ /*
function should return within 1 msec */

-(UINT32) current_tracker_time
{
    UINT32 time_subject=0, time_tracker=0;
    eyelink_request_time();
    time_subject = current_msec();
    
    while(!time_tracker && current_msec() -time_subject < 50)
        time_tracker = eyelink_read_time();
    
    return time_tracker;
    
}


@end