//
//  Recording.h
//  DigiScope
//
//  Created by Sean Brown on 2/3/14.
//  Copyright (c) 2014 Sound the Bell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Recording : NSManagedObject

@property (nonatomic, retain) NSString * recordingPath;
@property (nonatomic, retain) NSDate * recordingDate;
@property (nonatomic, retain) NSString * recordingPatientFirstName;
@property (nonatomic, retain) NSString * recordingPatientLastName;
@property (nonatomic, retain) NSNumber * recordingIsECG;

@end
