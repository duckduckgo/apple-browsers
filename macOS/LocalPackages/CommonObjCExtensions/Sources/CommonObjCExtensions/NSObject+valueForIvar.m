//
//  NSObject+valueForIvar.m
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

#import "include/NSObject+valueForIvar.h"
#import <objc/runtime.h>

@implementation NSObject (valueForIvar)

- (void *)valueForIvar:(NSString *)name {
    Ivar ivar = class_getInstanceVariable(object_getClass(self), [name UTF8String]);
    if (ivar) {
        return (__bridge void *)object_getIvar(self, ivar);
    }
    return nil;
}

@end
