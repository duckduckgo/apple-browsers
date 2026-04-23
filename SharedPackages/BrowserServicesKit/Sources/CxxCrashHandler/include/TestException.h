//
//  TestException.h
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

#ifndef TESTEXCEPTION_H
#define TESTEXCEPTION_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Throw C++ test exception with the provided message (used for debug purpose)
void _throwTestCppException(NSString *message);

/// Call `+[NSException currentCxxException]` from inside a C++ catch block that has an
/// active `std::runtime_error`.  The only way to drive the `throw;` branch inside
/// `currentCxxException` safely — a catch context is required for `__cxa_rethrow` to work
/// without re-triggering `std::terminate`.
NSException * _Nullable _currentCxxExceptionInsideCatchBlock(void);

/// Simulate the full `__cxa_throw` hook → terminate-handler flow without actually crashing:
///
///  1. Calls `captureStackTrace` with the real `std::type_info` of the exception **before**
///     throwing, so the thread dictionary gets the stack from the throw site.
///  2. Throws the exception into a `catch(...)` block.
///  3. From the catch block calls `+[NSException currentCxxException]`, which reads the
///     stored stack from the thread dictionary and attaches it to the returned NSException.
///  4. Returns that NSException and (via `outThrowSiteStack`) the raw stack that was
///     stored at throw time — so the test can compare the two.
///
/// Use this to verify that `callStackSymbols` on the returned exception comes from
/// the throw site, not from the catch block / handler frame.
NSException * _Nullable _currentCxxExceptionWithCapturedThrowSiteStack(NSArray<NSString *> * _Nullable * _Nonnull outThrowSiteStack);

/// Reproduce the concrete crash scenario introduced by commit ab01ecc697:
/// throws an instance of a *real* ObjC subclass of NSException (`TestNSExceptionSubclass`)
/// so that `__cxa_current_exception_type()->name()` returns `"TestNSExceptionSubclass"`,
/// not `"NSException"`.  This is the key distinction: using
/// `[NSException exceptionWithName:NSRangeException ...]` would NOT reproduce the bug
/// because that object is still class `NSException` and `tinfo->name()` would equal
/// `"NSException"`, which the old strcmp check would have matched.
///
/// The old vtable-unaware check (`strcmp(name, "NSException") == 0`) returned NO for any
/// true subclass, so the function fell through to `throw;` — which on Apple's libc++abi
/// triggered another std::terminate, starting the infinite recursion.
///
/// The new `isObjCException()` vtable check must return YES for any ObjC exception class
/// (the vtable pointer `objc_ehtype_vtable` is shared across all ObjC exception types),
/// so `currentCxxException()` returns nil without ever reaching `throw;`.
///
/// Returns whatever `currentCxxException()` returns when a real ObjC NSException subclass
/// is the active current exception.
NSException * _Nullable _currentCxxExceptionForObjCExceptionSubclass(void);

/// Measures how many times the `std::terminate` handler fires when
/// `+[NSException currentCxxException]` is called from inside it with an active
/// ObjC NSException *subclass* (no catch context).
///
/// This is the exact runtime state of the original crash:
///   - A real `TestNSExceptionSubclass : NSException` is thrown through a `noexcept`
///     boundary → `std::terminate` is called.
///   - A custom terminate handler calls `currentCxxException()`, mirroring
///     `handleTerminateOnCxxException` (without the `isHandlingTermination` guard,
///     to measure raw recursion depth).
///   - A `longjmp` escape prevents the test runner from crashing.
///
/// Returns 1 if no recursion (isObjCException() fix present — returns nil before `throw;`).
/// Returns > 1 if recursion occurred:
///   - Darwin 25+ / iOS: `throw;` with no catch context re-triggers `std::terminate`
///     natively, incrementing the counter on each re-entrant handler call.
///   - macOS (test host): `throw;` rethrows into currentCxxException's own
///     `catch(NSException*)` block; the handler detects the non-nil return value
///     and simulates the recursive call itself, giving the same >1 result.
int _measureTerminateRecursionDepth(void);

#ifdef __cplusplus
}
#endif

#endif // TESTEXCEPTION_H
