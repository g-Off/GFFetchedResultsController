//
//  GFFetchedResultsController.m
//
//  Created by Geoffrey Foster on 2013-02-10.
//  Copyright (c) 2013 Geoffrey Foster. All rights reserved.
//

/* Notes
 * -[NSData initWithContentsOfMappedFile:]
 */

#import "GFFetchedResultsController.h"

@interface NSFetchRequest (GFEntityResolution)

- (NSEntityDescription *)gf_resolvedEntityInContext:(NSManagedObjectContext *)ctx;

@end

@implementation NSFetchRequest (GFEntityResolution)

- (NSEntityDescription *)gf_resolvedEntityInContext:(NSManagedObjectContext *)ctx
{
	NSEntityDescription *entity = [NSEntityDescription entityForName:self.entityName inManagedObjectContext:ctx];
	return entity;
}

@end

@interface _GFDefaultSectionInfo : NSObject <GFFetchedResultsSectionInfo>

@property(nonatomic) NSUInteger oldSectionNumber;
@property(readonly, nonatomic) NSUInteger numberOfObjects;
@property(readonly, nonatomic) NSUInteger sectionOffset;
@property(readonly, nonatomic) NSString *indexTitle;
@property(readonly, nonatomic) NSString *name;
@property(readonly, nonatomic) NSArray *objects;
@property(readonly, nonatomic) NSUInteger sectionNumber;

- (id)initWithController:(GFFetchedResultsController *)controller name:(NSString *)name indexTitle:(NSString *)indexTitle sectionOffset:(NSUInteger)sectionOffset;

- (NSUInteger)indexOfObject:(id)obj;
- (void)clearSectionObjectsCache;
- (void)setController:(GFFetchedResultsController *)controller;
- (void)setSectionOffset:(NSUInteger)sectionOffset;
- (void)setNumberOfObjects:(NSUInteger)numberOfObjects;

@end

@implementation _GFDefaultSectionInfo {
	__weak GFFetchedResultsController *_controller;
	NSArray *_sectionObjects;
}

- (id)initWithController:(GFFetchedResultsController *)controller name:(NSString *)name indexTitle:(NSString *)indexTitle sectionOffset:(NSUInteger)sectionOffset
{
	if ((self = [super init])) {
		_controller = controller;
		_name = [name copy];
		_indexTitle = [indexTitle copy];
		_sectionOffset = sectionOffset;
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ - (%@ @[%tu]): [%tu, %tu]", [super description], self.name, self.sectionNumber, self.sectionOffset, self.numberOfObjects];
}

- (NSArray *)objects
{
	if (_controller && !_sectionObjects) {
		NSArray *fetchedObjects = [_controller fetchedObjects];
		_sectionObjects = [fetchedObjects subarrayWithRange:NSMakeRange(self.sectionOffset, self.numberOfObjects)];
	}
	return _sectionObjects;
}

- (NSUInteger)sectionNumber
{
	NSUInteger sectionNumber = [[_controller sections] indexOfObject:self];
	if (sectionNumber == NSNotFound) {
		NSLog(@"CoreData: error: (UMFetchedResultsController) section '%@' not found in controller", [self name]);
	}
	return sectionNumber;
}

- (NSUInteger)indexOfObject:(id)obj
{
	NSUInteger idx;
	if (_sectionObjects) {
		idx = [_sectionObjects indexOfObject:obj];
	} else {
		idx = [[_controller fetchedObjects] indexOfObject:obj inRange:NSMakeRange(self.sectionOffset, self.numberOfObjects)];
		if (idx != NSNotFound) {
			idx = idx - 0; // ??
		}
	}
	return idx;
}

- (void)setController:(GFFetchedResultsController *)controller
{
	_controller = controller;
}

- (void)setSectionOffset:(NSUInteger)sectionOffset
{
	_sectionOffset = sectionOffset;
	[self clearSectionObjectsCache];
}

- (void)setNumberOfObjects:(NSUInteger)numberOfObjects
{
	_numberOfObjects = numberOfObjects;
	[self clearSectionObjectsCache];
}

- (void)clearSectionObjectsCache
{
	_sectionObjects = nil;
}

@end

static NSString *kContentChangeObjectKey = @"_ContentChange_ObjectKey";
static NSString *kContentChangeUpdateTypeKey = @"_ContentChange_updateTypeKey";
static NSString *kContentChangeOldIndexPathKey = @"_ContentChange_OldIndexPathKey";
static NSString *kContentChangeNewIndexPathKey = @"_ContentChange_NewIndexPathKey";
static NSString *kContentChangeSectionInfoKey = @"_ContentChange_SectionInfoKey";
static NSString *kContentChangeDidChangeSectionsKey = @"_ContentChange_didChangeSectionsKey";

@interface GFFetchedResultsController ()

@property (nonatomic, readwrite) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readwrite) NSFetchRequest *fetchRequest;
@property (nonatomic, readwrite) NSArray *fetchedObjects;

@end

@implementation GFFetchedResultsController {
	struct _fetchResultsControllerFlags {
        unsigned int _sendObjectChangeNotifications:1;
        unsigned int _sendSectionChangeNotifications:1;
        unsigned int _sendDidChangeContentNotifications:1;
        unsigned int _sendWillChangeContentNotifications:1;
        unsigned int _sendSectionIndexTitleForSectionName:1;
        unsigned int _changedResultsSinceLastSave:1;
        unsigned int _hasMutableFetchedResults:1;
        unsigned int _hasBatchedArrayResults:1;
        unsigned int _hasSections:1;
        unsigned int _usesNonpersistedProperties:1;
        unsigned int _includesSubentities:1;
        unsigned int _reservedFlags:21;
    } _flags;
	
	NSMutableArray *_sections;
	NSMutableDictionary *_sectionsByName;
	NSMutableArray *_sortKeys;
}

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest managedObjectContext:(NSManagedObjectContext *)context sectionNameKeyPath:(NSString *)sectionNameKeyPath
{
	if (!fetchRequest || !context) {
		NSString *reason = [NSString stringWithFormat:@"An instance of %@ requires a non-nil fetchRequest and managedObjectContext", [self class]];
		[[NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil] raise];
	}
	if (!fetchRequest.sortDescriptors) {
		//NSString *reason = [NSString stringWithFormat:@"An instance of %@ requires a fetch request with sort descriptors", [self class]];
		//[[NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil] raise];
	}
	if ((self = [super init])) {
		_fetchRequest = fetchRequest;
		_managedObjectContext = context;
		_sectionNameKeyPath = [sectionNameKeyPath copy];
		
		_flags._hasSections = _sectionNameKeyPath != nil;
		
		NSEntityDescription *entity = [_fetchRequest gf_resolvedEntityInContext:_managedObjectContext];
		if ([[entity subentitiesByName] count]) {
			_flags._includesSubentities = [_fetchRequest includesSubentities];
		}
		
		_sortKeys = [[NSMutableArray alloc] init];
		
		for (NSSortDescriptor *sortDescriptor in _fetchRequest.sortDescriptors) {
			NSString *keyPath = sortDescriptor.key;
			NSArray *keyPathComponents = [keyPath componentsSeparatedByString:@"."];
			[_sortKeys addObject:[keyPathComponents firstObject]];
			_flags._usesNonpersistedProperties |= [self _keyPathContainsNonPersistedProperties:keyPathComponents];
		}
		
		if (_flags._hasSections) {
			NSArray *keyPathComponents = [_sectionNameKeyPath componentsSeparatedByString:@"."];
			_flags._usesNonpersistedProperties |= [self _keyPathContainsNonPersistedProperties:keyPathComponents];
		}
	}
	
	return self;
}

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest managedObjectContext:(NSManagedObjectContext *)context
{
	return [self initWithFetchRequest:fetchRequest managedObjectContext:context sectionNameKeyPath:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)performFetch:(NSError **)error
{
	BOOL returnsAsFaults = [_fetchRequest returnsObjectsAsFaults];
	[_fetchRequest setReturnsObjectsAsFaults:YES];
	
	NSError *fetchError = nil;
	self.fetchedObjects = [_managedObjectContext executeFetchRequest:_fetchRequest error:&fetchError];
	
	if (error) {
		*error = fetchError;
	}
	
	if (self.fetchedObjects) {
		if (![self _computeSectionInfo:self.fetchedObjects error:&fetchError]) {
			_fetchedObjects = nil;
			if (error) {
				*error = fetchError;
			}
		}
	} else {
		// reset to nil
		_sections = nil;
		_sectionsByName = nil;
		_sectionIndexTitles = nil;
		//_sectionIndexTitlesSections;
	}
	
	[_fetchRequest setReturnsObjectsAsFaults:returnsAsFaults];
	
	return (fetchError == nil);
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
	id object = nil;
	NSUInteger sectionIndex = [indexPath indexAtPosition:0];
	NSUInteger rowIndex = [indexPath indexAtPosition:1];
	
	NSArray *sections = [self sections];
	if (sections) {
		if (sectionIndex <= [sections count]) {
			_GFDefaultSectionInfo *section = sections[sectionIndex];
			NSUInteger numberOfObjects = [section numberOfObjects];
			if (rowIndex <= numberOfObjects) {
				NSUInteger idx = [section sectionOffset] + rowIndex;
				object = _fetchedObjects[idx];
			} else {
				NSString *reason = [NSString stringWithFormat:@"no object at index %tu in section at index %tu", rowIndex, sectionIndex];
				[[NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil] raise];
			}
		} else {
			NSString *reason = [NSString stringWithFormat:@"no section at index %tu", (unsigned long)sectionIndex];
			[[NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil] raise];
		}
	} else {
		object = _fetchedObjects[rowIndex];
	}
	
	return object;
}

- (NSIndexPath *)indexPathForObject:(id)object
{
	NSIndexPath *indexPath = nil;
	if (object) {
		_GFDefaultSectionInfo *sectionInfo;
		if (_flags._hasSections) {
			NSString *sectionName = [self _sectionNameForObject:object];
			sectionInfo = _sectionsByName[sectionName];
		} else {
			sectionInfo = [_sections lastObject];
		}
		
		if (sectionInfo) {
			NSUInteger idx = [sectionInfo indexOfObject:object];
			if (idx != NSNotFound) {
				NSUInteger section = [sectionInfo sectionNumber];
				NSUInteger indexes[2] = {section, idx};
				indexPath = [NSIndexPath indexPathWithIndexes:indexes length:2];
			}
		}
	}
	return indexPath;
}

- (NSUInteger)numberOfObjects
{
	return [_fetchedObjects count];
}

#pragma mark - Delegate

- (void)setDelegate:(id<GFFetchedResultsControllerDelegate>)delegate
{
	if (_delegate == delegate) {
		return;
	}
	
	if (_delegate) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:_managedObjectContext];
	}
	
	_delegate = delegate;
	
	if (_delegate) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:_managedObjectContext];
	}
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:_managedObjectContext];
	
	_flags._sendObjectChangeNotifications = [_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)];
	_flags._sendSectionChangeNotifications = [_delegate respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)];
	_flags._sendDidChangeContentNotifications = [_delegate respondsToSelector:@selector(controllerDidChangeContent:)];
	_flags._sendWillChangeContentNotifications = [_delegate respondsToSelector:@selector(controllerWillChangeContent:)];
	_flags._sendSectionIndexTitleForSectionName = [_delegate respondsToSelector:@selector(controller:sectionIndexTitleForSectionName:)];
}

#pragma mark - Notifications

- (void)_managedObjectContextDidChange:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	[self _processManagedObjectContextUserInfo:userInfo];
}

- (void)_managedObjectContextDidSave:(NSNotification *)notification
{
	
}

- (void)_processManagedObjectContextUserInfo:(NSDictionary *)userInfo
{
	NSEntityDescription *entity = [_fetchRequest gf_resolvedEntityInContext:_managedObjectContext];
	
	NSMutableSet *newSectionNames = [[NSMutableSet alloc] init];
	NSMutableDictionary *sectionsWithDeletes = [[NSMutableDictionary alloc] init];
	
	NSMutableArray *insertsInfo = [[NSMutableArray alloc] init];
	NSMutableArray *deletesInfo = [[NSMutableArray alloc] init];
	NSMutableArray *updatesInfo = [[NSMutableArray alloc] init];
	
	NSSet *inserted = [userInfo[NSInsertedObjectsKey] objectsPassingTest:^BOOL(NSManagedObject *obj, BOOL *stop) {
		return [[obj entity] isEqual:entity];
	}];
	[self _preprocessInsertedObjects:inserted insertsInfo:insertsInfo newSectionNames:newSectionNames];
	
	NSSet *deleted = [userInfo[NSDeletedObjectsKey] objectsPassingTest:^BOOL(NSManagedObject *obj, BOOL *stop) {
		return [[obj entity] isEqual:entity];
	}];
	[self _preprocessDeletedObjects:deleted deletesInfo:deletesInfo sectionsWithDeletes:sectionsWithDeletes];
	
	NSSet *invalidated = [userInfo[NSInvalidatedObjectsKey] objectsPassingTest:^BOOL(NSManagedObject *obj, BOOL *stop) {
		return [[obj entity] isEqual:entity];
	}];
	[self _preprocessDeletedObjects:invalidated deletesInfo:deletesInfo sectionsWithDeletes:sectionsWithDeletes]; // with invalidated objects this time, TODO
	
	NSSet *updated = [userInfo[NSUpdatedObjectsKey] objectsPassingTest:^BOOL(NSManagedObject *obj, BOOL *stop) {
		return [[obj entity] isEqual:entity];
	}];
	[self _preprocessUpdatedObjects:updated insertsInfo:insertsInfo deletesInfo:deletesInfo updatesInfo:updatesInfo sectionsWithDeletes:sectionsWithDeletes newSectionNames:newSectionNames treatAsRefreshes:NO];
	
	NSSet *refreshedObjects = [userInfo objectForKey:NSRefreshedObjectsKey];
	if (refreshedObjects) {
		NSMutableSet *mutableRefreshedObjects = [[NSMutableSet alloc] initWithSet:refreshedObjects];
		if (deleted) {
			[mutableRefreshedObjects minusSet:deleted];
		}
		
		if (updated) {
			[mutableRefreshedObjects minusSet:updated];
		}
		
		[self _preprocessUpdatedObjects:mutableRefreshedObjects insertsInfo:insertsInfo deletesInfo:deletesInfo updatesInfo:updatesInfo sectionsWithDeletes:sectionsWithDeletes newSectionNames:newSectionNames treatAsRefreshes:YES];
	}
	
	if ([insertsInfo count] > 0 || [deletesInfo count] > 0 || [updatesInfo count] > 0) {
		if (self.delegate && _flags._sendWillChangeContentNotifications) {
			[self.delegate controllerWillChangeContent:self];
		}
		
		BOOL didFailPostprocessing = NO;
		
		BOOL processed = [self _postprocessDeletedObjects:deletesInfo];
		if (!processed) {
			// error
			didFailPostprocessing = YES;
		} else {
			processed = [self _postprocessUpdatedObjects:updatesInfo];
			if (!processed) {
				didFailPostprocessing = !processed;
			} else {
				processed = [self _postprocessInsertedObjects:insertsInfo];
				didFailPostprocessing = !processed;
			}
		}
		
		if (didFailPostprocessing) {
			NSError *refetchError = nil;
			BOOL refetched = [self performFetch:&refetchError];
			if (!refetched) {
				NSLog(@"CoreData: error: (NSFetchedResultsController) error refetching objects after context update: %@", refetchError);
			}
		} else {
			//... what do we do here? was this just section name updating? cache updates?
		}
		
		if (self.delegate && _flags._sendObjectChangeNotifications) {
			for (NSDictionary *info in deletesInfo) {
				NSManagedObject *object = info[kContentChangeObjectKey];
				GFFetchedResultsChangeType changeType = [info[kContentChangeUpdateTypeKey] unsignedIntegerValue];
				NSIndexPath *oldIndexPath = info[kContentChangeOldIndexPathKey];
				[self.delegate controller:self didChangeObject:object atIndexPath:oldIndexPath forChangeType:changeType newIndexPath:nil];
			}
			
			// NSTableView doesn't seem to like having an insertion done at indexes that are out of bounds (currently)
			// Getting around this by sorting insertions based on insertion index
			// TODO: Create sample project, file radar
			NSMutableArray *insertsInfoCopy = [[NSMutableArray alloc] initWithCapacity:[insertsInfo count]];
			for (NSDictionary *info in insertsInfo) {
				NSMutableDictionary *infoCopy = [info mutableCopy];
				NSManagedObject *object = info[kContentChangeObjectKey];
				NSUInteger newIndex = [self _indexOfFetchedID:[object objectID]];
				infoCopy[kContentChangeNewIndexPathKey] = [self _indexPathForIndex:newIndex];
				[insertsInfoCopy addObject:infoCopy];
			}
			
			[insertsInfoCopy sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:kContentChangeNewIndexPathKey ascending:YES]]];
			for (NSDictionary *info in insertsInfoCopy) {
				NSManagedObject *object = info[kContentChangeObjectKey];
				GFFetchedResultsChangeType changeType = [info[kContentChangeUpdateTypeKey] unsignedIntegerValue];
				NSIndexPath *newIndexPath = info[kContentChangeNewIndexPathKey];
				[self.delegate controller:self didChangeObject:object atIndexPath:nil forChangeType:changeType newIndexPath:newIndexPath];
			}
			
			for (NSDictionary *info in updatesInfo) {
				NSManagedObject *object = info[kContentChangeObjectKey];
				GFFetchedResultsChangeType changeType = [info[kContentChangeUpdateTypeKey] unsignedIntegerValue];
				
				NSIndexPath *oldIndexPath = info[kContentChangeOldIndexPathKey];
				NSIndexPath *newIndexPath = [self indexPathForObject:object];
				
				if (changeType == GFFetchedResultsChangeMove) {
					[self.delegate controller:self didChangeObject:object atIndexPath:oldIndexPath forChangeType:changeType newIndexPath:newIndexPath];
				} else {
					[self.delegate controller:self didChangeObject:object atIndexPath:oldIndexPath forChangeType:changeType newIndexPath:newIndexPath];
				}
			}
		}
		
		if (_flags._sendSectionChangeNotifications) {
			for (NSString *sectionName in newSectionNames) {
				_GFDefaultSectionInfo *section = _sectionsByName[sectionName];
				[self.delegate controller:self didChangeSection:section atIndex:section.sectionNumber forChangeType:GFFetchedResultsChangeInsert];
			}
			
			// TODO: hm?
			//for (NSString *sectionName in sectionsWithDeletes) {
			//}
			
			for (_GFDefaultSectionInfo *section in [sectionsWithDeletes allValues]) {
				if (_sectionsByName[section.name] == nil) {
					[self.delegate controller:self didChangeSection:section atIndex:section.oldSectionNumber forChangeType:GFFetchedResultsChangeDelete];
				}
			}
		}
		
		if (self.delegate && _flags._sendDidChangeContentNotifications) {
			[self.delegate controllerDidChangeContent:self];
		}
	}
}

- (NSUInteger)_indexOfFetchedID:(NSManagedObjectID *)objectID
{
	return [self.fetchedObjects indexOfObjectPassingTest:^BOOL(NSManagedObject *obj, NSUInteger idx, BOOL *stop) {
		return [[obj objectID] isEqual:objectID];
	}];
}

#pragma mark - Insertion Helpers

- (void)_preprocessInsertedObjects:(NSSet *)insertedObjects insertsInfo:(NSMutableArray *)insertsInfo newSectionNames:(NSMutableSet *)newSectionNames
{
	NSPredicate *predicate = self.fetchRequest.predicate;
	for (NSManagedObject *insertedObject in insertedObjects) {
		if (predicate == nil || [predicate evaluateWithObject:insertedObject]) {
			NSManagedObjectID *objectID = [insertedObject objectID];
			NSUInteger objectIndex = [self _indexOfFetchedID:objectID];
			if (objectIndex == NSNotFound) {
				NSDictionary *contentChange = @{kContentChangeObjectKey : insertedObject, kContentChangeUpdateTypeKey : @(GFFetchedResultsChangeInsert)};
				[insertsInfo addObject:contentChange];
				
				if (_flags._hasSections) {
					NSString *sectionName = [self _sectionNameForObject:insertedObject];
					if (sectionName) {
						if (_sectionsByName[sectionName] == nil) {
							[newSectionNames addObject:sectionName];
						}
					}
				}
			}
		}
	}
}

- (BOOL)_postprocessInsertedObjects:(NSArray *)insertInfos
{
	NSArray *sortDescriptors = self.fetchRequest.sortDescriptors;
	for (NSDictionary *insertInfo in insertInfos) {
		id insertedObject = insertInfo[kContentChangeObjectKey];
		_GFDefaultSectionInfo *sectionInfo;
		if (_flags._hasSections) {
			NSString *sectionName = [self _sectionNameForObject:insertedObject];
			if (sectionName) {
				sectionInfo = _sectionsByName[sectionName];
			}
		} else {
			sectionInfo = [_sections lastObject];
		}
		
		if (!sectionInfo) {
			sectionInfo = [self _createNewSectionForObject:insertedObject];
		}
		
		NSUInteger numberOfObjects = sectionInfo.numberOfObjects;
		NSUInteger sectionOffset = sectionInfo.sectionOffset;
		
		NSUInteger insertIndex = [GFFetchedResultsController _insertIndexForObject:insertedObject inArray:self.fetchedObjects lowIdx:sectionOffset highIdx:(sectionOffset + numberOfObjects) sortDescriptors:sortDescriptors];
		[self _insertObjectInFetchedObjects:insertedObject atIndex:insertIndex];
		sectionInfo.numberOfObjects = sectionInfo.numberOfObjects + 1;
		[self _updateSectionOffsetsStartingAtSection:sectionInfo];
	}
	
	return YES;
}

#pragma mark - Deletion Helpers

- (void)_preprocessDeletedObjects:(NSSet *)deletedObjects deletesInfo:(NSMutableArray *)deletesInfo sectionsWithDeletes:(NSMutableDictionary *)sectionsWithDeletes
{
	for (NSManagedObject *deletedObject in deletedObjects) {
		NSManagedObjectID *objectID = [deletedObject objectID];
		NSUInteger objectIndex = [self _indexOfFetchedID:objectID];
		if (objectIndex != NSNotFound) {
			NSMutableDictionary *contentChange = [[NSMutableDictionary alloc] init];
			contentChange[kContentChangeObjectKey] = deletedObject;
			contentChange[kContentChangeUpdateTypeKey] = @(GFFetchedResultsChangeDelete);
			
			NSIndexPath *indexPath = [self _indexPathForIndex:objectIndex];
			if (indexPath) {
				contentChange[kContentChangeOldIndexPathKey] = indexPath;
				_GFDefaultSectionInfo *sectionInfo = _sections[[indexPath indexAtPosition:0]];
				contentChange[kContentChangeSectionInfoKey] = sectionInfo;
				if (_flags._hasSections) {
					sectionInfo.oldSectionNumber = sectionInfo.sectionNumber;
					sectionsWithDeletes[sectionInfo.name] = sectionInfo;
				}
			}
			
			[deletesInfo addObject:contentChange];
		}
	}
}

- (BOOL)_postprocessDeletedObjects:(NSArray *)deleteInfos
{
	for (NSDictionary *deleteInfo in deleteInfos) {
		NSManagedObject *deletedObject = deleteInfo[kContentChangeObjectKey];
		_GFDefaultSectionInfo *sectionInfo = deleteInfo[kContentChangeSectionInfoKey];
		
		NSUInteger sectionOffsetIndex = NSNotFound;
		
		if (sectionInfo) {
			sectionOffsetIndex = [sectionInfo indexOfObject:deletedObject];
		}
		
		if (sectionOffsetIndex == NSNotFound) {
			NSManagedObjectID *deletedObjectId = [deletedObject objectID];
			NSUInteger deletionIndex = [self _indexOfFetchedID:deletedObjectId];
			if (deletionIndex != NSNotFound) {
				NSUInteger sectionNumber = [self _sectionNumberForIndex:deletionIndex];
				if (sectionNumber != NSNotFound) {
					sectionInfo = _sections[sectionNumber];
					sectionOffsetIndex = [sectionInfo indexOfObject:deletedObject];
				}
			} else {
				continue;
			}
		}
		
		if (sectionInfo && sectionOffsetIndex != NSNotFound) {
			[self _removeObjectInFetchedObjectsAtIndex:sectionInfo.sectionOffset + sectionOffsetIndex];
			sectionInfo.numberOfObjects = sectionInfo.numberOfObjects - 1;
			[self _updateSectionOffsetsStartingAtSection:sectionInfo];
		}
		
		if (sectionInfo) {
			NSUInteger numberOfObjects = sectionInfo.numberOfObjects;
			if (numberOfObjects == 0 && _flags._hasSections) {
				[_sections removeObjectAtIndex:sectionInfo.sectionNumber];
				[_sectionsByName removeObjectForKey:sectionInfo.name];
				[sectionInfo setController:nil];
				[sectionInfo clearSectionObjectsCache];
				_sectionIndexTitles = nil;
				//_sectionIndexTitlesSections = nil;
			}
		}
	}
	
	return YES;
}

#pragma mark - Update Helpers

// TODO: !!!
- (void)_preprocessUpdatedObjects:(NSSet *)updatedObjects insertsInfo:(NSMutableArray *)insertsInfo deletesInfo:(NSMutableArray *)deletesInfo updatesInfo:(NSMutableArray *)updatesInfo sectionsWithDeletes:(NSMutableDictionary *)sectionsWithDeletes newSectionNames:(NSMutableSet *)newSectionNames treatAsRefreshes:(BOOL)treatAsRefreshes
{
	NSPredicate *predicate = self.fetchRequest.predicate;
	//NSSet *sortKeys = [NSSet setWithArray:[self.fetchRequest.sortDescriptors valueForKey:@"key"]];
	
	for (NSManagedObject *updatedObject in updatedObjects) {
		NSMutableDictionary *contentChange = [[NSMutableDictionary alloc] init];
		contentChange[kContentChangeObjectKey] = updatedObject;
		
		NSManagedObjectID *objectID = [updatedObject objectID];
		NSUInteger objectIndex = [self _indexOfFetchedID:objectID];
		
		BOOL containsObject = objectIndex != NSNotFound;
		BOOL predicateEvaluates = predicate == nil || [predicate evaluateWithObject:updatedObject];
		
		if (containsObject) {
			// Object already in list
			NSIndexPath *currentIndexPath = [self _indexPathForIndex:objectIndex];
			if (currentIndexPath) {
				contentChange[kContentChangeOldIndexPathKey] = currentIndexPath;
			}
			
			if (!predicateEvaluates) {
				// Object no longer matches predicate
				// TODO: this is the same as the inner body of _preprocessDeletedObjects
				
				contentChange[kContentChangeUpdateTypeKey] = @(GFFetchedResultsChangeDelete);
				
				if (currentIndexPath) {
					_GFDefaultSectionInfo *sectionInfo = _sections[[currentIndexPath indexAtPosition:0]];
					contentChange[kContentChangeSectionInfoKey] = sectionInfo;
					if (_flags._hasSections) {
						sectionInfo.oldSectionNumber = sectionInfo.sectionNumber;
						sectionsWithDeletes[sectionInfo.name] = sectionInfo;
					}
				}
				[deletesInfo addObject:contentChange];
			} else {
				// XXX: this might only work on NSManagedObjectContextObjectsDidChangeNotification where changedValuesForCurrentEvent might work better
				
				BOOL sortingChanged = NO;
				for (NSString *key in [[updatedObject changedValues] allKeys]) {
					NSLog(@"-----%@", key);
					if ([_sortKeys containsObject:key]) {
						sortingChanged = YES;
						break;
					}
				}
				
				NSUInteger currentSectionIndex = [currentIndexPath indexAtPosition:0];
				_GFDefaultSectionInfo *currentSection = _sections[currentSectionIndex];
				
				// TODO: if not using sections determine if sorting order actually changed
				
				if (sortingChanged) {
					// moved object
					contentChange[kContentChangeUpdateTypeKey] = @(GFFetchedResultsChangeMove);
					contentChange[kContentChangeOldIndexPathKey] = currentIndexPath;
					
					if (_flags._hasSections) {
						NSString *newSectionName = [self _sectionNameForObject:updatedObject];
						if (newSectionName) {
							_GFDefaultSectionInfo *section = _sectionsByName[newSectionName];
							if (section == nil) {
								[newSectionNames addObject:newSectionName];
							} else {
								if (![currentSection.name isEqualToString:newSectionName]) {
									contentChange[kContentChangeDidChangeSectionsKey] = @YES;
									sectionsWithDeletes[currentSection.name] = currentSection;
									currentSection.oldSectionNumber = section.sectionNumber;
									_sectionsByName[currentSection.name] = currentSection;
								}
							}
						}
					}
				} else {
					// updated object
					contentChange[kContentChangeUpdateTypeKey] = @(GFFetchedResultsChangeUpdate);
				}
			}
			
			
		} else if (predicateEvaluates) {
			// Object wasn't in list but is now
			contentChange[kContentChangeUpdateTypeKey] = @(GFFetchedResultsChangeInsert);
			
			// TODO: below is the same as in _preprocessInsertedObjects
			if (_flags._hasSections) {
				NSString *sectionName = [self _sectionNameForObject:updatedObject];
				if (sectionName) {
					if (_sectionsByName[sectionName] == nil) {
						[newSectionNames addObject:sectionName];
					}
				}
			}
		} else {
			continue;
		}
		
		[updatesInfo addObject:contentChange];
	}
}

- (BOOL)_postprocessUpdatedObjects:(NSArray *)updateInfos
{
	for (NSDictionary *updateInfo in updateInfos) {
		NSNumber *changeType = updateInfo[kContentChangeUpdateTypeKey];
		id changedObject = updateInfo[kContentChangeObjectKey];
		if ([changeType unsignedIntegerValue] == GFFetchedResultsChangeMove) {
			if (![self _postprocessDeletedObjects:@[updateInfo]]) {
				NSLog(@"CoreData: error: (UMFetchedRequestController) error moving object %@ from old location", changedObject);
			}
			if (![self _postprocessInsertedObjects:@[updateInfo]]) {
				NSLog(@"CoreData: error: (UMFetchedRequestController) error moving object %@ to new location", changedObject);
			}
		} else {
			
		}
	}
	
	return YES;
}

#pragma mark - Section Helpers

- (void)_updateSectionOffsetsStartingAtSection:(_GFDefaultSectionInfo *)sectionInfo
{
	NSUInteger sectionCount = [_sections count]; //7
	NSUInteger sectionNumber = sectionInfo.sectionNumber; //3
	// 0, 1, 2, 3, 4, 5, 6
	
	if (sectionNumber + 1 < sectionCount) {
		__block _GFDefaultSectionInfo *previousSection = sectionInfo;
		for (NSUInteger i = sectionNumber + 1; i < sectionCount; ++i) {
			_GFDefaultSectionInfo *currentSection = _sections[i];
			currentSection.sectionOffset = previousSection.sectionOffset + previousSection.numberOfObjects;
			previousSection = currentSection;
		}
	}
}

- (NSUInteger)_sectionNumberForIndex:(NSUInteger)idx
{
	NSUInteger sectionNumber = NSNotFound;
	for (_GFDefaultSectionInfo *sectionInfo in _sections) {
		NSUInteger sectionOffset = sectionInfo.sectionOffset;
		NSUInteger numberOfObjects = sectionInfo.numberOfObjects;
		if (sectionOffset + numberOfObjects > idx) {
			sectionNumber = sectionInfo.sectionNumber;
			break;
		}
	}
	return sectionNumber;
}

- (BOOL)_computeSectionInfoWithGroupBy:(NSArray *)objects error:(NSError **)error
{
	if ([_managedObjectContext hasChanges]) {
		if ([_fetchRequest includesPendingChanges]) {
			
		}
	}
	
	NSString *sectionNameKeyPath = [self sectionNameKeyPath];
	if (!sectionNameKeyPath) {
		return NO;
	}
	
	NSFetchRequest *fetchRequest = [[self fetchRequest] copy];
	[fetchRequest setResultType:NSDictionaryResultType];
	[fetchRequest setIncludesPropertyValues:YES];
	[fetchRequest setFetchBatchSize:0];
	
	NSExpression *distinct = [NSExpression expressionForFunction:@"distinct:" arguments:@[[NSExpression expressionForEvaluatedObject]]];
	NSExpression *count = [NSExpression expressionForFunction:@"count:" arguments:@[distinct]];
	
	NSExpressionDescription *countExpressionDescription = [[NSExpressionDescription alloc] init];
	[countExpressionDescription setExpression:count];
	[countExpressionDescription setName:@"sectionCount"];
	[countExpressionDescription setExpressionResultType:NSInteger32AttributeType];
	
	[fetchRequest setPropertiesToGroupBy:@[sectionNameKeyPath]];
	[fetchRequest setPropertiesToFetch:@[sectionNameKeyPath, countExpressionDescription]];
	
	if ([[fetchRequest sortDescriptors] count] == 0) {
		NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:sectionNameKeyPath ascending:YES];
		[fetchRequest setSortDescriptors:@[sortDescriptor]];
	}
	
	NSError *fetchError;
	NSArray *results = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
	if (results) {
		NSUInteger offset = 0;
		for (NSDictionary *result in results) {
			NSNumber *sectionCount = result[@"sectionCount"];
			NSString *sectionName = [result[sectionNameKeyPath] description];
			
			if (sectionName == nil) {
				NSLog(@"CoreData: error: (NSFetchedResultsController) A section returned nil value for section name key path '%@'. Objects will be placed in unnamed section", _sectionNameKeyPath);
				sectionName = @"";
			}
			
			_GFDefaultSectionInfo *sectionInfo = _sectionsByName[sectionName];
			if (sectionInfo) {
				
			} else {
				NSString *indexTitle = [self _resolveSectionIndexTitleForSectionName:sectionName];
				_GFDefaultSectionInfo *sectionInfo = [[_GFDefaultSectionInfo alloc] initWithController:self name:sectionName indexTitle:indexTitle sectionOffset:offset];
				sectionInfo.numberOfObjects = [sectionCount unsignedIntegerValue];
				[_sections addObject:sectionInfo];
				_sectionsByName[sectionName] = sectionInfo;
			}
			offset += [sectionCount unsignedIntegerValue];
		}
	} else {
		NSLog(@"CoreData: error: Fetching ERROR during section computation with request = %@ and error = %@ and userInfo = %@", fetchRequest, fetchError, [fetchError userInfo]);
	}
	
	
	return YES;
}

- (BOOL)_computeSectionInfo:(NSArray *)objects error:(NSError **)error
{
	NSUInteger objectsCount = [objects count];
	_sections = [[NSMutableArray alloc] init];
	_sectionsByName = [[NSMutableDictionary alloc] init];
	_sectionIndexTitles = nil;
	//	_sectionIndexTitlesSections = nil;
	
	if (objectsCount > 0) {
		if (_flags._hasSections) {
			if ([self _computeSectionInfoWithGroupBy:objects error:error]) {
				return YES;
			}
			
			if (_fetchRequest.resultType == NSDictionaryResultType) {
				id obj = objects[0];
				NSString *sectionName = [self _sectionNameForObject:obj];
				
				if (sectionName == nil) {
					NSLog(@"CoreData: error: (NSFetchedResultsController) object %@ returned nil value for section name key path '%@'. Object will be placed in unnamed section", obj, _sectionNameKeyPath);
					sectionName = @"";
				}
				
				NSString *sectionIndexTitle = [self _resolveSectionIndexTitleForSectionName:sectionName];
				
				_GFDefaultSectionInfo *sectionInfo = [[_GFDefaultSectionInfo alloc] initWithController:self name:sectionName indexTitle:sectionIndexTitle sectionOffset:0];
				[_sections addObject:sectionInfo];
				_sectionsByName[sectionName] = sectionInfo;
				
				if (objectsCount < 2) {
					[sectionInfo setNumberOfObjects:1];
					return YES;
				} else {
					//goto loc_1120fd
					obj = objects[1];
					NSString *otherSectionName = [self _sectionNameForObject:obj];
					if (otherSectionName == nil) {
						NSLog(@"CoreData: error: (NSFetchedResultsController) object %@ returned nil value for section name key path '%@'. Object will be placed in unnamed section", obj, _sectionNameKeyPath);
						sectionName = @"";
					}
					if (![otherSectionName isEqualToString:sectionName]) {
						//goto loc_1121a0
					} else {
						//goto loc_11218f;
					}
				}
			} else {
				
			}
		} else {
			_GFDefaultSectionInfo *sectionInfo = [[_GFDefaultSectionInfo alloc] initWithController:self name:nil indexTitle:nil sectionOffset:0];
			sectionInfo.numberOfObjects = objectsCount;
			[_sections addObject:sectionInfo];
		}
	}
	
	return YES;
}

- (NSString *)_sectionNameForObject:(id)obj
{
	return [[obj valueForKeyPath:_sectionNameKeyPath] description];
}

- (NSString *)_resolveSectionIndexTitleForSectionName:(NSString *)sectionName
{
	NSString *title;
	if (_flags._sendSectionIndexTitleForSectionName) {
		title = [self.delegate controller:self sectionIndexTitleForSectionName:sectionName];
	} else {
		title = [self sectionIndexTitleForSectionName:sectionName];
	}
	return title;
}

- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName
{
	if (sectionName == nil || [sectionName length] == 0) {
		return nil;
	}
	
	return [[NSString stringWithFormat:@"%C", [sectionName characterAtIndex:0]] uppercaseString];
}

- (_GFDefaultSectionInfo *)_createNewSectionForObject:(id)obj
{
	_GFDefaultSectionInfo *section;
	if (_flags._hasSections) {
		NSString *sectionName = [self _sectionNameForObject:obj];
		if (!sectionName) {
			NSLog(@"CoreData: error: (UMFetchedResultsController) object %@ returned nil value for section name key path '%@'. Object will be placed in unnamed section", obj, _sectionNameKeyPath);
			sectionName = @"";
		}
		NSString *sectionIndexTitle = [self _resolveSectionIndexTitleForSectionName:sectionName];
		
		NSMutableArray *sectionFirstObjects = [[NSMutableArray alloc] init];
		for (_GFDefaultSectionInfo *existingSection in _sections) {
			NSUInteger sectionOffset = existingSection.sectionOffset;
			id fetchedObj = [_fetchedObjects objectAtIndex:sectionOffset];
			[sectionFirstObjects addObject:fetchedObj];
		}
		
		NSUInteger insertIndex = [GFFetchedResultsController _insertIndexForObject:obj inArray:sectionFirstObjects lowIdx:0 highIdx:[sectionFirstObjects count] sortDescriptors:_fetchRequest.sortDescriptors];
		
		NSUInteger sectionOffset = 0;
		if (insertIndex != 0) {
			_GFDefaultSectionInfo *section = _sections[insertIndex - 1];
			sectionOffset = section.sectionOffset + section.numberOfObjects;
		}
		
		// XXX
		section = [[_GFDefaultSectionInfo alloc] initWithController:self name:sectionName indexTitle:sectionIndexTitle sectionOffset:sectionOffset];
		[_sections insertObject:section atIndex:insertIndex];
		[_sectionsByName setObject:section forKey:section.name];
		_sectionIndexTitles = nil;
		//_sectionIndexTitlesSections = nil;
	} else {
		section = [[_GFDefaultSectionInfo alloc] initWithController:self name:nil indexTitle:nil sectionOffset:0];
		[_sections addObject:section];
	}
	return section;
}

#pragma mark - Other Helpers

- (BOOL)_keyPathContainsNonPersistedProperties:(NSArray *)keyPath
{
	NSEntityDescription *entity = [_fetchRequest gf_resolvedEntityInContext:_managedObjectContext];
	NSDictionary *propertiesByName = [entity propertiesByName];
	for (NSString *key in keyPath) {
		NSPropertyDescription *propertyDescription = propertiesByName[key];
		if ([propertyDescription isTransient]) {
			return YES;
		} else {
			if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
				NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *)propertyDescription;
				entity = [relationshipDescription destinationEntity];
				propertiesByName = [entity propertiesByName];
			}
		}
	}
	return NO;
}

- (BOOL)_objectInResults:(id)obj
{
	if (_flags._hasSections) {
		NSString *sectionName = [obj valueForKeyPath:_sectionNameKeyPath];
		if (!sectionName) {
			return NO;
		}
	}
	
	NSPredicate *predicate = self.fetchRequest.predicate;
	return predicate ? [predicate evaluateWithObject:obj] : YES;
}

+ (NSUInteger)_insertIndexForObject:(id)obj inArray:(NSArray *)array lowIdx:(NSUInteger)lowIdx highIdx:(NSUInteger)highIdx sortDescriptors:(NSArray *)sortDescriptors
{
	NSUInteger insertIndex = NSNotFound;
	if (highIdx == lowIdx) {
		insertIndex = lowIdx;
	} else if (highIdx + 1 == lowIdx) {
		insertIndex = lowIdx;
	} else {
		insertIndex = [array indexOfObject:obj
							 inSortedRange:NSMakeRange(lowIdx, highIdx - lowIdx)
								   options:NSBinarySearchingFirstEqual|NSBinarySearchingInsertionIndex
						   usingComparator:^NSComparisonResult(id obj1, id obj2) {
							   NSComparisonResult result = NSOrderedSame;
							   for (NSSortDescriptor *sortDescriptor in sortDescriptors) {
								   result = [sortDescriptor compareObject:obj1 toObject:obj2];
								   if (result != NSOrderedSame) {
									   break;
								   }
							   }
							   return result;
						   }];
	}
	return insertIndex;
}

#pragma mark - _fetchedObjects Helpers

- (void)_removeObjectInFetchedObjectsAtIndex:(NSUInteger)idx
{
	if (!_flags._hasMutableFetchedResults) {
		[self _makeMutableFetchedObjects];
	}
	[(NSMutableArray *)_fetchedObjects removeObjectAtIndex:idx];
}

- (void)_insertObjectInFetchedObjects:(id)obj atIndex:(NSUInteger)insertionIndex
{
	if (_flags._hasMutableFetchedResults == NO) {
		[self _makeMutableFetchedObjects];
	}
	
	[(NSMutableArray *)_fetchedObjects insertObject:obj atIndex:insertionIndex];
}

- (void)_removeObjectAtIndex:(NSUInteger)removalIndex
{
	if (_flags._hasMutableFetchedResults == NO) {
		[self _makeMutableFetchedObjects];
	}
	
	[(NSMutableArray *)_fetchedObjects removeObjectAtIndex:removalIndex];
}

- (void)_makeMutableFetchedObjects
{
	if (_flags._hasMutableFetchedResults == NO) {
		_fetchedObjects = [_fetchedObjects mutableCopy];
		_flags._hasMutableFetchedResults = YES;
	}
}

- (NSIndexPath *)_indexPathForIndex:(NSUInteger)idx
{
	NSIndexPath *indexPath = nil;
	for (_GFDefaultSectionInfo *sectionInfo in _sections) {
		NSUInteger sectionOffset = [sectionInfo sectionOffset];
		NSUInteger numberOfObjects = [sectionInfo numberOfObjects];
		
		if (sectionOffset + numberOfObjects > idx) {
			NSUInteger sectionNumber = [sectionInfo sectionNumber];
			NSUInteger sectionIndex = idx - sectionOffset;
			NSUInteger indexes[2] = {sectionNumber, sectionIndex};
			indexPath = [NSIndexPath indexPathWithIndexes:indexes length:2];
			break;
		}
	}
	return indexPath;
}

#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED)

- (NSIndexPath *)indexPathForTableViewIndex:(NSUInteger)idx
{
	NSIndexPath *indexPath;
	if (_flags._hasSections) {
		NSUInteger sectionNumber = 0;
		NSUInteger objectIndex = NSNotFound;
		if (idx > 0) {
			for (_GFDefaultSectionInfo *sectionInfo in _sections) {
				NSUInteger numberOfObjects = [sectionInfo numberOfObjects];
				if (idx <= numberOfObjects) {
					objectIndex = idx - 1;
					break;
				}
				
				idx -= numberOfObjects + 1;
				sectionNumber += 1;
				
				if (idx == 0) {
					// fell on a section, return nil
					break;
				}
			}
		}
		NSUInteger indexes[2] = {sectionNumber, objectIndex};
		indexPath = [NSIndexPath indexPathWithIndexes:indexes length:2];
	} else {
		indexPath = [self _indexPathForIndex:idx]; // XXX: necessary? maybe just {0, idx} for index path
	}
	return indexPath;
}

- (NSUInteger)numberOfRowsForTableView
{
	NSUInteger numberOfRowsForTableView = 0;
	if (_flags._hasSections) {
		numberOfRowsForTableView = [self.sections count] + [self.fetchedObjects count];
	} else {
		numberOfRowsForTableView = [self.fetchedObjects count];
	}
	return numberOfRowsForTableView;
}

- (id)objectAtIndex:(NSUInteger)idx
{
	NSIndexPath *indexPath = [self indexPathForTableViewIndex:idx];
	if (indexPath) {
		return [self objectAtIndexPath:indexPath];
	}
	return nil;
}

- (BOOL)isSectionAtTableViewIndex:(NSUInteger)idx
{
	NSIndexPath *indexPath = [self indexPathForTableViewIndex:idx];
	return ([indexPath indexAtPosition:1] == NSNotFound);
}

- (id <GFFetchedResultsSectionInfo>)sectionAtTableViewIndex:(NSUInteger)idx
{
	NSIndexPath *indexPath = [self indexPathForTableViewIndex:idx];
	NSUInteger sectionIndex = [indexPath indexAtPosition:0];
	return self.sections[sectionIndex];
}

- (NSUInteger)tableViewRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSUInteger idx = 0;
	if (_flags._hasSections) {
		NSUInteger sectionIndex = [indexPath indexAtPosition:0];
		_GFDefaultSectionInfo *section = _sections[sectionIndex];
		idx = section.sectionOffset + [indexPath indexAtPosition:1];
	} else {
		idx = [indexPath indexAtPosition:1];
	}
	return idx;
}

- (NSUInteger)tableViewRowAtSectionIndex:(NSUInteger)sectionIndex
{
	NSUInteger idx = 0;
	if (_flags._hasSections) {
		_GFDefaultSectionInfo *section = _sections[sectionIndex];
		idx = section.sectionOffset;
	} else {
	}
	return idx;
}

#endif

@end
