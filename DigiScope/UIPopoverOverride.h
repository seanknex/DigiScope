//
//  UIPopoverOverride.h
//  DigiScope
//
//  Created by Sean Brown on 12/4/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UIPopoverController (overrides)
+ (BOOL)_popoversDisabled;
@end
