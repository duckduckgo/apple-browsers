//
//  NSException+cxxHandler.h
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

#ifndef NSException_cxxHandler_h
#define NSException_cxxHandler_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*terminate_handler)();

/// Set unhandled C++ exception handler (`std::terminate`)
/// - Returns:original unhandled `std::terminate` pointer
terminate_handler SetCxxExceptionTerminateHandler(terminate_handler);

/// Collect call stack symbols and store to the thread dictionary when handling `std::__cxa_throw` hook
void captureStackTrace(void* _Nullable exc, void* _Nullable tinfo, void (* _Nullable dest)(void*_Nullable)) __attribute__((disable_tail_calls));

#ifdef __cplusplus
}
#endif

@interface NSException (CPPException)

/// Get currently handled C++ exception
/// To be used from the `std::terminate` handler
/// - Returns:`NSException` with:
///  - `name`: C++ exception name
///  - `reason`: exception description
///  - `callStackSymbols`: stack trace where the exception was thrown
/// - Note:`kscm_enableSwapCxaThrow` should be called for stack symbols to be populated
+ (NSException * _Nullable)currentCxxException NS_SWIFT_NAME(currentCxxException());

@end

NS_ASSUME_NONNULL_END

#endif // NSException_cxxHandler_h
