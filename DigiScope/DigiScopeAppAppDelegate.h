//
//  DigiScopeAppAppDelegate.h
//  DigiScope
//
//  Created by Sean Brown on 10/15/13.
//  Copyright (c) 2013 Sound the Bell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DigiScopeAppAppDelegate : UIResponder <UIApplicationDelegate>{
	
}

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

- (NSURL *)applicationDocumentsDirectory;

@property (strong, nonatomic) UIWindow *window;

@end
