//
//  NSObject+AutoreleaseTracking.h
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>

@interface AutoreleaseTracker : NSObject

@property (nonatomic, readonly, assign) NSObject *object;

- (instancetype)initWithObject:(NSObject *)object;

@end

@interface NSObject (AutoreleaseTracking)

/// Returns the autorelease trackers associated with this object
//@property (nonatomic, readonly, strong) NSMutableArray<AutoreleaseTracker *> *autoreleaseTrackers;

/// Enables autorelease tracking by swizzling the autorelease method
+ (void)enableAutoreleaseTracking;

@end 
