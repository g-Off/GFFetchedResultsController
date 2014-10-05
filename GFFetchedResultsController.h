//
//  GFFetchedResultsController.h
//
//  Created by Geoffrey Foster on 2013-02-10.
//  Copyright (c) 2013 Geoffrey Foster. All rights reserved.
//

#import <CoreData/CoreData.h>

@class GFFetchedResultsController;

@protocol GFFetchedResultsSectionInfo

/* Name of the section
 */
@property (nonatomic, readonly) NSString *name;

/* Title of the section (used when displaying the index)
 */
@property (nonatomic, readonly) NSString *indexTitle;

/* Number of objects in section
 */
@property (nonatomic, readonly) NSUInteger numberOfObjects;

/* Returns the array of objects in the section.
 */
@property (nonatomic, readonly) NSArray *objects;

@end // GFFetchedResultsSectionInfo

typedef NS_ENUM(NSUInteger, GFFetchedResultsChangeType) {
	GFFetchedResultsChangeInsert = 1,
	GFFetchedResultsChangeDelete = 2,
	GFFetchedResultsChangeMove = 3,
	GFFetchedResultsChangeUpdate = 4
};

@protocol GFFetchedResultsControllerDelegate <NSObject>

/* Notifies the delegate that a fetched object has been changed due to an add, remove, move, or update. Enables GFFetchedResultsController change tracking.
 controller - controller instance that noticed the change on its fetched objects
 anObject - changed object
 indexPath - indexPath of changed object (nil for inserts)
 type - indicates if the change was an insert, delete, move, or update
 newIndexPath - the destination path for inserted or moved objects, nil otherwise
 
 Changes are reported with the following heuristics:
 
 On Adds and Removes, only the Added/Removed object is reported. It's assumed that all objects that come after the affected object are also moved, but these moves are not reported.
 The Move object is reported when the changed attribute on the object is one of the sort descriptors used in the fetch request.  An update of the object is assumed in this case, but no separate update message is sent to the delegate.
 The Update object is reported when an object's state changes, and the changed attributes aren't part of the sort keys.
 */
@optional

- (void)controller:(GFFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(GFFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath;

/* Notifies the delegate of added or removed sections.  Enables NSFetchedResultsController change tracking.
 
 controller - controller instance that noticed the change on its sections
 sectionInfo - changed section
 index - index of changed section
 type - indicates if the change was an insert or delete
 
 Changes on section info are reported before changes on fetchedObjects.
 */
@optional
- (void)controller:(GFFetchedResultsController *)controller didChangeSection:(id <GFFetchedResultsSectionInfo>)sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(GFFetchedResultsChangeType)type;

/* Notifies the delegate that section and object changes are about to be processed and notifications will be sent.  Enables GFFetchedResultsController change tracking.
 Clients utilizing a UITableView may prepare for a batch of updates by responding to this method with -beginUpdates
 */
@optional
- (void)controllerWillChangeContent:(GFFetchedResultsController *)controller;

/* Notifies the delegate that all section and object changes have been sent. Enables GFFetchedResultsController change tracking.
 Providing an empty implementation will enable change tracking if you do not care about the individual callbacks.
 */
@optional
- (void)controllerDidChangeContent:(GFFetchedResultsController *)controller;

/* Asks the delegate to return the corresponding section index entry for a given section name.	Does not enable NSFetchedResultsController change tracking.
 If this method isn't implemented by the delegate, the default implementation returns the capitalized first letter of the section name (seee NSFetchedResultsController sectionIndexTitleForSectionName:)
 Only needed if a section index is used.
 */
@optional
- (NSString *)controller:(GFFetchedResultsController *)controller sectionIndexTitleForSectionName:(NSString *)sectionName;

@end

@interface GFFetchedResultsController : NSObject

@property (nonatomic, weak) id <GFFetchedResultsControllerDelegate> delegate;
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readonly) NSFetchRequest *fetchRequest;
@property (nonatomic, readonly) NSArray *fetchedObjects;
@property (nonatomic, readonly) NSString *sectionNameKeyPath;

@property (nonatomic, readonly) NSArray *sections;
@property (nonatomic, readonly) NSArray *sectionIndexTitles;

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest managedObjectContext:(NSManagedObjectContext *)context sectionNameKeyPath:(NSString *)sectionNameKeyPath;
- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest managedObjectContext:(NSManagedObjectContext *)context;

- (BOOL)performFetch:(NSError **)error;

- (id)objectAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForObject:(id)object __attribute__((nonnull(1)));

- (NSUInteger)numberOfObjects;

- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName;

#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
- (NSIndexPath *)indexPathForTableViewIndex:(NSUInteger)idx;
- (NSUInteger)numberOfRowsForTableView;
#endif

@end
