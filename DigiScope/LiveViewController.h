//
//  LiveViewController.h
//  DigiScope
//
//  Created by Sean Brown on 12/2/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>
#import "UIPopoverOverride.h"
#import "EAGLView.h"

@class DigiScopeAppAppDelegate;

@interface LiveViewController : UIViewController <UIPopoverControllerDelegate, UIPickerViewDelegate>{
	
	IBOutlet UIButton *recordOutlet;
	IBOutlet UIButton *playOutlet;
	IBOutlet UIButton *loadOutlet;
	IBOutlet EAGLView *graphView;
}

@property (readonly, nonatomic) UIPopoverController *SavePopoverController;
@property (readonly, nonatomic) UIViewController *SavePopoverViewController;
@property (readonly, nonatomic) UIPopoverController *LoadPopoverController;
@property (readonly, nonatomic) UIViewController *LoadPopoverViewController;
@property (strong, nonatomic) UIButton *cancelRecording;
@property (strong, nonatomic) UIButton *saveRecording;
@property (strong, nonatomic) UIButton *exportRecording;
@property (strong, nonatomic) UITextField *patientFirstName;
@property (strong, nonatomic) UITextField *patientLastName;
@property (strong, nonatomic) UIButton *cancelLoad;
@property (strong, nonatomic) UIButton *selectRecording;
@property (strong, nonatomic) UIButton *deleteRecording;
@property (strong, nonatomic) UIPickerView *pickerView;
@property (strong, nonatomic) UILabel *dateRecorded;
@property (strong, nonatomic) UILabel *saveSuccessLabel;


- (IBAction)loadAction:(id)sender;
- (IBAction)recordAction:(id)sender;
- (IBAction)playAction:(id)sender;
-(void)resetPlayButton;
-(void)cancelRecordingAction;
-(void)saveRecordingAction;
-(void)exportRecordingAction;
-(void)cancelLoadAction;
-(void)selectRecordingAction;
-(void)deleteRecordingAction;
-(void)resetSaveBanner;



@end
