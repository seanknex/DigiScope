//
//  LiveViewController.m
//  DigiScope
//
//  Created by Sean Brown on 12/2/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import "LiveViewController.h"
#import "DigiScopeAppAppDelegate.h"
#import "AudioController.h"

@implementation LiveViewController
@synthesize SavePopoverController, SavePopoverViewController, cancelRecording, saveRecording, exportRecording, patientFirstName, patientLastName, LoadPopoverController, LoadPopoverViewController, cancelLoad, selectRecording, pickerView, deleteRecording, dateRecorded, saveSuccessLabel;

-(void)viewDidAppear:(BOOL)animated{
	
	// Start Audio Unit
	[AudioController startAudioUnit];
	[AudioController setView:graphView];
	
	// Setup Save Popover Controller
	SavePopoverViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"SavePopoverViewController"];
	SavePopoverController = [[UIPopoverController alloc] initWithContentViewController:SavePopoverViewController];
	[SavePopoverController setDelegate:self];
	[SavePopoverController setPopoverContentSize:[SavePopoverViewController.view viewWithTag:1].frame.size animated:NO];
	patientFirstName = (UITextField *)[SavePopoverViewController.view viewWithTag:2];
	patientLastName = (UITextField *)[SavePopoverViewController.view viewWithTag:3];
	cancelRecording = (UIButton *)[SavePopoverViewController.view viewWithTag:4];
	saveRecording = (UIButton *)[SavePopoverViewController.view viewWithTag:5];
	exportRecording = (UIButton *)[SavePopoverViewController.view viewWithTag:6];
	saveSuccessLabel = (UILabel *)[SavePopoverViewController.view viewWithTag:7];
	[cancelRecording addTarget:self action:@selector(cancelRecordingAction) forControlEvents:UIControlEventTouchUpInside];
	[saveRecording addTarget:self action:@selector(saveRecordingAction) forControlEvents:UIControlEventTouchUpInside];
	[exportRecording addTarget:self action:@selector(exportRecordingAction) forControlEvents:UIControlEventTouchUpInside];
	
	// Setup Picker View
	LoadPopoverViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"LoadPopoverViewController"];
	LoadPopoverController = [[UIPopoverController alloc] initWithContentViewController:LoadPopoverViewController];
	[LoadPopoverController setDelegate:self];
	[LoadPopoverController setPopoverContentSize:[LoadPopoverViewController.view viewWithTag:1].frame.size animated:NO];
	pickerView = (UIPickerView *)[LoadPopoverViewController.view viewWithTag:2];
	cancelLoad = (UIButton *)[LoadPopoverViewController.view viewWithTag:3];
	selectRecording = (UIButton *)[LoadPopoverViewController.view viewWithTag:4];
	deleteRecording = (UIButton *)[LoadPopoverViewController.view viewWithTag:5];
	dateRecorded = (UILabel *)[LoadPopoverViewController.view viewWithTag:6];
	[cancelLoad addTarget:self action:@selector(cancelLoadAction) forControlEvents:UIControlEventTouchUpInside];
	[selectRecording addTarget:self action:@selector(selectRecordingAction) forControlEvents:UIControlEventTouchUpInside];
	[deleteRecording addTarget:self action:@selector(deleteRecordingAction) forControlEvents:UIControlEventTouchUpInside];
	[pickerView setDelegate:self];
	
}


- (IBAction)loadAction:(id)sender {
	[AudioController loadAllRecordings];
	[LoadPopoverController presentPopoverFromRect:loadOutlet.frame inView:self.view permittedArrowDirections:UIPopoverArrowDirectionDown animated:YES];
	[pickerView reloadAllComponents];
	
	// Test if recordings exist
	if ([AudioController sizeOfFetchedArray] == 0) {
		[selectRecording setEnabled:NO];
		[selectRecording setHidden:YES];
		[deleteRecording setEnabled:NO];
		[deleteRecording setHidden:YES];
		[dateRecorded setText:@""];
	}
	else{
		[selectRecording setEnabled:YES];
		[selectRecording setHidden:NO];
		[deleteRecording setEnabled:YES];
		[deleteRecording setHidden:NO];
	}
}

- (IBAction)recordAction:(id)sender {
	if ([AudioController isRecording] && ![AudioController isPlaying]) {
		[AudioController stopRecording];
		[recordOutlet setTitle:@"Record" forState:UIControlStateNormal];
		[saveRecording setEnabled:YES];
		[saveRecording setHidden:NO];
		[exportRecording setEnabled:YES];
		[exportRecording setHidden:NO];
		[SavePopoverController presentPopoverFromRect:recordOutlet.frame inView:self.view permittedArrowDirections:UIPopoverArrowDirectionDown animated:YES];
	}
	else if(![AudioController isPlaying]){
		[AudioController startRecording];
		[recordOutlet setTitle:@"Stop" forState:UIControlStateNormal];
	}
	else
		NSLog(@"\nError, cannot record while playing");
	
}

- (IBAction)playAction:(id)sender {
	if ([AudioController isPlaying] && ![AudioController isRecording]) {
		[AudioController stopPlaying];
		[playOutlet setTitle:@"Play" forState:UIControlStateNormal];
	}
	else if(![AudioController isRecording]){
		float delay = [AudioController startPlaying];
		[playOutlet setTitle:@"Stop" forState:UIControlStateNormal];
		[self performSelector:@selector(resetPlayButton) withObject:nil afterDelay:delay];
	}
	else
		NSLog(@"\nError, cannot play while recording");
}

-(void)resetPlayButton{
	[playOutlet setTitle:@"Play" forState:UIControlStateNormal];
	[AudioController startAudioUnit];
}

-(void)cancelRecordingAction{
	[SavePopoverController dismissPopoverAnimated:YES];
}

-(void)saveRecordingAction{
	BOOL saveSuccessful;
	saveSuccessful = [AudioController saveRecording:patientFirstName.text :patientLastName.text];
	
	if (saveSuccessful){
		[saveSuccessLabel setText:@"Save Successful!"];
		[saveSuccessLabel setBackgroundColor:[UIColor greenColor]];
		[saveRecording setEnabled:NO];
		[saveRecording setHidden:YES];
	}
	else{
		[saveSuccessLabel setText:@"Save Failed!"];
		[saveSuccessLabel setBackgroundColor:[UIColor redColor]];
	}
		
	[saveSuccessLabel setHidden:NO];
	[self performSelector:@selector(resetSaveBanner) withObject:nil afterDelay:3.0f];
}

-(void)exportRecordingAction{
	[SavePopoverController dismissPopoverAnimated:YES];
	[AudioController emailMP3FileFromURL :patientFirstName.text :patientLastName.text];
}

-(void)cancelLoadAction{
	[LoadPopoverController dismissPopoverAnimated:YES];
}

-(void)selectRecordingAction{
	if ([AudioController sizeOfFetchedArray] != 0) {
		[AudioController loadRecordingAtFetchIndex:[pickerView selectedRowInComponent:0]];
		[LoadPopoverController dismissPopoverAnimated:YES];
	}
}

-(void)deleteRecordingAction{
	
	if ([AudioController sizeOfFetchedArray] != 0) {
		[AudioController deleteRecordingAtFetchIndex:[pickerView selectedRowInComponent:0]];
		[pickerView reloadAllComponents];
	}
	
	// Test if the user removed the last component
	if ([AudioController sizeOfFetchedArray] == 0) {
		[selectRecording setEnabled:NO];
		[selectRecording setHidden:YES];
		[deleteRecording setEnabled:NO];
		[deleteRecording setHidden:YES];
		[dateRecorded setText:@""];
	}
	
}

// Number of components.
-(NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView{
	return 1;
}

// Total rows in our component.
-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component{
	if ([AudioController sizeOfFetchedArray] == 0)
		return 1;
	
	return [AudioController sizeOfFetchedArray];
}

// Display each row's data.
-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component{
	return [AudioController titleForFetchResult:row];
}

// Responding if the user picks a row
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component{
	
	if ([AudioController sizeOfFetchedArray] != 0)
		[dateRecorded setText:[AudioController dateForFetchResult:row]];
	else
		[dateRecorded setText:@""];
	
	
}

-(void)resetSaveBanner{
	[saveSuccessLabel setHidden:YES];
}


@end
