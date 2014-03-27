//
//  AudioController.h
//  bluetoothTestApp
//
//  Created by Sean Brown on 11/25/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioFile.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <MessageUI/MessageUI.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import "CAStreamBasicDescription.h"
#import "EAGLView.h"

@class DigiScopeAppAppDelegate;

enum kAudioControllerNotification {
	kAudioControllerNotification_None,
	kAudioControllerNotification_ECGSaveRequest,
	kAudioControllerNotification_ECGSaveInProgress,
	kAudioControllerNotification_ECGSaveComplete,
	kAudioControllerNotification_ECGPlayingStarted,
	kAudioControllerNotification_ECGPlayingStopped,
	kAudioControllerNotification_AudioSaveRequest,
	kAudioControllerNotification_AudioSaveInProgress,
	kAudioControllerNotification_AudioSaveComplete,
	kAudioControllerNotification_AudioPlayingStarted,
	kAudioControllerNotification_AudioPlayingStopped,
	kAudioControllerNotification_ModeChange,
	kAudioControllerNotification_SwipeOccurance,
	kAudioControllerNotification_RateUpdate

};

enum kAudioControllerPreferences {
	kAudioControllerPreferences_LineColor_Red,
	kAudioControllerPreferences_LineColor_Green,
	kAudioControllerPreferences_LineColor_Blue,
	kAudioControllerPreferences_LineColor_Alpha,
	kAudioControllerPreferences_BGColor_Red,
	kAudioControllerPreferences_BGColor_Green,
	kAudioControllerPreferences_BGColor_Blue,
	kAudioControllerPreferences_BGColor_Alpha,
	kAudioControllerPreferences_Scale,
	kAudioControllerPreferences_Translation
};

enum kFilterType{
	kFilterType_Audio,
	kFilterType_ECG
};

enum kFilterCoefficients{
	kGain,
	kB,
	kA
};

@protocol AudioControllerDelegate <NSObject>
@required
@optional
- (void)AudioControllerNotificationCenter: (kAudioControllerNotification)notification withObject:(id)object;
@end

@interface AudioController : NSObject<AVAudioRecorderDelegate, MFMailComposeViewControllerDelegate, EAGLViewDelegate, UIGestureRecognizerDelegate>{
	AudioUnit ioUnit;
	AVAudioRecorder *RecordingController;
	AVAudioPlayer *PlayingController;
	AVAudioSession *AudioSession;
	NSURL *baseFileURL;
	AudioConverterRef audioConverter;
	AudioBufferList*  drawABL;
	BOOL resetOscilLine;
	BOOL resetECGOscilLine;
	GLfloat* oscilLine;
	GLfloat* ECGoscilLine;
	CAStreamBasicDescription	thruFormat;
    CAStreamBasicDescription    drawFormat;
	CGRect viewFrame;
}
@property (strong, nonatomic) DigiScopeAppAppDelegate *myAppDelegate;
@property (strong, nonatomic) NSMutableArray *fetchedRecordings;
@property (strong, nonatomic) id viewDelegate;
@property BOOL digiscopeHardwareAttached;
@property BOOL loadFromData;
@property BOOL notificationCenterAvailable;
@property (nonatomic, retain)	EAGLView* view;
@property (weak) NSObject <AudioControllerDelegate> *ControllerDelegate;

+(AudioController*)sharedInstance;
-(void)initializeAudioUnit;
+(BOOL)startAudioUnit;
+(void)stopAudioUnit;
+(void)initializeRecorder;
+(void)startRecording;
+(void)stopRecording;
+(void)exportRecording;
+(BOOL)isRecording;
+(void)startPlaying;
+(void)stopPlaying;
+(BOOL)isPlaying;
+(BOOL)isInECGMode;
+(BOOL)isReadyToSave;
-(void)setUpAudioSession;
+(void)setAudioSessionActive: (BOOL)setActive;
+(BOOL)saveRecording :(NSString *) patientFirstName :(NSString *)patientLastName;
+(BOOL)loadAllRecordings;
+(BOOL)loadRecordingAtFetchIndex: (NSInteger)index;
+(NSString *)titleForFetchResult: (NSInteger)index;
+(NSString *)dateForFetchResult: (NSInteger)index;
+(NSInteger)sizeOfFetchedArray;
+(void)deleteRecordingAtFetchIndex: (NSInteger)index;
+(void)emailFileAtIndex :(NSInteger)index;
+(void)emailFileWithData :(NSData*)fileData :(NSString*)fileName;
+(void)setView: (EAGLView*)view;
-(void)setView:(EAGLView *)EAGLViewFrame;
+(void)setDelegate: (NSObject<AudioControllerDelegate>*)delegate;
+(void)switchMode;
-(void)orientationChanged:(NSNotification *)notification;

@end
