//
//  UIPopoverOverride.m
//  DigiScope
//
//  Created by Sean Brown on 12/4/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import "UIPopoverOverride.h"

@implementation UIPopoverController (overrides)
+ (BOOL)_popoversDisabled { return NO;
}

@end
