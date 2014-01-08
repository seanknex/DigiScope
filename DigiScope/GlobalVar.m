//
//  GlobalVar.m
//  DigiScope
//
//  Created by Sean Brown on 12/2/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import "GlobalVar.h"

@implementation GlobalVar
@synthesize bluetoothOnly;

+(GlobalVar *)sharedInstance{
	static GlobalVar *myInstance = nil;
	
	if (nil==myInstance) {
		myInstance = [[[self class] alloc] init];
		myInstance.bluetoothOnly = FALSE; // This needs to be TRUE for the Final
	}
	return myInstance;
}

@end
