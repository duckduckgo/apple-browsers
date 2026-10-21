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

/**
 * @brief A tracker object that maintains a weak reference to an autoreleased object.
 *
 * This class is used internally by the AutoreleaseTracking system to track when
 * and where `[object autorelease]` calls are made. Each tracker is autoreleased
 * alongside the object it tracks, allowing for debugging of autorelease pools.
 */
@interface AutoreleaseTracker : NSObject {
    NSObject *_object;
}

/**
 * @brief Initialize a tracker with the given object.
 * @param object The object to track autorelease calls for.
 * @return A new AutoreleaseTracker instance.
 */
- (instancetype)initWithObject:(NSObject *)object;

@end

/**
 * @brief Extension for tracking autorelease calls on specific object types.
 *
 * This extension provides debugging capabilities for tracking when and where
 * `[object autorelease]` calls are made on specific types of objects. This is
 * particularly useful for debugging memory leaks and understanding autorelease
 * pool behavior in test cases.
 *
 * ## Purpose
 *
 * When objects are "leaked" after test cases end, it can be difficult to determine
 * where the autorelease call that's holding the object was made. This extension
 * creates `AutoreleaseTracker` objects that are autoreleased alongside tracked
 * objects, allowing you to trace back to the original autorelease call site.
 *
 * ## Tracked Object Types
 *
 * Currently tracks autorelease calls for classes defined in NSObject+AutoreleaseTracking.m: `swizzled_autorelease`
 *
 * ## Usage
 *
 * 1. **Enable tracking**: Call `[NSObject enableAutoreleaseTracking]` at the start
 *    of test suite or debugging session (done in TestRunHelper).
 *
 * 2. **Configure Xcode for debugging**:
 *    - Go to Xcode → Product → Scheme → Edit Scheme… (⌘⇧,)
 *    - Select "Test" action
 *    - Go to "Diagnostics" tab
 *    - Check "Malloc Stack Logging" option
 *
 * 3. **When a leak is detected**:
 *    - Open Xcode's Memory Browser (Debug → Debug Memory Browser, or ⌃⌥⇧⌘M)
 *    - Find the leaked object in the memory browser (use Filter at the bottom of the Memory Browser left panel)
 *    - Double-click on the leaked object to focus on it
 *    - Click the "…" button in the top-left corner of the object details
 *    - In the popover with objects referring to the leaked object, search for "AutoreleaseTracker"
 *    - Select some AutoreleaseTracker objects - they'll appear on the memory graph (use Filter at the bottom of the Memory Browser left panel)
 *    - Click on an AutoreleaseTracker to activate it
 *    - In Xcode's right panel, view the malloc stack trace (Debug → Debug Memory Browser → Show Malloc Stack) (⌥⌘3)
 *    - The stack trace will show where the AutoreleaseTracker was instantiated,
 *      which corresponds to where `[object autorelease]` was called on the leaked object
 *
 * ## Implementation Details
 *
 * The extension uses method swizzling to intercept `autorelease` calls. When an
 * object of a tracked type calls `autorelease`, the system:
 * 1. Calls the original `autorelease` implementation
 * 2. Creates an `AutoreleaseTracker` with a weak reference to the object
 * 3. Autoreleases the tracker, placing it in the same autorelease pool
 * 4. The tracker's allocation stack trace can be used to identify the autorelease call site
 */
@interface NSObject (AutoreleaseTracking)

/**
 * @brief Enable autorelease tracking for supported object types.
 *
 * This method sets up method swizzling to intercept autorelease calls.
 * Call this once at the beginning of your test suite or debugging session.
 *
 * @note This method is thread-safe and uses dispatch_once internally.
 */
+ (void)enableAutoreleaseTracking;

/**
 * @brief Swizzled autorelease method (internal use only).
 *
 * This method is used internally by the tracking system. Do not call directly.
 * @return The result of the original autorelease call.
 */
- (instancetype)swizzled_autorelease;

@end 
