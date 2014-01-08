//
//  AudioController.m
//  bluetoothTestApp
//
//  Created by Sean Brown on 11/25/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import "AudioController.h"
#import <AudioToolbox/AudioToolbox.h>
#import "DigiScopeAppAppDelegate.h"
#import "Recording.h"

#define kOutputBus 0
#define kInputBus 1
#define bluetoothOnly 0
#define disableAUIfHardwareNotAvailable 1

// Draw Specifications

#define kNumDrawBuffers 6
#define kNumECGDrawBuffers 2
#define kDefaultDrawSamples 1024
#define kMinDrawSamples 64
#define kMaxDrawSamples 4096

SInt8 *drawBuffers[kNumDrawBuffers];
SInt8 *ECGBuffers[kNumECGDrawBuffers];
int drawBufferIdx = 0;
int ECGDrawBufferIdx = 0;
int drawBufferLen = kDefaultDrawSamples;
int ECGBufferLen = 4096;
int drawBufferLen_alloced = 0;
int ECGBuferLen_alloced = 0;
int currentECGBuffer = 0;
BOOL ECGInUse = FALSE;

@implementation AudioController
@synthesize myAppDelegate, fetchedRecordings, loadFromData, viewDelegate, hardwareAttached, view;

#pragma mark Shared Instance

+(AudioController *)sharedInstance{
	static AudioController *myInstance = nil;
	
	if (nil==myInstance) {
		myInstance = [[[self class] alloc] init];
		[myInstance setUpAudioSession];
		[myInstance initializeAudioUnit];
	}
	return myInstance;
}

void cycleOscilloscopeLines()
{
	// Cycle the lines in our draw buffer so that they age and fade. The oldest line is discarded.
	int drawBuffer_i;
	for (drawBuffer_i=(kNumDrawBuffers - 2); drawBuffer_i>=0; drawBuffer_i--)
			memmove(drawBuffers[drawBuffer_i + 1], drawBuffers[drawBuffer_i], drawBufferLen);
}

#pragma mark IOUnit_RenderCallBack

// Render Call Back
static OSStatus renderInput(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
	AudioController *THIS = (__bridge AudioController *)inRefCon;
	OSStatus err = AudioUnitRender(THIS->ioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
	
	{
		
		// The draw buffer is used to hold a copy of the most recent PCM data to be drawn
		if (drawBufferLen != drawBufferLen_alloced)
		{
			int drawBuffer_i;
			// Allocate our draw buffer if needed
			if (drawBufferLen_alloced == 0)
				for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
					drawBuffers[drawBuffer_i] = NULL;
			
			// Fill the first element in the draw buffer with PCM data
			for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
			{
				drawBuffers[drawBuffer_i] = (SInt8 *)realloc(drawBuffers[drawBuffer_i], drawBufferLen);
				bzero(drawBuffers[drawBuffer_i], drawBufferLen);
				//printf("%s",drawBuffers[drawBuffer_i]);
				
			}
			
			drawBufferLen_alloced = drawBufferLen;
		}
		
		// The draw buffer is used to hold a copy of the most recent PCM data to be drawn
		if (ECGBufferLen != ECGBuferLen_alloced)
		{
			int drawBuffer_i;
			// Allocate our draw buffer if needed
			if (ECGBuferLen_alloced == 0)
				for (drawBuffer_i=0; drawBuffer_i<kNumECGDrawBuffers; drawBuffer_i++)
					ECGBuffers[drawBuffer_i] = NULL;
			
			// Fill the first element in the draw buffer with PCM data
			for (drawBuffer_i=0; drawBuffer_i<kNumECGDrawBuffers; drawBuffer_i++)
			{
				ECGBuffers[drawBuffer_i] = (SInt8 *)realloc(ECGBuffers[drawBuffer_i], ECGBufferLen);
				bzero(ECGBuffers[drawBuffer_i], ECGBufferLen);
				//printf("%s",drawBuffers[drawBuffer_i]);
				
			}
			
			drawBufferLen_alloced = drawBufferLen;
		}
		
		int i;

        //Convert the floating point audio data to integer (Q7.24)
        err = AudioConverterConvertComplexBuffer(THIS->audioConverter, inNumberFrames, ioData, THIS->drawABL);
		//printf("%i\n", (unsigned int)(*ioData).mBuffers[0].mDataByteSize);
		//printf("%i\n", (unsigned int)(*THIS->drawABL).mBuffers[0].mDataByteSize);
		
        if (err) {
			printf("AudioConverterConvertComplexBuffer: error %d\n", (int)err);
			return err;
		}
        
		
		SInt8 *data_ptr = (SInt8 *)(THIS->drawABL->mBuffers[0].mData);
		for (i=0; i<inNumberFrames; i++)
		{
			if (!ECGInUse) {
				if ((i+drawBufferIdx) >= drawBufferLen)
				{
					cycleOscilloscopeLines();
					drawBufferIdx = -i;
				}
				drawBuffers[0][i + drawBufferIdx] = data_ptr[2];
				ECGDrawBufferIdx = 0;
			}
			else{
				if ((i+ECGDrawBufferIdx) >= ECGBufferLen){
					ECGDrawBufferIdx = -i;
					if (currentECGBuffer)
						currentECGBuffer = 0;
					else
						currentECGBuffer = 1;
				}
				ECGBuffers[currentECGBuffer][i + drawBufferIdx] = data_ptr[2];
				drawBufferIdx = 0;
			}
			data_ptr += 4;
		}
		
		drawBufferIdx += inNumberFrames;
		ECGDrawBufferIdx += inNumberFrames;

	}
	
	return err;
	
}

#pragma mark AudioSession/RIOUnit Methods

-(void)initializeAudioUnit{
	
	OSStatus status;
	loadFromData = FALSE;
	
	// Describe audio component
	AudioComponentDescription desc;
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	// Get component
	AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
	
	// Get audio units
	status = AudioComponentInstanceNew(inputComponent, &ioUnit);
	
	if (status != noErr)
		printf("Error in AudioComponentInstanceNew");
	
	// Enable IO for recording
	UInt32 flag = 1;
	status = AudioUnitSetProperty(ioUnit,
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Input,
								  kInputBus,
								  &flag,
								  sizeof(flag));
	
	// Enable IO for playback
	status = AudioUnitSetProperty(ioUnit,
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Output,
								  kOutputBus,
								  &flag,
								  sizeof(flag));
	
	if (status != noErr)
		printf("Error in Enabling Input");
	
	
	// Connecting the ioUnit input to the ioUnit output: Audio Streaming
	AudioUnitConnection AUConnection;
	AUConnection.sourceAudioUnit = ioUnit;
	AUConnection.destInputNumber = 1;
	AUConnection.sourceOutputNumber = 0;
	
	status = AudioUnitSetProperty(ioUnit,
								  kAudioUnitProperty_MakeConnection,
								  kAudioUnitScope_Input,
								  1,
								  &AUConnection, sizeof(AUConnection));
	
	if (status != noErr)
		printf("\nError in Connection");
	
	// Any Additional Stream Formating
	/*
	 AudioStreamBasicDescription outFormat;
	 outFormat.mSampleRate = 44100.0;
	 outFormat.mFormatID = kAudioFormatLinearPCM;
	 outFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
	 outFormat.mFramesPerPacket	= 1;
	 outFormat.mChannelsPerFrame	= 1;
	 outFormat.mBitsPerChannel		= 16;
	 outFormat.mBytesPerPacket		= 2;
	 outFormat.mBytesPerFrame		= 2;
	 
	 status = AudioUnitSetProperty(ioUnit,
	 kAudioUnitProperty_StreamFormat,
	 kAudioUnitScope_Output,
	 kInputBus,
	 &outFormat,
	 sizeof(outFormat));
	 
	 status = AudioUnitSetProperty(ioUnit,
	 kAudioUnitProperty_StreamFormat,
	 kAudioUnitScope_Input,
	 kOutputBus,
	 &outFormat,
	 sizeof(outFormat));
	 */
	
	// Configure and Set the Render Callback function (needed to render the audio)
	AURenderCallbackStruct	inputProc;
	inputProc.inputProc = renderInput;
	inputProc.inputProcRefCon = (__bridge void *)(self);
	
	status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &inputProc, sizeof(inputProc));
	
	if (status != noErr)
		printf("\nError setting Render Callback");
	
	// Initialize the Unit and confirm that all connections are correct
	status = AudioUnitInitialize(ioUnit);
	if (status != noErr)
		printf("\nError in AUInitialize");
	
	UInt32 maxFPS;
	UInt32 size = sizeof(maxFPS);
	AudioUnitGetProperty(ioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, &size);
	
	// Set up buffers
	drawABL = (AudioBufferList*) malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
	drawABL->mNumberBuffers = 2;
	for (UInt32 i=0; i<drawABL->mNumberBuffers; ++i)
	{
		drawABL->mBuffers[i].mData = (SInt32*) calloc(maxFPS, sizeof(SInt32));
		drawABL->mBuffers[i].mDataByteSize = maxFPS * sizeof(SInt32);
		drawABL->mBuffers[i].mNumberChannels = 1;
	}
	
	oscilLine = (GLfloat*)malloc(drawBufferLen * 2 * sizeof(GLfloat));
	
	thruFormat = CAStreamBasicDescription(44100, kAudioFormatLinearPCM, 4, 1, 4, 2, 32, kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved);
	drawFormat.SetAUCanonical(2, false);
	drawFormat.mSampleRate = 44100;
	AudioConverterNew(&thruFormat, &drawFormat, &audioConverter);
	
}



+(BOOL)startAudioUnit{
	// Start the AUGraph
	OSStatus status = noErr;
	if (([AudioController sharedInstance].hardwareAttached & disableAUIfHardwareNotAvailable) || !disableAUIfHardwareNotAvailable)
		status = AudioOutputUnitStart([AudioController sharedInstance]->ioUnit);
	else{
		NSLog(@"Error, Cannot Initialize Audio Unit because Proper Hardware was not Detected");
		return  FALSE;
	}
		
	if (status != noErr){
		printf("\nError in Turning on the Output (AudioController)");
		return FALSE;
	}
	
	return TRUE;
}

+(void)stopAudioUnit{
	
	// Check if AUGrapph is Running
	OSStatus status;
	status = AudioOutputUnitStop([AudioController sharedInstance]->ioUnit);
	if (status != noErr)
		printf("\nError in Turning off on the Output (AudioController)");
	
}

-(void)setUpAudioSession{
	
	hardwareAttached = FALSE;
	
	// Set up App Delegate
	if (myAppDelegate == NULL)
		myAppDelegate = (DigiScopeAppAppDelegate *)[[UIApplication sharedApplication] delegate];
	
	
	NSError *error;
	
	AudioSession = [AVAudioSession sharedInstance];
	
	// Set Category
	[AudioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:&error];
	
	if (error != nil)
		NSLog(@"\nError in Setting the Audio Session Category: %@", [error localizedDescription]);
	
	// Set Sample Rate
	[AudioSession setPreferredSampleRate:44100.0 error:&error];
	if (error != nil)
		NSLog(@"\nError in Setting the Preferred Sample Rate: %@", [error localizedDescription]);
	
	[AudioSession setPreferredIOBufferDuration:23.0 error:&error];
	if (error) NSLog(@"Error in Setting Buffer Duration");
	error = nil;
	
	// Set Active
	[AudioSession setActive:YES error:&error];
	
	if (error != nil)
		NSLog(@"\nError in Setting the Audio Session Active: %@", [error localizedDescription]);
	
	// Set Input Settings
	for (AVAudioSessionPortDescription *mDes in AudioSession.availableInputs) {
		if ([mDes.portType isEqualToString:AVAudioSessionPortBluetoothHFP] || [mDes.portType isEqualToString:AVAudioSessionPortBluetoothA2DP]) {
			[AudioSession setPreferredInput:mDes error:&error];
			if (error != nil)
				NSLog(@"\nError Setting the Input to Bluetooth, although Input was discovered: %@", [error localizedDescription]);
			else
				hardwareAttached = TRUE;
		}
	}
	
	if (!hardwareAttached && !bluetoothOnly) {
		for (AVAudioSessionPortDescription *mDes in AudioSession.availableInputs) {
			if ([mDes.portType isEqualToString:AVAudioSessionPortHeadsetMic]) {
				[AudioSession setPreferredInput:mDes error:&error];
				if (error != nil)
					NSLog(@"\nError Setting the Input to Headset Mic, although Mic was discovered: %@", [error localizedDescription]);
				else
					hardwareAttached = TRUE;
			}
			
		}
	}
	
	baseFileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"AudioFile"]]];

	
}

+(void)setAudioSessionActive:(BOOL)setActive{
	NSError *error;
	[[AudioController sharedInstance]->AudioSession setActive:setActive error:&error];
	
	if (error != nil)
		NSLog(@"\nError in Setting the Audio Session Active/Inactive: %@", [error localizedDescription]);
}

#pragma mark Recording Methods

+(void)initializeRecorder{
	NSError *error;
	
	[AudioController sharedInstance]->RecordingController = [[AVAudioRecorder alloc] initWithURL:[AudioController sharedInstance]->baseFileURL settings:nil error:&error];
	if (error != nil)
		NSLog(@"\nError in initializing Recorder with temporary URL: %@", [error localizedDescription]);
	
	[[AudioController sharedInstance]->RecordingController setDelegate:self];
	BOOL success = [[AudioController sharedInstance]->RecordingController prepareToRecord];
	if (!success)
		NSLog(@"\nError, Recorder did not prepare");
}

+(void)startRecording{
	if (![[AudioController sharedInstance]->RecordingController isRecording]){
		[self initializeRecorder];
		BOOL success = [[AudioController sharedInstance]->RecordingController record];
		if (!success)
			NSLog(@"\nError, Recorder did not start recording");
			
	}
	else
		NSLog(@"\nError, recorder is already running");
	
}

+(void)stopRecording{
	if ([[AudioController sharedInstance]->RecordingController isRecording]){
		[[AudioController sharedInstance]->RecordingController stop];
	}
	else
		NSLog(@"\nError, recorder isn't running");
	
}

+(BOOL)isRecording{
	return [[AudioController sharedInstance]->RecordingController isRecording];
}

+(void)exportRecording{
	
}

#pragma mark Player Methods
+(void)initializePlayer{
	NSError *error;
	
	[AudioController sharedInstance]->PlayingController = [[AVAudioPlayer alloc] initWithContentsOfURL:[AudioController sharedInstance]->baseFileURL error:&error];
	
	if (error != nil)
		NSLog(@"\nError in initializing Player with temporary URL: %@", [error localizedDescription]);
	
	if ([AudioController sharedInstance]->PlayingController.duration == 0)
		NSLog(@"\nWarning: Player was initialized with an empty audio file");
	
	[[AudioController sharedInstance]->PlayingController prepareToPlay];
	
}

+(float)startPlaying{
	if (![[AudioController sharedInstance]->PlayingController isPlaying]){
		[self stopAudioUnit];
		[self initializePlayer];
		[[AudioController sharedInstance]->PlayingController play];
	}
	else
		NSLog(@"Error, play is currently playing");
	return [AudioController sharedInstance]->PlayingController.duration;
}

+(void)stopPlaying{
	if ([[AudioController sharedInstance]->PlayingController isPlaying]){
		[[AudioController sharedInstance]->PlayingController stop];
		[self startAudioUnit];
	}
	else
		NSLog(@"Error, player is not currently playing");
}

+(BOOL)isPlaying{
	return [[AudioController sharedInstance]->PlayingController isPlaying];
}

+(BOOL)saveRecording:(NSString *)patientFirstName :(NSString *)patientLastName{
	Recording *recording = [NSEntityDescription insertNewObjectForEntityForName:@"Recording" inManagedObjectContext:[AudioController sharedInstance]->myAppDelegate.managedObjectContext];
	recording.recordingPatientFirstName = patientFirstName;
	recording.recordingPatientLastName = patientLastName;
	recording.recordingDate = [NSDate date];
	recording.recordingData = [NSData dataWithContentsOfURL:[AudioController sharedInstance]->baseFileURL];
	
	NSError *error = nil;
	if ([[AudioController sharedInstance]->myAppDelegate.managedObjectContext hasChanges]) {
		if (![[AudioController sharedInstance]->myAppDelegate.managedObjectContext save:&error]){
			NSLog(@"\nSave Failed: %@", [error localizedDescription]);
			return FALSE;
		}
		else{
			NSLog(@"\nSave Succeeded");
			return TRUE;
		}
	}
	
	return FALSE;
}

+(BOOL)loadAllRecordings{
	BOOL success = FALSE;
	NSError *error = nil;
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	NSManagedObjectContext *context = [[AudioController sharedInstance]->myAppDelegate managedObjectContext];
	NSEntityDescription *entityDesc = [NSEntityDescription entityForName:@"Recording" inManagedObjectContext:[[AudioController sharedInstance]->myAppDelegate managedObjectContext]];
	NSSortDescriptor *sortLastName = [NSSortDescriptor sortDescriptorWithKey:@"recordingPatientLastName" ascending:YES];
	NSSortDescriptor *sortFirstName = [NSSortDescriptor sortDescriptorWithKey:@"recordingPatientFirstName" ascending:YES];
	NSSortDescriptor *sortDate = [NSSortDescriptor sortDescriptorWithKey:@"recordingDate" ascending:YES];
	[fetchRequest setSortDescriptors:[NSArray arrayWithObjects:sortLastName, sortFirstName, sortDate, nil]];
	[fetchRequest setEntity:entityDesc];
	[AudioController sharedInstance]->fetchedRecordings = nil;
	[AudioController sharedInstance]->fetchedRecordings = [[NSMutableArray alloc] initWithArray:[context executeFetchRequest:fetchRequest error:&error]];
	
	if (error != nil)
		NSLog(@"\nError Fetching Recordings: %@", [error localizedDescription]);
	
	if ([[AudioController sharedInstance]->fetchedRecordings count] != 0)
		success = TRUE;
	
	return success;
}

+(BOOL)loadRecordingAtFetchIndex:(NSInteger)index{
	BOOL success = TRUE;
	
	// Getting Fetched Result
	Recording *fetchedResult = [[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index];
	
	[fetchedResult.recordingData writeToURL:[AudioController sharedInstance]->baseFileURL atomically:YES];
	
	if (fetchedResult.recordingData == nil)
		success = FALSE;
	
	[AudioController sharedInstance]->loadFromData = success;
	return success;
}

+(NSString *)titleForFetchResult: (NSInteger)index{
	
	if ([[AudioController sharedInstance]->fetchedRecordings count] == 0)
		return [NSString stringWithFormat:@"No Records Found"];
	
	Recording *fetchedResult = [[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index];
	NSMutableString *result = [[NSMutableString alloc] initWithString:fetchedResult.recordingPatientLastName];
	[result appendString:@", "];
	[result appendString:fetchedResult.recordingPatientFirstName];
	return result;
}

+(NSString *)dateForFetchResult:(NSInteger)index{
	
	if ([[AudioController sharedInstance]->fetchedRecordings count] == 0)
		return [NSString stringWithFormat:@""];
	
	Recording *fetchedResult = [[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index];
	NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
	[dateFormat setDateStyle:NSDateFormatterMediumStyle];
	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	NSMutableString *result = [[NSMutableString alloc] initWithString:@"Recorded on: "];
	[result appendString:[dateFormat stringFromDate:fetchedResult.recordingDate]];
	return result;
}

+(NSInteger)sizeOfFetchedArray{
	return [[AudioController sharedInstance]->fetchedRecordings count];
}

+(void)deleteRecordingAtFetchIndex:(NSInteger)index{
	[[[AudioController sharedInstance]->myAppDelegate managedObjectContext] deleteObject:[[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index]];
	[[AudioController sharedInstance]->fetchedRecordings removeObjectAtIndex:index];
	NSError *error = nil;
	if ([[AudioController sharedInstance]->myAppDelegate.managedObjectContext hasChanges]) {
		if (![[AudioController sharedInstance]->myAppDelegate.managedObjectContext save:&error])
			NSLog(@"\nSave Failed: %@", [error localizedDescription]);
		else
			NSLog(@"\nSave Succeeded");
	}
}

+(void)emailMP3FileAtIndex:(NSInteger)index{
	
	// Determine Resource
	Recording *fetchedResult = [[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index];
	
	// Determine Date String
	NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
	[dateFormat setDateStyle:NSDateFormatterMediumStyle];
	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	NSArray *dateComponents = [[dateFormat stringFromDate:fetchedResult.recordingDate] componentsSeparatedByString:@" "];
	NSMutableString *dateString = [[NSMutableString alloc] initWithString:[dateComponents objectAtIndex:0]];
	[dateString appendString:@"_"];
	[dateString appendString:[dateComponents lastObject]];
	
    
    // Determine the file name and data
    NSMutableString *fileName = [[NSMutableString alloc] initWithString:fetchedResult.recordingPatientLastName];
	[fileName appendString:@"_"];
	[fileName appendString:fetchedResult.recordingPatientFirstName];
	[fileName appendString:@"_"];
	[fileName appendString:dateString];
    
	// Email
	[self emailMP3FileWithData:fetchedResult.recordingData :fileName];
    
}

+(void)emailMP3FileFromURL :(NSString *)patientFirstName :(NSString *)patientLastName{
	
	// Determine Date String
	NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
	[dateFormat setDateStyle:NSDateFormatterMediumStyle];
	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	NSArray *dateComponents = [[dateFormat stringFromDate:[NSDate date]] componentsSeparatedByString:@" "];
	NSMutableString *dateString = [[NSMutableString alloc] initWithString:[dateComponents objectAtIndex:0]];
	[dateString appendString:@"_"];
	[dateString appendString:[dateComponents lastObject]];
	
	NSMutableString *fileName = [[NSMutableString alloc] initWithString:patientLastName];
	[fileName appendString:@"_"];
	[fileName appendString:patientFirstName];
	[fileName appendString:@"_"];
	[fileName appendString:dateString];
	
	// Email
	[self emailMP3FileWithData:[NSData dataWithContentsOfURL:[AudioController sharedInstance]->baseFileURL] :fileName];
	
}

+(void)emailMP3FileWithData:(NSData *)fileData :(NSString *)fileName{
	MFMailComposeViewController *mc = [[MFMailComposeViewController alloc] init];
    mc.mailComposeDelegate = self;
	
	// MIME type
    NSString *mimeType = @"audio/mpeg3";
    
    // Add attachment
    [mc addAttachmentData:fileData mimeType:mimeType fileName:fileName];
    
    // Present mail view controller on screen
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:mc animated:YES completion:NULL];
	
}



+(void) mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    switch (result)
    {
        case MFMailComposeResultCancelled:
            NSLog(@"Mail cancelled");
            break;
        case MFMailComposeResultSaved:
            NSLog(@"Mail saved");
            break;
        case MFMailComposeResultSent:
            NSLog(@"Mail sent");
            break;
        case MFMailComposeResultFailed:
            NSLog(@"Mail sent failure: %@", [error localizedDescription]);
            break;
        default:
            break;
    }
    
    // Close the Mail Interface
    [[UIApplication sharedApplication].keyWindow.rootViewController dismissViewControllerAnimated:YES completion:NULL];
}
- (void)drawOscilloscope
{
	// Clear the view
	glClear(GL_COLOR_BUFFER_BIT);
	
	glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	
	glColor4f(1., 1., 1., 1.);
	
	glPushMatrix();
	
	glEnable(GL_TEXTURE_2D);
	glEnable(GL_BLEND);
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	
	/*
	 {
	 // Draw our background oscilloscope screen
	 const GLfloat vertices[] = {
	 0., 0.,
	 512., 0.,
	 0.,  512.,
	 512.,  512.,
	 };
	 const GLshort texCoords[] = {
	 0, 0,
	 1, 0,
	 0, 1,
	 1, 1,
	 };
	 
	 
	 glBindTexture(GL_TEXTURE_2D, bgTexture);
	 
	 glVertexPointer(2, GL_FLOAT, 0, vertices);
	 glTexCoordPointer(2, GL_SHORT, 0, texCoords);
	 
	 glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	 }
	 */
	
	GLfloat *oscilLine_ptr;
	GLfloat max = drawBufferLen;
	SInt8 *drawBuffer_ptr;
	
	// Alloc an array for our oscilloscope line vertices
	if (resetOscilLine) {
		oscilLine = (GLfloat*)realloc(oscilLine, drawBufferLen * 2 * sizeof(GLfloat));
		resetOscilLine = NO;
	}
	
	glPushMatrix();
	
	// Translate to the left side and vertical center of the screen, and scale so that the screen coordinates
	// go from 0 to 1 along the X, and -1 to 1 along the Y
	
	float y;
	float x;
	float height;
	float width;
	float theta;
	
	// Customize for Rotation
	
		theta = 0;
		y = view.frame.size.width/2.0;
		x = 0.;
		height = view.frame.size.height/.9;
		width = view.frame.size.width;
	
	glTranslatef(x, y, 0.);
	glRotatef(theta, 0., 0., 1.0);
	glScalef(height, width, 1.);
	
	// Set up some GL state for our oscilloscope lines
	glDisable(GL_TEXTURE_2D);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_COLOR_ARRAY);
	glDisable(GL_LINE_SMOOTH);
	glLineWidth(2.);
	
	int drawBuffer_i;
	// Draw a line for each stored line in our buffer (the lines are stored and fade over time)
	for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
	{
		
		if (!drawBuffers[drawBuffer_i]) continue;
		
		oscilLine_ptr = oscilLine;
		drawBuffer_ptr = drawBuffers[drawBuffer_i];
		
		GLfloat i;
		// Fill our vertex array with points
		for (i=0.; i<max; i=i+1.)
		{
			*oscilLine_ptr++ = i/max;
			*oscilLine_ptr++ = (Float32)(*drawBuffer_ptr++) / 128.;
		}
		
		// If we're drawing the newest line, draw it in solid green. Otherwise, draw it in a faded green.
		if (drawBuffer_i == 0)
			glColor4f(1., 0., 0., 1.);
		else
			glColor4f(1., 0., 0., (.24 * (1. - ((GLfloat)drawBuffer_i / (GLfloat)kNumDrawBuffers))));
		
		// Set up vertex pointer,
		glVertexPointer(2, GL_FLOAT, 0, oscilLine);
		
		// and draw the line.
		glDrawArrays(GL_LINE_STRIP, 0, drawBufferLen);
		
	}
	
	glPopMatrix();
    
	glPopMatrix();

}

- (void)drawView:(id)sender forTime:(NSTimeInterval)time
{
	[self drawOscilloscope];
}

+(void)setView:(EAGLView *)view{
	[[AudioController sharedInstance]setView:view];
}

-(void)setView:(EAGLView *)EAGLViewFrame{
	view = EAGLViewFrame;
	view.delegate = self;
	[view setAnimationInterval:1./20.];
	[view startAnimation];
}



@end

