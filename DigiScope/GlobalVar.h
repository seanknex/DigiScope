//
//  GlobalVar.h
//  DigiScope
//
//  Created by Sean Brown on 12/2/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface GlobalVar : NSObject{
	
}

@property BOOL bluetoothOnly;

+(GlobalVar *)sharedInstance;

@end
