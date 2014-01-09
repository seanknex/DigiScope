//
//  AudioController.h
//  bluetoothTestApp
//
//  Created by Sean Brown on 11/25/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <MessageUI/MessageUI.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import "CAStreamBasicDescription.h"
#import "EAGLView.h"

@class DigiScopeAppAppDelegate;

@protocol AudioControllerDelegate
@required
- (void)drawView:(id)sender forTime:(NSTimeInterval)time;
@optional
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
@end

@interface AudioController : NSObject<AVAudioRecorderDelegate, MFMailComposeViewControllerDelegate, EAGLViewDelegate>{
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
}
@property (strong, nonatomic) DigiScopeAppAppDelegate *myAppDelegate;
@property (strong, nonatomic) NSMutableArray *fetchedRecordings;
@property (strong, nonatomic) id viewDelegate;
@property BOOL hardwareAttached;
@property BOOL loadFromData;
@property (nonatomic, retain)	EAGLView* view;
@property (nonatomic, retain) UIViewController *requestingController;

+(AudioController*)sharedInstance;
-(void)initializeAudioUnit;
+(BOOL)startAudioUnit;
+(void)stopAudioUnit;
+(void)initializeRecorder;
+(void)startRecordingFromController: (UIViewController*)controller;
+(void)stopRecording;
+(void)exportRecording;
+(BOOL)isRecording;
+(void)initializePlayer;
+(float)startPlaying;
+(void)stopPlaying;
+(BOOL)isPlaying;
-(void)setUpAudioSession;
+(void)setAudioSessionActive: (BOOL)setActive;
+(BOOL)saveRecording :(NSString *) patientFirstName :(NSString *)patientLastName;
+(BOOL)loadAllRecordings;
+(BOOL)loadRecordingAtFetchIndex: (NSInteger)index;
+(NSString *)titleForFetchResult: (NSInteger)index;
+(NSString *)dateForFetchResult: (NSInteger)index;
+(NSInteger)sizeOfFetchedArray;
+(void)deleteRecordingAtFetchIndex: (NSInteger)index;
+(void)emailMP3FileAtIndex :(NSInteger)index;
+(void)emailMP3FileFromURL :(NSString *)patientFirstName :(NSString *)patientLastName;
+(void)emailMP3FileWithData :(NSData*)fileData :(NSString*)fileName;
+(void)setView: (UIView*)view;
-(void)setView:(EAGLView *)EAGLViewFrame;



@end
