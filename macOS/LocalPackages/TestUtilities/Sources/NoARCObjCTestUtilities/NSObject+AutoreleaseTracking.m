//
//  NSObject+AutoreleaseTracking.m
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

/**
 * @file NSObject+AutoreleaseTracking.m
 * @brief Implementation of autorelease tracking for debugging memory leaks.
 *
 * This file implements the autorelease tracking system that helps debug memory
 * leaks by creating tracker objects that are autoreleased alongside tracked
 * objects. The tracker objects maintain malloc stack traces that can be used
 * to identify where autorelease calls were made.
 */

#import "NSObject+AutoreleaseTracking.h"
#import <objc/runtime.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

static const void *AutoreleaseTrackersKey = &AutoreleaseTrackersKey;

@implementation AutoreleaseTracker

- (instancetype)initWithObject:(NSObject *)object {
    self = [super init];
    if (self) {
        _object = object;
    }
    return self;
}

@end

@implementation NSObject (AutoreleaseTracking)

static IMP originalAutoreleaseIMP = NULL;

+ (void)enableAutoreleaseTracking {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMethod = class_getInstanceMethod([NSObject class], @selector(autorelease));
        Method swizzledMethod = class_getInstanceMethod([NSObject class], @selector(swizzled_autorelease));
        
        originalAutoreleaseIMP = method_getImplementation(originalMethod);
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

- (instancetype)swizzled_autorelease {
    // Call original autorelease implementation
    id result = ((id (*)(id, SEL))originalAutoreleaseIMP)(self, @selector(autorelease));
    
    // Only track NSWindow and NSView objects to avoid excessive tracking
    if (!([self isKindOfClass:[WKWebView class]]
          || [self isKindOfClass:[NSWindow class]]
          || [self isKindOfClass:[NSWindowController class]]
          || [self isKindOfClass:[NSViewController class]]
          || [self isKindOfClass:NSClassFromString(@"TabBarItemCellView")])) {
        return result;
    }
    
    // Create tracker for this autoreleased object
    AutoreleaseTracker *tracker = [[AutoreleaseTracker alloc] initWithObject:self];
    ((id (*)(id, SEL))originalAutoreleaseIMP)(tracker, @selector(autorelease)); // autorelease

    return result;
}

@end 
