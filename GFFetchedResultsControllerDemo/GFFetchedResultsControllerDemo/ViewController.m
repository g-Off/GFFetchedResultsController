//
//  ViewController.m
//  GFFetchedResultsControllerDemo
//
//  Created by Geoffrey Foster on 2014-11-04.
//  Copyright (c) 2014 Geoffrey Foster. All rights reserved.
//

#import "ViewController.h"
#import "GFFetchedResultsController.h"
#import "DemoObject.h"

@implementation ViewController {
	IBOutlet NSManagedObjectContext *_managedObjectContext;
	GFFetchedResultsController *_fetchedResultsController;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"DemoModel" withExtension:@"momd"];
	NSManagedObjectModel *mom = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
	
	NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES,
							  NSInferMappingModelAutomaticallyOption: @YES};
	
	NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
	NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"fetched_demo.storedata"]];
	NSError *error;
	[psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:&error];
	
	_managedObjectContext.persistentStoreCoordinator = psc;
	
	NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DemoObject"];
	_fetchedResultsController = [[GFFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:_managedObjectContext];
	
	NSError *fetchError;
	if (![_fetchedResultsController performFetch:&fetchError]) {
		NSLog(@"%@", fetchError);
	}
}

- (void)setRepresentedObject:(id)representedObject {
	[super setRepresentedObject:representedObject];

	// Update the view, if already loaded.
}

@end
