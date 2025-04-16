//
//  NSException+cxxHandler.mm
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#include "NSException+cxxHandler.h"
#include <typeinfo>
#include <cxxabi.h>
#include <exception>

#define DESCRIPTION_BUFFER_LENGTH 1024

#define CATCH_VALUE(TYPE, PRINTFTYPE) \
catch(TYPE value)\
{ \
    snprintf(descriptionBuff, sizeof(descriptionBuff), "%" #PRINTFTYPE, value); \
}

#define CALL_STACK_SYMBOLS_KEY @"callStackSymbols"
#define RESERVED_KEY @"reserved"

extern "C" void captureStackTrace(void* exc, void* tinfo, void (*dest)(void*)) __attribute__((disable_tail_calls)) {
    if (tinfo && strcmp(((std::type_info *)tinfo)->name(), "NSException") == 0) {
        [[[NSThread currentThread] threadDictionary] removeObjectForKey:CALL_STACK_SYMBOLS_KEY];
        return;
    }
    // collect call stack symbols and store to the thread dictionary
    [[[NSThread currentThread] threadDictionary] setObject:[NSThread callStackSymbols] forKey:CALL_STACK_SYMBOLS_KEY];

    __asm__ __volatile__(""); // thwart tail-call optimization
}

// set `std::terminate` handler, returns original handler
extern "C" terminate_handler SetCxxExceptionTerminateHandler(terminate_handler handler) {
    return std::set_terminate(handler);
}

@implementation NSException (CPPException)

// get C++ exception currently handled in the `std::terminate` handler
+ (NSException * _Nullable)currentCxxException {
    const char* name = nil;
    std::type_info* tinfo = __cxxabiv1::__cxa_current_exception_type();
    if (tinfo) {
        name = tinfo->name();
    }
    
    // NSException is handled by NSUncaughtExceptionHandler
    if (name && strcmp(name, "NSException") == 0) {
        return nil;
    }

    char descriptionBuff[DESCRIPTION_BUFFER_LENGTH];
    const char* description = descriptionBuff;
    descriptionBuff[0] = 0;

    try {
        throw;
    } catch(std::exception& exc) {
        strncpy(descriptionBuff, exc.what(), sizeof(descriptionBuff));
    }
    CATCH_VALUE(char,                 d)
    CATCH_VALUE(short,                d)
    CATCH_VALUE(int,                  d)
    CATCH_VALUE(long,                ld)
    CATCH_VALUE(long long,          lld)
    CATCH_VALUE(unsigned char,        u)
    CATCH_VALUE(unsigned short,       u)
    CATCH_VALUE(unsigned int,         u)
    CATCH_VALUE(unsigned long,       lu)
    CATCH_VALUE(unsigned long long, llu)
    CATCH_VALUE(float,                f)
    CATCH_VALUE(double,               f)
    CATCH_VALUE(long double,         Lf)
    CATCH_VALUE(char*,                s)
    catch(...) {
        description = nil;
    }

    // create NSException with C++ exception name and description
    NSException *exception = [[NSException alloc] initWithName:[NSString stringWithCString:name encoding:NSUTF8StringEncoding]
                                                        reason:description != nil ? [NSString stringWithCString:description encoding:NSUTF8StringEncoding] : nil
                                                      userInfo:nil];

    id callStackSymbols = [[[NSThread currentThread] threadDictionary] objectForKey:CALL_STACK_SYMBOLS_KEY];
    if (callStackSymbols) {
        NSMutableDictionary *reserved = [exception valueForKey:RESERVED_KEY];
        if (!reserved) {
            reserved = [NSMutableDictionary dictionary];
            [exception setValue:reserved forKey:RESERVED_KEY];
        }
        [reserved setValue:callStackSymbols forKey:CALL_STACK_SYMBOLS_KEY];
    }

    return exception;
}

// prevent crashes if `NSException` has no `reserved` field
- (id)valueForUndefinedKey:(NSString *)key { return nil; }
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}

@end
