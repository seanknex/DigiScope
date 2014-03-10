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

#define kNumDrawBuffers 1
#define kNumECGDrawBuffers 1
#define kDefaultDrawSamples 1024
#define kMinDrawSamples 64
#define kMaxDrawSamples 4096
#define kSizeOfHeartRateBuffer 5

SInt8 *drawBuffers[kNumDrawBuffers];
SInt8 *ECGBuffer;
int drawBufferIdx = 0;
int ECGDrawBufferIdx = 0;
int drawBufferLen = kDefaultDrawSamples;
int ECGBufferLen = 4096;
int drawBufferLen_alloced = 0;
int ECGBuferLen_alloced = 0;

Float32 *inputSaveBuffer;
int inputSaveOffset = 0;
Float32 *postFilterBuffer;
int postFilterOffset = 0;

Float32 preferenceConstants[10] = {
	0., // Red Line Color
	1., // Green Line Color
	1., // Blue Line Color
	1., // Alpha Line Color
	0., // Red Background Color
	0., // Green Background Color
	0., // Blue Background Color
	1., // Alpha Background Color
	1., // Scale
	0}; // Translation

Float32 *ioDataPtr;
Float32 *inputBuffer;
Float32 *BPBuffer; // Bandpass buffer
Float64 *LPBuffer; // Lowpass buffer

BOOL isRecording = FALSE;
AudioFileID tempAudioFile;
UInt64 byteOffset = 0;
UInt64 fileByteSize = 0;
BOOL isPlaying = FALSE;
BOOL recordingAwaitingSave = FALSE;
Float32 cutoffAmp = 0.5;
Float32 max = 0;
double startingFrameCount;
UIDeviceOrientation currentOrientation = UIDeviceOrientationPortrait;

// Heart Rate Variables
BOOL heartRateBufferBeingModified = FALSE;
Float32 *heartRateBuffer;
int sizeOfHeartBuffer = 0;
NSDate *dateLastUpdated;
NSTimer *refreshTimer;



# pragma mark Filter Definitions

// Coefficents B and A for Butterworth Filter (4th order max, band pass, low pass)
// FilterCoefficients[kAudioOptimizedFor_][Sampling_Rate(8000,44100)][Coefficents(gain,BP:B&A,LP:B&A)][Coefficient Values]
Float64 FilterCoefficients[1][2][5][5] =
{
	// kAudioOptimizationOptions_Heart
	{
		// 8000 Hz Sampling Rate
		{
			{2000., 0., 0., 0., 0.}, // Filter Gain
			{ 0.010432413371167, 0.0,  -0.020864826742333, 0.0, 0.010432413371167}, // Bandpass B
			{1.00,  -3.684140456333678,   5.102011663126655,  -3.150585424636544, 0.7327260303718160}, // Bandpass A
			{0.00000066171528800840, 0.00000264686115203361, 0.00000397029172805041, 0.00000264686115203361, 0.00000066171528800840}, // Lowpass B
			{1.,  -3.848136880041180, 5.555835685441924, -3.566763664734585, 0.859075446778450} // Lowpass A
		},
		
		// 44100 Hz Sampling Rate
		{
			{100000., 0., 0., 0., 0.}, // Filter Gain
			{0.010432413371167, 0.0,  -0.020864826742333, 0.0, 0.010432413371167}, // Bandpass B
			{1.00,  -3.684140456333678,   5.102011663126655,  -3.150585424636544, 0.7327260303718160}, // Bandpass A
			{0.00000000076173778396083,   0.00000000304695113584330,   0.00000000457042670376495,   0.00000000304695113584330,   0.00000000076173778396083}, // Lowpass B
			{1.,  -3.972449317496953,   5.917726838292429,  -3.918102679009986, 0.972825170402315} // Lowpass A
		}
	}
};

enum kAudioOptimizationOptions{
	kAudioOptimizationOptions_Heart,
	//kAudioOptimizationOptions_HeartMurmur,
	//kAudioOptimizationOptions_Lungs,
};

enum kAudioOptimizationSampleRate{
	kAudioOptimizationSampleRate_8000Hz,
	kAudioOptimizationSampleRate_44100Hz,
};

enum kFilterCoefficients{
	kAmp,
	kB_Band,
	kA_Band,
	kB_Low,
	kA_Low
};

BOOL filterNeedsUpdateFlag = TRUE;
kAudioOptimizationSampleRate filterRate;
kAudioOptimizationOptions filterOption = kAudioOptimizationOptions_Heart;

Float32 freq = 125.;
OSStatus err;

double maxECGValue;
BOOL inECGMode = FALSE;
BOOL ECGRecordingRequest = FALSE;

@implementation AudioController
@synthesize myAppDelegate, fetchedRecordings, loadFromData, viewDelegate, digiscopeHardwareAttached, view, ControllerDelegate, notificationCenterAvailable;

#pragma mark CheckError
static void CheckError(OSStatus error, const char *operation){
	if (error == noErr)
		return;
	
	char errorString[20];
	// See if it appears to be a 4-char-code
	*(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
	if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
		errorString[0] = errorString[5] = '\'';
		errorString[6] = '\0';
	}
	else
		sprintf(errorString, "%d",(int)error);
	
	fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
	exit(1);
}



#pragma mark Shared Instance

+(AudioController *)sharedInstance{
	static AudioController *myInstance = nil;
	
	if (nil==myInstance) {
		myInstance = [[[self class] alloc] init];
		[myInstance setUpAudioSession];
		[myInstance initializeAudioUnit];
		// Register for Notifications
		[[NSNotificationCenter defaultCenter] addObserver:myInstance selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
	}
	return myInstance;
}

void cycleOscilloscopeLines()
{
	// Cycle the lines in our draw buffer so that they age and fade. The oldest line is discarded.
	int drawBuffer_i;
	for (drawBuffer_i=(kNumDrawBuffers - 2); drawBuffer_i>=0; drawBuffer_i--) // 3
			memmove(drawBuffers[drawBuffer_i + 1], drawBuffers[drawBuffer_i], drawBufferLen);
}

#pragma mark IOUnit_RenderCallBack

// Render Call Back
static OSStatus renderInput(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
	//NSLog(@"Start\n");
	AudioController *THIS = (__bridge AudioController *)inRefCon;
	
	err = AudioUnitRender(THIS->ioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
	
	ioDataPtr = (Float32*)ioData->mBuffers[0].mData;
	
	static BOOL tempBuffersCreated = FALSE;
	if (!tempBuffersCreated) {
		sizeOfHeartBuffer = inNumberFrames*kSizeOfHeartRateBuffer;
		inputBuffer = (Float32*)malloc((inNumberFrames+4)*sizeof(Float32));
		BPBuffer = (Float32*)malloc((inNumberFrames+4)*sizeof(Float32));
		heartRateBuffer = (Float32*)malloc((sizeOfHeartBuffer)*sizeof(Float32));
		memset(inputBuffer, 0, (inNumberFrames+4)*sizeof(Float32));
		memset(BPBuffer, 0, (inNumberFrames+4)*sizeof(Float32));
		memset(heartRateBuffer, 0, (sizeOfHeartBuffer)*sizeof(Float32));
		inputSaveBuffer = (Float32*)malloc(40000*sizeof(Float32));
		postFilterBuffer = (Float32*)malloc(40000*sizeof(Float32));
		tempBuffersCreated = TRUE;
	}
	
	if (inputSaveOffset+inNumberFrames < 40000 && isRecording) {
		memcpy(&inputSaveBuffer[inputSaveOffset], ioDataPtr, inNumberFrames*sizeof(Float32));
		inputSaveOffset+=inNumberFrames;
	}
	
	// Zero the Audio if Digiscope Hardware is not found
	if (!THIS.digiscopeHardwareAttached)
		memset(ioDataPtr, 0, ioData->mBuffers[0].mDataByteSize);
	
	if (inECGMode) {
		for (int i = 4; i<inNumberFrames+4; i++)
			ioDataPtr[i] = 5.000*ioDataPtr[i]; // Pre Amplify
	}
	else{
		memcpy(&inputBuffer[4], ioDataPtr, ioData->mBuffers[0].mDataByteSize);
		memset(ioDataPtr, 0, ioData->mBuffers[0].mDataByteSize);
		Float32 *ioDataPtr2 = (Float32*)ioData->mBuffers[1].mData;
		memset(ioDataPtr2, 0, ioData->mBuffers[1].mDataByteSize);
		
		/////////////////////////////////// Audio /////////////////////////////////////////////////////
		
		//The best yet ....
		for (int i = 4; i<inNumberFrames+4; i++)
			inputBuffer[i] = 160.000*inputBuffer[i]; // Pre Amplify
		
		
		for (int i = 4; i<inNumberFrames+4; i++) {
			BPBuffer[i] = FilterCoefficients[filterOption][filterRate][kB_Band][0] * inputBuffer[i]
			+FilterCoefficients[filterOption][filterRate][kB_Band][1] * inputBuffer[i-1]
			+FilterCoefficients[filterOption][filterRate][kB_Band][2] * inputBuffer[i-2]
			+FilterCoefficients[filterOption][filterRate][kB_Band][3] * inputBuffer[i-3]
			+FilterCoefficients[filterOption][filterRate][kB_Band][4] * inputBuffer[i-4]
			-FilterCoefficients[filterOption][filterRate][kA_Band][1] * BPBuffer[i-1]
			-FilterCoefficients[filterOption][filterRate][kA_Band][2] * BPBuffer[i-2]
			-FilterCoefficients[filterOption][filterRate][kA_Band][3] * BPBuffer[i-3]
			-FilterCoefficients[filterOption][filterRate][kA_Band][4] * BPBuffer[i-4];
		}
		
		if (postFilterOffset+inNumberFrames < 40000 && isRecording) {
			memcpy(&postFilterBuffer[postFilterOffset], BPBuffer, inNumberFrames*sizeof(Float32));
			postFilterOffset+=inNumberFrames;
		}
		
		memcpy(ioDataPtr, BPBuffer, ioData->mBuffers[0].mDataByteSize);
		memcpy(&(BPBuffer)[0], &(BPBuffer)[inNumberFrames], 4*sizeof(Float32));
		memcpy(&(inputBuffer)[0], &(inputBuffer)[inNumberFrames], 4*sizeof(Float32));
		
		
		// Amplify Output
		/*
		static int calcAmpConst = 1;
		static Float32 ampInitial = 0;
		static Float32 ampFinal = 0.5;
		static Float32 amplification = 0;
		for (int i = 0; i<inNumberFrames; i++){
			if (fabsf(ioDataPtr[i])>max)
				max = fabsf(ioDataPtr[i]);
		}
		
		if (calcAmpConst <= 0) {
			ampInitial = ampFinal;
			//if (max < 0.4 || max > 3.0)
				//ampFinal = 0;
			//else
				ampFinal = 0.5;
			max = 0;
			calcAmpConst = 4;
		}
		else
			calcAmpConst--;
		
		amplification = ampFinal - (ampFinal - ampInitial)*exp2f(-2+0.5*calcAmpConst);
		
		for (int i = 0; i<inNumberFrames; i++)
			ioDataPtr[i] = ioDataPtr2[i] = amplification * ioDataPtr[i];
		*/
		
		// Set aside data for recording
		if (isRecording) {
			CheckError(AudioFileWriteBytes(tempAudioFile, FALSE, byteOffset, &ioData->mBuffers[0].mDataByteSize, ioDataPtr),"Failed to Write Bytes");
			byteOffset += (SInt64)ioData->mBuffers[0].mDataByteSize;
		}
		else if (isPlaying){
			UInt32 numOfBytesToRead = ioData->mBuffers[0].mDataByteSize;
			if (byteOffset+numOfBytesToRead < fileByteSize){
				CheckError(AudioFileReadBytes(tempAudioFile, FALSE, byteOffset, &numOfBytesToRead, ioDataPtr), "Failed to Read Bytes");
				byteOffset += numOfBytesToRead;
				memcpy(ioDataPtr2, ioDataPtr, numOfBytesToRead);
			}
			else
				isPlaying = FALSE;
		}
		
		
		/////////////////////////////////// End Audio /////////////////////////////////////////////////////
	}
	
	// Fill Heart Rate Buffer
	while (heartRateBufferBeingModified){} // Pause until it is no longer modified
	heartRateBufferBeingModified = TRUE;
	memcpy(heartRateBuffer, &heartRateBuffer[inNumberFrames], inNumberFrames*(kSizeOfHeartRateBuffer-1)*sizeof(Float32));
	memcpy(&heartRateBuffer[(kSizeOfHeartRateBuffer-1)*inNumberFrames], ioDataPtr, inNumberFrames*sizeof(Float32));
	heartRateBufferBeingModified = FALSE;
	
	{
		// The draw buffer is used to hold a copy of the most recent PCM data to be drawn
		if (drawBufferLen != drawBufferLen_alloced)
		{
			int drawBuffer_i;
			// Allocate our draw buffer if needed
			if (drawBufferLen_alloced == 0)
				for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++) // 1
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
			// Allocate our draw buffer if needed
			if (ECGBuferLen_alloced == 0)
				ECGBuffer = NULL;
			
			ECGBuffer = (SInt8 *)realloc(ECGBuffer, ECGBufferLen);
			bzero(ECGBuffer, ECGBufferLen);
			
			ECGBuferLen_alloced = ECGBufferLen;
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
		maxECGValue = 0;
		
		for (i=1; i<inNumberFrames; i++)
		{
			if (!inECGMode) {
				if ((i+drawBufferIdx) >= drawBufferLen)
				{
					cycleOscilloscopeLines();
					drawBufferIdx = -i;
				}
				
				drawBuffers[0][i + drawBufferIdx] = data_ptr[2]; // 2
				ECGDrawBufferIdx = 0;
			}
			
			else{
				if (fabs(maxECGValue)<fabs(data_ptr[2]))
					maxECGValue = data_ptr[2];
				
				drawBufferIdx = 0;
				
				if ((i+1)%8 == 0) {
					ECGBuffer[ECGDrawBufferIdx] = maxECGValue;
					ECGDrawBufferIdx++;
					maxECGValue = 0;
				}
				
				// Readjust ECGDrawBufferIdx if needed
				if (ECGDrawBufferIdx >= ECGBufferLen)
					ECGDrawBufferIdx = 0;
			}
			 
			data_ptr += 4;
		}
		
		drawBufferIdx += inNumberFrames;

	}
	
	//NSLog(@"Stop\n");
	return err;
	
}

#pragma mark Touch Funchtions
- (void)handleGesture:(UIGestureRecognizer *)gestureRecognizer{
	if ([gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
		UIPinchGestureRecognizer *pinchRecognizer = (UIPinchGestureRecognizer*)gestureRecognizer;
		preferenceConstants[kAudioControllerPreferences_Scale] = pinchRecognizer.scale;
		if (preferenceConstants[kAudioControllerPreferences_Scale]<1.)
			preferenceConstants[kAudioControllerPreferences_Scale] = 1;
	}
	else if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]){
		UIPanGestureRecognizer *panRecognizer = (UIPanGestureRecognizer*)gestureRecognizer;
		preferenceConstants[kAudioControllerPreferences_Translation] = [panRecognizer translationInView:view].x;
	}
	else if ([gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]]){
		UISwipeGestureRecognizer *swipeRecognizer = (UISwipeGestureRecognizer*)gestureRecognizer;
		if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_SwipeOccurance withObject:swipeRecognizer];}
	}
}

-(BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer{
	return YES;
}

#pragma mark AudioSession/RIOUnit Methods

-(void)initializeAudioUnit{

	loadFromData = FALSE;
	
	// Describe audio component
	AudioComponentDescription desc = {0};
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	// Get component
	AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
	
	// Get audio unit
	CheckError(AudioComponentInstanceNew(inputComponent, &ioUnit), "Error in AudioComponentInstanceNew");
	
	// Enable IO for recording
	UInt32 flag = 1;
	CheckError(AudioUnitSetProperty(ioUnit,
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Input,
								  kInputBus,
								  &flag,
								  sizeof(flag)),"Could Not Enable IO");
	
	
	// Connecting the ioUnit input to the ioUnit output: Audio Streaming
	AudioUnitConnection AUConnection;
	AUConnection.sourceAudioUnit = ioUnit;
	AUConnection.destInputNumber = 1;
	AUConnection.sourceOutputNumber = 0;
	
	CheckError(AudioUnitSetProperty(ioUnit,
								  kAudioUnitProperty_MakeConnection,
								  kAudioUnitScope_Input,
								  1,
								  &AUConnection, sizeof(AUConnection)),"Could Not Connect Input to Output");
	
	// Syncronize Formats
	AudioStreamBasicDescription inputFormat = {0};
	UInt32 propertySize = sizeof(inputFormat);
	CheckError(AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &inputFormat, &propertySize), "Error AudioUnitGetProperty");
	CheckError(AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &inputFormat, propertySize), "Error AudioUnitSetProperty");
	
	// Set Filter Sample Rate
	switch ((int)inputFormat.mSampleRate) {
		case 8000:
			filterRate = kAudioOptimizationSampleRate_8000Hz;
			break;
		case 44100:
			filterRate = kAudioOptimizationSampleRate_44100Hz;
			break;
		default:
			filterRate = kAudioOptimizationSampleRate_8000Hz;
			break;
	}
	
	
	// Configure and Set the Render Callback function (needed to render the audio)
	AURenderCallbackStruct	inputProc;
	inputProc.inputProc = renderInput;
	inputProc.inputProcRefCon = (__bridge void *)(self);
	CheckError(AudioUnitSetProperty(ioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &inputProc, sizeof(inputProc)),"Error in Setting Render Callback");
	
	// Initialize the Unit and confirm that all connections are correct
	CheckError(AudioUnitInitialize(ioUnit),"Error AudioUnitInitialize");
	
	
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
	ECGoscilLine = (GLfloat*)malloc(ECGBufferLen * 2 * sizeof(GLfloat));
	
	thruFormat = CAStreamBasicDescription(8000, kAudioFormatLinearPCM, 4, 1, 4, 2, 32, kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved);
	drawFormat.SetAUCanonical(2, false);
	drawFormat.mSampleRate = 8000;
	AudioConverterNew(&thruFormat, &drawFormat, &audioConverter);
	
}



+(BOOL)startAudioUnit{
	// Start the AUGraph
	CheckError(AudioOutputUnitStart([AudioController sharedInstance]->ioUnit),"Error AudioOutputUnitStart");
	
	// Start the Heart Rate Monitor
	refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:[AudioController class] selector:@selector(refreshHeartRate) userInfo:nil repeats:YES];
	return TRUE;
}

+(void)stopAudioUnit{
	CheckError(AudioOutputUnitStop([AudioController sharedInstance]->ioUnit),"Error AudioOutputUnitStop");
	[refreshTimer invalidate];
	refreshTimer = nil;
}

-(void)setUpAudioSession{
	
	digiscopeHardwareAttached = FALSE;
	
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
	[AudioSession setPreferredSampleRate:8000 error:&error];
	if (error != nil)
		NSLog(@"\nError in Setting the Preferred Sample Rate: %@", [error localizedDescription]);
	
	[AudioSession setPreferredIOBufferDuration:0.1 error:&error];
	if (error) NSLog(@"Error in Setting Buffer Duration");
	error = nil;
	
	// Set Active
	[AudioSession setActive:YES error:&error];
	
	if (error != nil)
		NSLog(@"\nError in Setting the Audio Session Active: %@", [error localizedDescription]);
	
	// Set Input Settings
	for (AVAudioSessionPortDescription *mDes in AudioSession.availableInputs) {
		if ([mDes.portName isEqualToString:@"Digiscope"]|| [mDes.portName isEqualToString:@"DigiScopeTestBoard"]|| [mDes.portName isEqualToString:@"DigiScope"]){
			[AudioSession setPreferredInput:mDes error:&error];
			digiscopeHardwareAttached = TRUE;
		}
		if (error != nil)
			NSLog(@"\nError Setting Input: %@", [error localizedDescription]);
	}
	
	// Reset Category if the hardware was not found
	if (!digiscopeHardwareAttached) {
		[AudioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
		if (error != nil)
			NSLog(@"\nError in Setting the Audio Session Category: %@", [error localizedDescription]);
		
		// Set Sample Rate
		if (error != nil)
			NSLog(@"\nError in Setting the Preferred Sample Rate: %@", [error localizedDescription]);
		
	}
	
	

	
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
	/*
	if (inECGMode) {
		ECGRecordingRequest = TRUE;
		if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_ECGSaveInProgress];}
	}
	else{
	 */
		if (!isRecording) {
			AudioStreamBasicDescription recordFormat = {0};
			recordFormat.mSampleRate = 8000;
			recordFormat.mFormatID = kAudioFormatLinearPCM;
			recordFormat.mBitsPerChannel = 32;
			recordFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
			recordFormat.mFramesPerPacket = 1;
			recordFormat.mChannelsPerFrame = 1;
			recordFormat.mBytesPerFrame = 4;
			recordFormat.mBytesPerPacket = 4;
			
			NSURL *documentDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
			NSURL *myNSURL = [NSURL fileURLWithPath:[documentDirectory.path stringByAppendingString:@"/TempFile.wav"]];
			CFURLRef myFileUrl = (__bridge CFURLRef)myNSURL;
			CheckError(AudioFileCreateWithURL(myFileUrl, kAudioFileWAVEType, &recordFormat, kAudioFileFlags_EraseFile, &tempAudioFile),"Could not create a tempAudioFile for saving");
			printf("\nRecording");
			byteOffset = 0;
			isRecording = TRUE;
			if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_AudioSaveInProgress withObject:nil];}
			
		}
		else printf("\nError: Recorder is already running");
		
	//}
	
}

+(void)stopRecording{
	/*
	if (inECGMode) {
		if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_ECGSaveComplete];}
	}
	else{
	 */
		if (isRecording) {
			isRecording = FALSE;
			printf("\nStopped");
			AudioFileClose(tempAudioFile);
			recordingAwaitingSave = TRUE;
			if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_AudioSaveComplete withObject:nil];}
			
			for (int i = 0; i<40000; i++)
				printf("\n%.9f",inputSaveBuffer[i]);
			postFilterOffset = 0;
			
			for (int i = 0; i<40000; i++)
				printf("\n%.9f",postFilterBuffer[i]);
			inputSaveOffset = 0;
		}
		else{
			printf("\nError: Not Currently Recording");
		}
	//}
	
	
}

+(BOOL)isRecording{
	return isRecording;
}

+(void)exportRecording{
	
}

#pragma mark Player Methods

+(void)startPlaying{
	float duration = 0;
	if (!isPlaying){
		
		// Open TempFile
		NSURL *documentDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
		NSURL *myNSURL = [NSURL fileURLWithPath:[documentDirectory.path stringByAppendingString:@"/TempFile.caf"]];
		CFURLRef myFileUrl = (__bridge CFURLRef)myNSURL;
		CheckError(AudioFileOpenURL(myFileUrl, kAudioFileReadPermission, 0, &tempAudioFile), "Could Not Open TempFile.wav");
		AudioStreamBasicDescription fileFormat = {0};
		UInt32 propSize = sizeof(fileFormat);
		CheckError(AudioFileGetProperty(tempAudioFile, kAudioFilePropertyDataFormat, &propSize, &fileFormat), "Could not get file format");
		
		// Check which hardware is available
		if ([[AVAudioSession sharedInstance] sampleRate] != fileFormat.mSampleRate) {
			
			// Convert TempFile into the right sample rate
			UInt64 numOfBytes;
			propSize = sizeof(numOfBytes);
			CheckError(AudioFileGetProperty(tempAudioFile, kAudioFilePropertyAudioDataByteCount, &propSize, &numOfBytes), "Couldn't get the total number of bytes");
			
			UInt32 numOfBytes32 = (UInt32)numOfBytes;
			UInt32 numOfFrames = (UInt32)numOfBytes/sizeof(Float32);
			Float32 *audioBuffer = (Float32*)malloc(numOfBytes32);
			CheckError(AudioFileReadBytes(tempAudioFile, FALSE, 0, &numOfBytes32, audioBuffer), "Could not read bytes from temp file");
			
			numOfFrames = (UInt32)floor(numOfFrames*[[AVAudioSession sharedInstance] sampleRate]/fileFormat.mSampleRate);
			Float32 *adjAudioBuffer = (Float32*)malloc(numOfFrames*sizeof(Float32));
			int x1 = 0;
			int x2 = 0;
			float x = 0;
			float delta = fileFormat.mSampleRate/[[AVAudioSession sharedInstance] sampleRate]
			;
			for (int i = 0; i<numOfFrames; i++) {
				x2 += (x>x2);
				x1 = x2-1;
				adjAudioBuffer[i] = (audioBuffer[x2]-audioBuffer[x1])/(x2-x1)*(x-x1)+audioBuffer[x1];
				x+=delta;
			}
			
			// Close current Temp File
			CheckError(AudioFileClose(tempAudioFile), "Could not close open temp file");
			
			// Rewrite Temp File
			fileFormat.mSampleRate = [[AVAudioSession sharedInstance] sampleRate];
			CheckError(AudioFileCreateWithURL(myFileUrl, kAudioFileCAFType, &fileFormat, kAudioFileFlags_EraseFile, &tempAudioFile), "Could not create new temp file");
			
			// Write Bytes to Temp File
			numOfBytes32 = numOfFrames*sizeof(Float32);
			CheckError(AudioFileWriteBytes(tempAudioFile, FALSE, 0, &numOfBytes32, adjAudioBuffer), "Could not write bytes to Temp File");
			
		}
		
		
		propSize = sizeof(fileByteSize);
		CheckError(AudioFileGetProperty(tempAudioFile, kAudioFilePropertyAudioDataByteCount, &propSize, &fileByteSize), "Could not get AudioDataByteCount");
		duration = fileByteSize/fileFormat.mSampleRate/sizeof(Float32);
		byteOffset = 0;
		isPlaying = TRUE;
		if([AudioController sharedInstance]->notificationCenterAvailable){
			[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_AudioPlayingStarted withObject:nil];
			NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[[AudioController sharedInstance]->ControllerDelegate methodSignatureForSelector:@selector(AudioControllerNotificationCenter: withObject:)]];
			kAudioControllerNotification notification = kAudioControllerNotification_AudioPlayingStopped;
			[inv setSelector:@selector(AudioControllerNotificationCenter: withObject:)];
			[inv setTarget:[AudioController sharedInstance]->ControllerDelegate];
			[inv setArgument:&notification atIndex:2];
			[inv performSelector:@selector(invoke) withObject:nil afterDelay:duration];
			
		}
	}
	else
		NSLog(@"Error, Play is currently playing");
}

+(void)stopPlaying{
	if (isPlaying){
		isPlaying = FALSE;
		CheckError(AudioFileClose(tempAudioFile), "Could not close TempFile.wav");
		[self startAudioUnit];
		if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_AudioPlayingStarted withObject:nil];}
	}
	else
		NSLog(@"Error, Player is not currently playing");
}

+(BOOL)isPlaying{
	return isPlaying;
}

+(BOOL)saveRecording:(NSString *)patientFirstName :(NSString *)patientLastName{
	Recording *recording = [NSEntityDescription insertNewObjectForEntityForName:@"Recording" inManagedObjectContext:[AudioController sharedInstance]->myAppDelegate.managedObjectContext];
	recording.recordingPatientFirstName = patientFirstName;
	recording.recordingPatientLastName = patientLastName;
	recording.recordingDate = [NSDate date];
	recording.recordingIsECG = [NSNumber numberWithBool:inECGMode];
	
	// Determine Date String
	NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
	[dateFormat setDateStyle:NSDateFormatterMediumStyle];
	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	NSArray *dateComponents = [[dateFormat stringFromDate:recording.recordingDate] componentsSeparatedByString:@" "];
	NSMutableString *dateString = [[NSMutableString alloc] initWithString:[dateComponents objectAtIndex:0]];
	[dateString appendString:@"_"];
	[dateString appendString:[dateComponents lastObject]];
	
    
    // Determine the file name and data
	NSMutableString *fileName = [[NSMutableString alloc] init];
	if (![patientLastName isEqualToString:@""]) {
		[fileName appendString:patientLastName];
		[fileName appendString:@"_"];
	}
	if (![patientFirstName isEqualToString:@""]) {
		[fileName appendString:patientFirstName];
		[fileName appendString:@"_"];
	}
	[fileName appendString:dateString];
	
	// Open Temp File
	NSURL *documentDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
	NSURL *myNSURL = [NSURL fileURLWithPath:[documentDirectory.path stringByAppendingString:@"/TempFile.caf"]];
	CFURLRef myFileUrl = (__bridge CFURLRef)myNSURL;
	CheckError(AudioFileOpenURL(myFileUrl, kAudioFileReadPermission, 0, &tempAudioFile), "Could Not Open UserFile.caf");
	
	// Get File Format
	AudioStreamBasicDescription fileFormat = {0};
	UInt32 propSize = sizeof(fileFormat);
	CheckError(AudioFileGetProperty(tempAudioFile, kAudioFilePropertyDataFormat, &propSize, &fileFormat), "Could not get file Format");
	
	// Create User Audio File By Copying Over Data from Temp File
	myNSURL = [NSURL fileURLWithPath:[documentDirectory.path stringByAppendingString:[NSString stringWithFormat:@"/%s.caf",[fileName UTF8String]]]];
	myFileUrl = (__bridge CFURLRef)myNSURL;
	AudioFileID UserFile;
	CheckError(AudioFileCreateWithURL(myFileUrl, kAudioFileCAFType, &fileFormat, kAudioFileFlags_EraseFile, &UserFile), "Could not open up a User Specific File");
	
	// Copy URL string
	recording.recordingPath = [myNSURL path];
			 
	// Get Total Bytes and Copy
	UInt64 numOfBytes;
	propSize = sizeof(numOfBytes);
	CheckError(AudioFileGetProperty(tempAudioFile, kAudioFilePropertyAudioDataByteCount, &propSize, &numOfBytes), "Could not get the total number of bytes from Temp File");
	void *audioBuffer = malloc((UInt32)numOfBytes);
	UInt32 numOfBytes32 = (UInt32)numOfBytes;
	CheckError(AudioFileReadBytes(tempAudioFile, FALSE, 0, &numOfBytes32, audioBuffer),"Could not read the bytes from Temp File");
	CheckError(AudioFileWriteBytes(UserFile, FALSE, 0, &numOfBytes32, audioBuffer), "Could not write the bytes to the User File");
	free(audioBuffer);
	CheckError(AudioFileClose(tempAudioFile), "Couldn't close the Temp File");
	CheckError(AudioFileClose(UserFile), "Couldn't close the User File");
	
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
	
	recordingAwaitingSave = FALSE;
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
	
	// Create User Audio File By Copying Over Data from TempAudioFile
	NSURL *documentDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
	NSURL *myNSURL = [NSURL fileURLWithPath:fetchedResult.recordingPath];
	CFURLRef myFileUrl = (__bridge CFURLRef)myNSURL;
	AudioFileID UserFile;
	CheckError(AudioFileOpenURL(myFileUrl, kAudioFileReadPermission, 0, &UserFile), "Could not load User File");
	
	// Get File Format
	AudioStreamBasicDescription fileFormat = {0};
	UInt32 propSize = sizeof(fileFormat);
	CheckError(AudioFileGetProperty(UserFile, kAudioFilePropertyDataFormat, &propSize, &fileFormat), "Could not get file Format");
	
	// Open Temp File
	myNSURL = [NSURL fileURLWithPath:[documentDirectory.path stringByAppendingString:@"/TempFile.caf"]];
	myFileUrl = (__bridge CFURLRef)myNSURL;
	CheckError(AudioFileCreateWithURL(myFileUrl, kAudioFileCAFType, &fileFormat, kAudioFileFlags_EraseFile, &tempAudioFile), "Could not open Temp File for loading"
			   );
	
	// Get Total Bytes and Copy
	UInt64 numOfBytes;
	UInt32 numOfBytes32;
	propSize = sizeof(numOfBytes);
	CheckError(AudioFileGetProperty(UserFile, kAudioFilePropertyAudioDataByteCount, &propSize, &numOfBytes), "Could not get the total number of bytes from Temp File");
	numOfBytes32 = (UInt32)numOfBytes;
	void *audioBuffer = malloc(numOfBytes32);
	CheckError(AudioFileReadBytes(UserFile, FALSE, 0, &numOfBytes32, audioBuffer),"Could not read the bytes from Temp File");
	CheckError(AudioFileWriteBytes(tempAudioFile, FALSE, 0, &numOfBytes32, audioBuffer), "Could not write the bytes to the User File");
	free(audioBuffer);
	CheckError(AudioFileClose(UserFile), "Couldn't close the User File");
	
	if (numOfBytes == 0)
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
	[dateFormat setDateFormat:@"MMM dd"];
	NSString *result = [[NSString alloc] initWithString:[dateFormat stringFromDate:fetchedResult.recordingDate]];
	return result;
}

+(NSInteger)sizeOfFetchedArray{
	return [[AudioController sharedInstance]->fetchedRecordings count];
}

+(void)deleteRecordingAtFetchIndex:(NSInteger)index{
	NSError *error;
	Recording *deletedRecording = [[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index];
	[[NSFileManager defaultManager] removeItemAtPath:deletedRecording.recordingPath error:&error];
	if (error != nil) printf("Could not removeItemAtPath from NSFileMananger");
	[[[AudioController sharedInstance]->myAppDelegate managedObjectContext] deleteObject:deletedRecording];
	deletedRecording = nil;
	[[AudioController sharedInstance]->fetchedRecordings removeObjectAtIndex:index];
	if ([[AudioController sharedInstance]->myAppDelegate.managedObjectContext hasChanges]) {
		if (![[AudioController sharedInstance]->myAppDelegate.managedObjectContext save:&error])
			NSLog(@"\nSave Failed: %@", [error localizedDescription]);
		else
			NSLog(@"\nSave Succeeded");
	}
}

+(void)emailFileAtIndex:(NSInteger)index{
	
	// Determine Resource
	Recording *fetchedResult = [[AudioController sharedInstance]->fetchedRecordings objectAtIndex:index];
	
	// Create User Audio File By Copying Over Data from TempAudioFile
	NSURL *documentDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
	NSURL *myNSURL = [NSURL fileURLWithPath:fetchedResult.recordingPath];
	CFURLRef myFileUrl = (__bridge CFURLRef)myNSURL;
	AudioFileID UserFile;
	CheckError(AudioFileOpenURL(myFileUrl, kAudioFileReadPermission, 0, &UserFile), "Could not load User File");
	
	// Get Recording Format
	AudioStreamBasicDescription userASBD = {0};
	UInt32 propSize = sizeof(userASBD);
	CheckError(AudioFileGetProperty(UserFile, kAudioFilePropertyDataFormat, &propSize, &userASBD), "Could not get UserFile Format");
	
	// Get Total Bytes and Copy
	UInt64 numOfBytes;
	UInt32 numOfBytes32;
	propSize = sizeof(numOfBytes);
	CheckError(AudioFileGetProperty(UserFile, kAudioFilePropertyAudioDataByteCount, &propSize, &numOfBytes), "Could not get the total number of bytes from Temp File");
	numOfBytes32 = (UInt32)numOfBytes;
	Float32 *audioBuffer = (Float32*)malloc(numOfBytes32);
	CheckError(AudioFileReadBytes(UserFile, FALSE, 0, &numOfBytes32, audioBuffer),"Could not read the bytes from Temp File");
	
	// Set up Email File Format
	AudioStreamBasicDescription emailFormat = {0};
	emailFormat.mSampleRate = 8000;
	emailFormat.mFormatID = kAudioFormatLinearPCM;
	emailFormat.mBitsPerChannel = 32;
	emailFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	emailFormat.mFramesPerPacket = 1;
	emailFormat.mChannelsPerFrame = 1;
	emailFormat.mBytesPerFrame = 4;
	emailFormat.mBytesPerPacket = 4;
	
	// Enhance the amplitude prior to writing
	for (int i=0; i<(int)numOfBytes32/sizeof(Float32); i++)
		audioBuffer[i] = 4.0*audioBuffer[i];
	
	// Open Email File
	AudioFileID emailAudioFile;
	myNSURL = [NSURL fileURLWithPath:[documentDirectory.path stringByAppendingString:@"/Email.wav"]];
	myFileUrl = (__bridge CFURLRef)myNSURL;
	CheckError(AudioFileCreateWithURL(myFileUrl, kAudioFileWAVEType, &emailFormat, kAudioFileFlags_EraseFile, &emailAudioFile), "Could not open Email File ID"
			   );
	CheckError(AudioFileWriteBytes(emailAudioFile, FALSE, 0, &numOfBytes32, audioBuffer), "Could not write the bytes to the User File");
	free(audioBuffer);
	CheckError(AudioFileClose(UserFile), "Couldn't close the User File");
	CheckError(AudioFileClose(emailAudioFile), "Could not close the email File");
	
	// Email
	NSString *fileName = [[NSString alloc] initWithString:[[fetchedResult.recordingPath lastPathComponent] stringByDeletingPathExtension]];
	[self emailFileWithData:[NSData dataWithContentsOfFile:[myNSURL path]] :[NSString stringWithFormat:@"%s.wav",[fileName UTF8String]]];
    
}

+(void)emailFileWithData:(NSData *)fileData :(NSString *)fileName{
	MFMailComposeViewController *mc = [[MFMailComposeViewController alloc] init];
    mc.mailComposeDelegate = self;
	
	// MIME type
    NSString *mimeType = @"audio/x-wav";
    
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
	
	glColor4f(preferenceConstants[kAudioControllerPreferences_BGColor_Red], preferenceConstants[kAudioControllerPreferences_BGColor_Green], preferenceConstants[kAudioControllerPreferences_BGColor_Blue], preferenceConstants[kAudioControllerPreferences_BGColor_Alpha]);
	
	glPushMatrix();
	
	glEnable(GL_TEXTURE_2D);
	glEnable(GL_BLEND);
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	
	GLfloat *oscilLine_ptr;
	GLfloat max = drawBufferLen;
	SInt8 *drawBuffer_ptr;
	
	// Alloc an array for our oscilloscope line vertices
	if (resetOscilLine) {
		oscilLine = (GLfloat*)realloc(oscilLine, drawBufferLen * 2 * sizeof(GLfloat));
		resetOscilLine = NO;
	}
	
	if (resetECGOscilLine) {
		ECGoscilLine = (GLfloat*)realloc(ECGoscilLine, ECGBufferLen * 2 * sizeof(GLfloat));
		resetECGOscilLine = NO;
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
	if (UIDeviceOrientationIsPortrait(currentOrientation)) {
		theta = 0;
		y = view.frame.size.width/2.0;
		x = 0.;
		height = view.frame.size.height/.9;
		width = view.frame.size.width;
	}
	else{
		theta = 0;
		y = view.frame.size.height/2.0;
		x = 0;
		height = view.frame.size.width/.9;
		width = view.frame.size.height;
	}
		
	glTranslatef(x+preferenceConstants[kAudioControllerPreferences_Translation], y, 0.);
	glRotatef(theta, 0., 0., 1.0);
	glScalef(height*preferenceConstants[kAudioControllerPreferences_Scale], width*preferenceConstants[kAudioControllerPreferences_Scale], 1.);
	
	// Set up some GL state for our oscilloscope lines
	glDisable(GL_TEXTURE_2D);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_COLOR_ARRAY);
	glDisable(GL_LINE_SMOOTH);
	glLineWidth(1.5);
	
	int drawBuffer_i;
	// Draw a line for each stored line in our buffer (the lines are stored and fade over time)
	if (inECGMode) {
		
		GLfloat i;
		oscilLine_ptr = ECGoscilLine;
		drawBuffer_ptr = ECGBuffer;
		
		for (i=0; i<ECGBufferLen; i++) {
			*oscilLine_ptr++ = i/ECGBufferLen;
			*oscilLine_ptr++ = (Float32)(*drawBuffer_ptr++)/128.;
		}
		glColor4f(preferenceConstants[kAudioControllerPreferences_LineColor_Red], preferenceConstants[kAudioControllerPreferences_LineColor_Green], preferenceConstants[kAudioControllerPreferences_LineColor_Blue], preferenceConstants[kAudioControllerPreferences_LineColor_Alpha]);
		
		// Set up vertex pointer,
		glVertexPointer(2, GL_FLOAT, 0, ECGoscilLine);
		
		// and draw first line.
		glDrawArrays(GL_LINE_STRIP, 0, ECGDrawBufferIdx-1);
		
		// Readjust Alpha
		glColor4f(preferenceConstants[kAudioControllerPreferences_LineColor_Red], preferenceConstants[kAudioControllerPreferences_LineColor_Green], preferenceConstants[kAudioControllerPreferences_LineColor_Blue], preferenceConstants[kAudioControllerPreferences_LineColor_Alpha]*(.5-.3*ECGDrawBufferIdx/ECGBufferLen));
		
		glDrawArrays(GL_LINE_STRIP, ECGDrawBufferIdx, ECGBufferLen-ECGDrawBufferIdx-1);
		
		// Check for if the user requested a recording and terminate drawing
		if (ECGRecordingRequest && ECGDrawBufferIdx == ECGBufferLen) {
			[[AudioController sharedInstance]->view stopAnimation];
			ECGRecordingRequest = FALSE;
		}
		 
		
	}
	else{
		for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
		{
			
			if (!drawBuffers[drawBuffer_i]) continue; // 4
			
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
				glColor4f(preferenceConstants[kAudioControllerPreferences_LineColor_Red], preferenceConstants[kAudioControllerPreferences_LineColor_Green], preferenceConstants[kAudioControllerPreferences_LineColor_Blue], preferenceConstants[kAudioControllerPreferences_LineColor_Alpha]);
			else
				glColor4f(preferenceConstants[kAudioControllerPreferences_LineColor_Red], preferenceConstants[kAudioControllerPreferences_LineColor_Green], preferenceConstants[kAudioControllerPreferences_LineColor_Blue], preferenceConstants[kAudioControllerPreferences_LineColor_Alpha]*(.24 * (1. - ((GLfloat)drawBuffer_i / (GLfloat)kNumDrawBuffers))));
			
			// Set up vertex pointer,
			glVertexPointer(2, GL_FLOAT, 0, oscilLine);
			
			// and draw the line.
			glDrawArrays(GL_LINE_STRIP, 0, drawBufferLen);
			
		}
	}
	
	
	glPopMatrix();
    
	glPopMatrix();

}

- (void)drawView:(id)sender forTime:(NSTimeInterval)time
{
	[self drawOscilloscope];
}

+(void)setView:(EAGLView *)view{
	[[AudioController sharedInstance] setView:view];
}

-(void)setView:(EAGLView *)EAGLViewFrame{
	view = EAGLViewFrame;
	view.delegate = self;
	viewFrame = EAGLViewFrame.frame;
	
	// Customize Touch Handlers
	[EAGLViewFrame.superview setMultipleTouchEnabled:YES];
	UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
	[pinchRecognizer setDelegate:self];
	[view addGestureRecognizer:pinchRecognizer];
	UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
	[panRecognizer setDelegate:self];
	[view addGestureRecognizer:panRecognizer];
	UISwipeGestureRecognizer *swipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
	[swipeRecognizer setDirection:UISwipeGestureRecognizerDirectionDown];
	[swipeRecognizer setDelegate:self];
	[view addGestureRecognizer:swipeRecognizer];
	swipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
	[swipeRecognizer setDirection:UISwipeGestureRecognizerDirectionUp];
	[swipeRecognizer setDelegate:self];
	[view addGestureRecognizer:swipeRecognizer];
	
	
	[view setAnimationInterval:1./20.];
	[view startAnimation];
	
}

+(void)setDelegate:(id<AudioControllerDelegate>)delegate{
	[[AudioController sharedInstance] setControllerDelegate:delegate];
	[AudioController sharedInstance].notificationCenterAvailable = [delegate respondsToSelector:@selector(AudioControllerNotificationCenter: withObject:)];
}

+(void)switchMode{
	inECGMode = !inECGMode;
	if (!inECGMode) {
		// Erase current ECG data
		for (int i = 0; i<ECGBufferLen; i++) {
			ECGBuffer[i]=0;
		}
	}
	if([AudioController sharedInstance]->notificationCenterAvailable){[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_ModeChange withObject:nil];}
	
}

#pragma mark Notifications
-(void)orientationChanged:(NSNotification *)notification{
	UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
	if (UIDeviceOrientationIsLandscape(deviceOrientation)) {
		[[UIApplication sharedApplication] setStatusBarHidden:YES];
		CGRect frame = CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.height, [[UIScreen mainScreen] bounds].size.width);
		currentOrientation = UIDeviceOrientationLandscapeLeft;
		[view setFrame:frame];
		
	}
	else if (UIDeviceOrientationIsPortrait(deviceOrientation)){
		[[UIApplication sharedApplication] setStatusBarHidden:NO];
		currentOrientation = UIDeviceOrientationPortrait;
		[view setFrame:viewFrame];
	}
}

+(BOOL)isInECGMode{
	return inECGMode;
}

+(BOOL)isReadyToSave{
	return recordingAwaitingSave;
}

+(void)refreshHeartRate{
	
	while (sizeOfHeartBuffer == 0){} // Pause incase the buffer hasn't been created
	Float32 avg = 0;
	Float32 dev = 0;
	static Float32 *tempHeartRateBuffer = (Float32*)malloc(sizeOfHeartBuffer*sizeof(Float32));
	
	// Copy rate to temp buffer
	while (heartRateBufferBeingModified){} // Pause incase the buffer is being modified
	heartRateBufferBeingModified = TRUE;
	memcpy(tempHeartRateBuffer, heartRateBuffer, sizeOfHeartBuffer*sizeof(Float32));
	heartRateBufferBeingModified = FALSE;
	
	// Calculate Average
	for (int i = 0; i<sizeOfHeartBuffer; i++)
		avg += tempHeartRateBuffer[i];
	avg = avg/sizeOfHeartBuffer;
	
	// Calculate Deviation
	for (int i = 0; i<sizeOfHeartBuffer; i++)
		dev += tempHeartRateBuffer[i]-avg;
	dev = sqrt(dev/sizeOfHeartBuffer);
	
	// Calculate the Heart Rate
	int minHeartRateIndex = (int)60/200*[[AVAudioSession sharedInstance] sampleRate];
	int x1 = 0;
	int x2 = 0;
	int heartRate = 74;
	if ([dateLastUpdated timeIntervalSinceNow]>2.0) heartRate = 0;
	if ([AudioController sharedInstance]->notificationCenterAvailable)
		[[AudioController sharedInstance]->ControllerDelegate AudioControllerNotificationCenter:kAudioControllerNotification_RateUpdate withObject:[NSNumber numberWithInt:heartRate]];

}

@end

