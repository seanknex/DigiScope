//
//  LiveViewController.m
//  DigiScope
//
//  Created by Sean Brown on 12/2/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import "LiveViewController.h"
#import "DigiScopeAppAppDelegate.h"
kTrayConfiguration currentTrayConfiguration = kTrayConfiguration_collapsed;
float kKeyBoardOffset = 0;

@implementation LiveViewController

-(void)viewDidAppear:(BOOL)animated{

	// Register for Notifications
	// Register for the events
    [[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector (keyboardDidShow:)
	 name: UIKeyboardDidShowNotification
	 object:nil];
    [[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector (keyboardDidHide:)
	 name: UIKeyboardDidHideNotification
	 object:nil];
	
	// Start Audio Unit
	[AudioController startAudioUnit];
	[AudioController setView:graphView];
	[AudioController setDelegate:self];
	
	// Attach Swipe Recognizers
	UISwipeGestureRecognizer *gesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(SwipeAction:)];
	[gesture setDirection:UISwipeGestureRecognizerDirectionDown];
	[self.view addGestureRecognizer:gesture];
	
	gesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(SwipeAction:)];
	[gesture setDirection:UISwipeGestureRecognizerDirectionUp];
	[self.view addGestureRecognizer:gesture];
	
	// Set Main Menu Tray Config
	[self setTrayConfigurationTo:kTrayConfiguration_collapsed];
	
}

-(void)SwipeAction: (UISwipeGestureRecognizer*)gesture{
	if ([gesture direction] == UISwipeGestureRecognizerDirectionUp)
		currentTrayConfiguration = kTrayConfiguration_collapsed;
	else if ([gesture direction] == UISwipeGestureRecognizerDirectionDown && currentTrayConfiguration ==kTrayConfiguration_collapsed){
		currentTrayConfiguration = kTrayConfiguration_main;
	}
	[self setTrayConfigurationTo:currentTrayConfiguration];
}


-(void)saveRecording{
	if (currentTrayConfiguration == kTrayConfiguration_main)
		[self setTrayConfigurationTo:kTrayConfiguration_save];
	else{
		UITextField *patientFirstName = (UITextField*)[trayView viewWithTag:5];
		UITextField *patientLastName = (UITextField*)[trayView viewWithTag:6];
		if ([[patientFirstName text] isEqualToString:@""])
			[patientFirstName setBackgroundColor:[UIColor redColor]];
		if ([[patientLastName text] isEqualToString:@""])
			[patientLastName setBackgroundColor:[UIColor redColor]];
		if ([patientFirstName isFirstResponder]) [patientFirstName resignFirstResponder];
		if ([patientLastName isFirstResponder]) [patientLastName resignFirstResponder];
		if ([AudioController saveRecording:[patientFirstName text] :[patientLastName text]]) {
			[self setTrayConfigurationTo:kTrayConfiguration_collapsed];
		}
	}
	
}

-(void)exportRecording{
	UIPickerView *pickerView = (UIPickerView*)[trayView viewWithTag:5];
	[AudioController emailFileAtIndex:[pickerView selectedRowInComponent:0]];
	[self setTrayConfigurationTo:kTrayConfiguration_main];
}

-(void)openRecording{
	if (currentTrayConfiguration == kTrayConfiguration_main)
		[self setTrayConfigurationTo:kTrayConfiguration_open];
	else if (currentTrayConfiguration == kTrayConfiguration_open){
		UIPickerView *pickerView = (UIPickerView*)[self.view viewWithTag:5];
		[AudioController loadRecordingAtFetchIndex:[pickerView selectedRowInComponent:0]];
		[self setTrayConfigurationTo:kTrayConfiguration_main];
	}
	
}

-(void)deleteRecording{
	
}

#pragma mark Set Rate
-(void)setRateTo: (int)rate{
	int hundreds = rate/100;
	int tens = (rate-hundreds*100)/10;
	int ones = (rate-hundreds*100-tens*10);
	if (rate >-1) {
		if (rate<100)
			[(UIImageView*)[rateView viewWithTag:100] setImage:[UIImage imageNamed:@"Number_B.png"]];
		else
			[(UIImageView*)[rateView viewWithTag:100] setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Number_%i.png",hundreds]]];
		if (rate<10)
			[(UIImageView*)[rateView viewWithTag:10] setImage:[UIImage imageNamed:@"Number_B.png"]];
		else
			[(UIImageView*)[rateView viewWithTag:10] setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Number_%i.png",tens]]];
		if (rate < 1)
			[(UIImageView*)[rateView viewWithTag:1] setImage:[UIImage imageNamed:@"Number_B.png"]];
		else
			[(UIImageView*)[rateView viewWithTag:1] setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Number_%i.png",ones]]];
	}
	else{
		[(UIImageView*)[rateView viewWithTag:1] setImage:[UIImage imageNamed:@"Number_R.png"]];
		[(UIImageView*)[rateView viewWithTag:10] setImage:[UIImage imageNamed:@"Number_R.png"]];
		[(UIImageView*)[rateView viewWithTag:100] setImage:[UIImage imageNamed:@"Number_E.png"]];
	}
	
}

#pragma mark PickerView Functions
// Number of components.
-(NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView{
	return 1;
}

-(UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view
{
	UIView *masterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pickerView.frame.size.width, 44)];
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, pickerView.frame.size.width*0.7, 44)];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [UIColor blackColor];
	label.font = [UIFont fontWithName:@"AppleSDGothicNeo-SemiBold" size:18];
	label.text = [AudioController titleForFetchResult:row];
	[label setTextAlignment:NSTextAlignmentLeft];
	[masterView addSubview:label];
	
	label = [[UILabel alloc] initWithFrame:CGRectMake(pickerView.frame.size.width*0.7, 0, pickerView.frame.size.width*0.3, 44)];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [UIColor blackColor];
	label.font = [UIFont fontWithName:@"AppleSDGothicNeo-SemiBold" size:18];
	label.text = [AudioController dateForFetchResult:row];
	[label setTextAlignment:NSTextAlignmentRight];
	[masterView addSubview:label];
	
	return masterView;
		
		
	
    
}

// Total rows in our component.
-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component{
	if ([AudioController sizeOfFetchedArray] == 0)
		return 1;
	
	return [AudioController sizeOfFetchedArray];
}

// Display each row's data.
/*
-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component{
	return [AudioController titleForFetchResult:row];
}
*/
// Responding if the user picks a row
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component{
	
	
}

#pragma mark NotificationCenter

-(void)AudioControllerNotificationCenter:(kAudioControllerNotification)notification withObject:(id)object{
	
	switch (notification) {

		case kAudioControllerNotification_AudioSaveInProgress:
			
			break;
		case kAudioControllerNotification_AudioSaveComplete:
			
			break;
		case kAudioControllerNotification_AudioPlayingStarted:
			
			break;
		case kAudioControllerNotification_AudioPlayingStopped:
			[self setTrayConfigurationTo:currentTrayConfiguration];
			break;
		case kAudioControllerNotification_ECGSaveInProgress:
			
			break;
		case kAudioControllerNotification_ECGSaveComplete:
			
			break;
		case kAudioControllerNotification_SwipeOccurance:
			if (object == nil || ![object isKindOfClass:[UISwipeGestureRecognizer class]]) break;
			[self SwipeAction:object];
			break;
		case kAudioControllerNotification_ModeChange:
			[self setTrayConfigurationTo:currentTrayConfiguration];
			break;
		case kAudioControllerNotification_RateUpdate:
			if (object != nil) {
				[self setRateTo:[(NSNumber*)object intValue]];
			}
			break;
		default:
			break;
	}
	
	// Update Tray Configuration
	if (notification != kAudioControllerNotification_RateUpdate) {
		[self setTrayConfigurationTo:currentTrayConfiguration];
	}
	
}

-(void)setTrayConfigurationTo:(kTrayConfiguration)config{
	UIButton *button1 = (UIButton*)[trayView viewWithTag:1];
	UIButton *button2 = (UIButton*)[trayView viewWithTag:2];
	UIButton *button3 = (UIButton*)[trayView viewWithTag:3];
	UIButton *button4 = (UIButton*)[trayView viewWithTag:4];
	
	// Remove PickerViews and Text Views if Needed
	UIView *viewExtra1 = [trayView viewWithTag:5];
	UIView *viewExtra2 = [trayView viewWithTag:6];
	if (viewExtra1 != nil) [viewExtra1 removeFromSuperview];
	if (viewExtra2 != nil) [viewExtra2 removeFromSuperview];
	
	// Remove all events from buttons
	[button1 removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[button2 removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[button3 removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[button4 removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	
	// Reveal and activate all buttons
	[button1 setAlpha:1.0];
	[button1 setEnabled:YES];
	[button2 setAlpha:1.0];
	[button2 setEnabled:YES];
	[button3 setAlpha:1.0];
	[button3 setEnabled:YES];
	[button4 setAlpha:1.0];
	[button4 setEnabled:YES];
	
	// Declare any variables used for configuration
	NSString *fileName;
	CGRect rect;
	UIPickerView *pickerView;
	UITextField	*textField;
	float height = 265;
	
	switch (config) {
		case kTrayConfiguration_collapsed:
			rect = graphView.frame;
			rect.size.height = height;
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.2];
			trayView.center = CGPointMake(trayView.center.x, 216-kKeyBoardOffset);
			[graphView setFrame:rect];
			rateView.alpha = 1;
			[UIView commitAnimations];
			break;
		case kTrayConfiguration_main: // This Is the Configuration when a user initial reveals tools
			// Set images
			[button1 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"ECG_%i.png",(int)[AudioController isInECGMode]]] forState:UIControlStateNormal];
			[button2 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Record_%i.png",(int)[AudioController isRecording]]] forState:UIControlStateNormal];
			[button3 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Play_%i.png",(int)[AudioController isPlaying]]] forState:UIControlStateNormal];
			if ([AudioController isReadyToSave]) fileName = @"Save.png";
			else fileName = @"Open.png";
			[button4 setImage:[UIImage imageNamed:fileName] forState:UIControlStateNormal];
			
			// Set Actions
			[button1 addTarget:[AudioController class] action:@selector(switchMode) forControlEvents:UIControlEventTouchUpInside];
			if ([AudioController isRecording]) [button2 addTarget:[AudioController class] action:@selector(stopRecording) forControlEvents:UIControlEventTouchUpInside];
			else [button2 addTarget:[AudioController class] action:@selector(startRecording) forControlEvents:UIControlEventTouchUpInside];
			if ([AudioController isPlaying]) [button3 addTarget:[AudioController class] action:@selector(stopPlaying) forControlEvents:UIControlEventTouchUpInside];
			else [button3 addTarget:[AudioController class] action:@selector(startPlaying) forControlEvents:UIControlEventTouchUpInside];
			if ([AudioController isReadyToSave]) [button4 addTarget:self action:@selector(saveRecording) forControlEvents:UIControlEventTouchUpInside];
			else [button4 addTarget:self action:@selector(openRecording) forControlEvents:UIControlEventTouchUpInside];
			
			// Move Tray
			rect = graphView.frame;
			rect.size.height = height;
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.2];
			trayView.center = CGPointMake(trayView.center.x, 262-kKeyBoardOffset);
			graphView.frame = rect;
			rateView.alpha = 0;
			[UIView commitAnimations];
			
			break;
			
		case kTrayConfiguration_open:// This Is the Configuration when a user presses Open
			// Set Picker View
			
			rect = CGRectMake(20, 8, 280-40, 162);
			pickerView = [[UIPickerView alloc] initWithFrame:rect];
			[pickerView setDelegate:self];
			[pickerView setTag:5];
			[trayView addSubview:pickerView];
			height = -16-pickerView.frame.size.height+button1.frame.origin.y-trayView.frame.size.height/2+344-graphView.frame.origin.y;
			
			// Set Picker View Data
			[AudioController loadAllRecordings];
			[pickerView reloadAllComponents];
			
			// Set Buttons and Images
			[button1 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Delete.png"]] forState:UIControlStateNormal];
			[button3 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Export.png"]] forState:UIControlStateNormal];
			[button4 setImage:[UIImage imageNamed:@"Open.png"] forState:UIControlStateNormal];
			[button2 setAlpha:0];
			[button2 setEnabled:NO];
			
			// Set Actions
			[button1 addTarget:self action:@selector(deleteRecording) forControlEvents:UIControlEventTouchUpInside];
			[button3 addTarget:self action:@selector(exportRecording) forControlEvents:UIControlEventTouchUpInside];
			[button4 addTarget:self action:@selector(openRecording) forControlEvents:UIControlEventTouchUpInside];
			
			// Move View to Open Position
			rect = graphView.frame;
			rect.size.height = height;
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.2];
			trayView.center = CGPointMake(trayView.center.x, 344-kKeyBoardOffset);
			[graphView setFrame:rect];
			rateView.alpha = 0;
			[UIView commitAnimations];
			break;
		
		case kTrayConfiguration_save: // This Is the Configuration when a user presses Save
			
			// Set Text Field
			rect = CGRectMake(20, 104, 240, 30);
			textField = [[UITextField alloc] initWithFrame:rect];
			[textField setPlaceholder:@"First Name"];
			[textField setBackgroundColor:[UIColor whiteColor]];
			[textField setTextAlignment:NSTextAlignmentCenter];
			[textField setBorderStyle:UITextBorderStyleRoundedRect];
			[textField setTag:5];
			[trayView addSubview:textField];
			rect = CGRectMake(rect.origin.x, rect.origin.y+38, rect.size.width, rect.size.height);
			textField = [[UITextField alloc] initWithFrame:rect];
			[textField setPlaceholder:@"Last Name"];
			[textField setBackgroundColor:[UIColor whiteColor]];
			[textField setTextAlignment:NSTextAlignmentCenter];
			[textField setBorderStyle:UITextBorderStyleRoundedRect];
			[textField setTag:6];
			[trayView addSubview:textField];
			
			// Set Buttons and Images
			[button1 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Delete.png"]] forState:UIControlStateNormal];
			[button2 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Play_%i.png",(int)[AudioController isPlaying]]] forState:UIControlStateNormal];
			[button3 setImage:[UIImage imageNamed:[NSString stringWithFormat:@"Export.png"]] forState:UIControlStateNormal];
			[button4 setImage:[UIImage imageNamed:@"Save.png"] forState:UIControlStateNormal];
			
			// Set Actions
			[button1 addTarget:self action:@selector(deleteRecording) forControlEvents:UIControlEventTouchUpInside];
			if ([AudioController isPlaying]) [button2 addTarget:[AudioController class] action:@selector(stopPlaying) forControlEvents:UIControlEventTouchUpInside];
			else [button2 addTarget:[AudioController class] action:@selector(startPlaying) forControlEvents:UIControlEventTouchUpInside];
			[button3 addTarget:self action:@selector(exportRecording) forControlEvents:UIControlEventTouchUpInside];
			[button4 addTarget:self action:@selector(saveRecording) forControlEvents:UIControlEventTouchUpInside];
			
			// Move View to Open Position
			rect = graphView.frame;
			rect.size.height = height;
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.2];
			trayView.center = CGPointMake(trayView.center.x, 344-kKeyBoardOffset);
			[graphView setFrame:rect];
			rateView.alpha = 0;
			[UIView commitAnimations];
			
			break;
		default:
			break;
	}
	
	currentTrayConfiguration = config;
}

#pragma mark Keyboard Notifcation Center
-(void) keyboardDidShow: (NSNotification *)notification{
	
	// Get keyboard info
	NSDictionary* keyboardInfo = [notification userInfo];
    NSValue* keyboardFrame = [keyboardInfo valueForKey:UIKeyboardFrameBeginUserInfoKey];
    CGRect keyboardFrameRect = [keyboardFrame CGRectValue];
	
	kKeyBoardOffset = keyboardFrameRect.size.height;
	
	[UIView beginAnimations:Nil context:NULL];
	[UIView setAnimationDuration:0.2];
	for(UIView *subView in self.view.subviews)
		subView.center = CGPointMake(subView.center.x, subView.center.y-keyboardFrameRect.size.height);
	[UIView commitAnimations];
}

-(void) keyboardDidHide: (NSNotification *)notification{
	
	// Get keyboard info
	NSDictionary* keyboardInfo = [notification userInfo];
    NSValue* keyboardFrame = [keyboardInfo valueForKey:UIKeyboardFrameBeginUserInfoKey];
    CGRect keyboardFrameRect = [keyboardFrame CGRectValue];
	
	kKeyBoardOffset = 0;
	
	[UIView beginAnimations:Nil context:NULL];
	[UIView setAnimationDuration:0.2];
	for(UIView *subView in self.view.subviews)
		subView.center = CGPointMake(subView.center.x, subView.center.y+keyboardFrameRect.size.height);
	[UIView commitAnimations];
}


@end

