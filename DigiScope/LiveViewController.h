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
#import "AudioController.h"

enum kTrayConfiguration{
	kTrayConfiguration_collapsed,
	kTrayConfiguration_main,
	kTrayConfiguration_open,
	kTrayConfiguration_save
};

@class DigiScopeAppAppDelegate;

@interface LiveViewController : UIViewController <UIPopoverControllerDelegate, UIPickerViewDelegate, AudioControllerDelegate>{
	IBOutlet EAGLView *graphView;
	IBOutlet UIView *trayView;
	IBOutlet UIView *rateView;
}

-(void)saveRecording;
-(void)exportRecording;
-(void)openRecording;
-(void)deleteRecording;
-(void)setTrayConfigurationTo: (kTrayConfiguration)config;


@end
