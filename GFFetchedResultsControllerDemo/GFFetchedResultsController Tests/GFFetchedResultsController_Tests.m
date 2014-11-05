//
//  GFFetchedResultsController_Tests.m
//  GFFetchedResultsController Tests
//
//  Created by Geoffrey Foster on 2014-11-04.
//  Copyright (c) 2014 Geoffrey Foster. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#import "GFFetchedResultsController.h"

#import "DemoObject.h"

@interface GFFetchedResultsController_Tests : XCTestCase

@end

@implementation GFFetchedResultsController_Tests {
	NSURL *_url;
	NSManagedObjectContext *_ctx;
}

- (void)setUp
{
	[super setUp];
	
	NSURL *modelURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DemoModel" withExtension:@"momd"];
	NSManagedObjectModel *mom = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
	
	NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES,
							  NSInferMappingModelAutomaticallyOption: @YES};
	
	NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
	_url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
	NSError *error;
	[psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:_url options:options error:&error];
	
	_ctx = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
	_ctx.persistentStoreCoordinator = psc;
	
	for (NSUInteger i = 0; i < 20; ++i) {
		DemoObject *obj = [NSEntityDescription insertNewObjectForEntityForName:@"DemoObject" inManagedObjectContext:_ctx];
		obj.age = @(i);
	}
	
	NSError *saveError;
	XCTAssertTrue([_ctx save:&saveError]);
	XCTAssertNil(saveError, @"%@", saveError);
}

- (void)tearDown
{
	NSError *deleteError;
	[[NSFileManager defaultManager] removeItemAtURL:_url error:&deleteError];
	[super tearDown];
}

- (void)testBasicFetch
{
	NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DemoObject"];
	GFFetchedResultsController *frc = [[GFFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:_ctx];
	NSError *fetchError;
	XCTAssertTrue([frc performFetch:&fetchError]);
	XCTAssertNil(fetchError, @"%@", fetchError);
	XCTAssertEqual(frc.fetchedObjects.count, 20);
}

- (void)testBasicPredicateFetch
{
	NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DemoObject"];
	fetchRequest.predicate = [NSPredicate predicateWithFormat:@"age < 10"];
	GFFetchedResultsController *frc = [[GFFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:_ctx];
	NSError *fetchError;
	XCTAssertTrue([frc performFetch:&fetchError]);
	XCTAssertNil(fetchError, @"%@", fetchError);
	XCTAssertEqual(frc.fetchedObjects.count, 10);
}

@end
