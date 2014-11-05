//
//  DemoObject.h
//  GFFetchedResultsControllerDemo
//
//  Created by Geoffrey Foster on 2014-11-04.
//  Copyright (c) 2014 Geoffrey Foster. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DemoObject;

@interface DemoObject : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSNumber * age;
@property (nonatomic, retain) DemoObject *parent;
@property (nonatomic, retain) NSSet *children;
@end

@interface DemoObject (CoreDataGeneratedAccessors)

- (void)addChildrenObject:(DemoObject *)value;
- (void)removeChildrenObject:(DemoObject *)value;
- (void)addChildren:(NSSet *)values;
- (void)removeChildren:(NSSet *)values;

@end
