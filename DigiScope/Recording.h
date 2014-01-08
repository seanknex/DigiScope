//
//  Recording.h
//  DigiScope
//
//  Created by Sean Brown on 12/4/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Recording : NSManagedObject

@property (nonatomic, retain) NSString * recordingPatientFirstName;
@property (nonatomic, retain) NSString * recordingPatientLastName;
@property (nonatomic, retain) NSData * recordingData;
@property (nonatomic, retain) NSDate * recordingDate;

@end
