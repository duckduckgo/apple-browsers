//
//  TestException.mm
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

#include "TestException.h"
#include "NSException+cxxHandler.h"

#include <stdexcept>
#include <string>
#include <exception>
#include <setjmp.h>

// A real ObjC subclass of NSException.
// This is the crucial part: @throw on this object causes __cxa_current_exception_type()
// to return a type_info whose name() is "TestNSExceptionSubclass", NOT "NSException".
// The old strcmp(name, "NSException") check would therefore return NO and fall through
// to throw;, triggering recursive std::terminate.  The new isObjCException() vtable
// check must return YES for this type_info regardless of the subclass name.
@interface TestNSExceptionSubclass : NSException
@end
@implementation TestNSExceptionSubclass
@end

class TestException : public std::exception {
public:
    TestException(const std::string& message) : msg(message) {}
    virtual const char* what() const noexcept override {
        return msg.c_str();
    }

private:
    std::string msg;
};

extern "C" void _throwTestCppException(NSString *message) {
    throw TestException(std::string([message UTF8String]));
}

extern "C" NSException * _Nullable _currentCxxExceptionWithCapturedThrowSiteStack(NSArray<NSString *> * _Nullable * outThrowSiteStack) {
    std::runtime_error exc("test cxx exception with stack");

    // Step 1: Simulate the __cxa_throw hook firing at the throw site.
    // In production this happens via CxaThrowSwapper; here we call captureStackTrace
    // directly with the real type_info so the thread dictionary gets the throw-site stack.
    captureStackTrace(nullptr, (void*)&typeid(exc), nullptr);

    // Step 2: Snapshot what captureStackTrace stored — this IS the throw-site stack.
    *outThrowSiteStack = [[[NSThread currentThread] threadDictionary] objectForKey:@"callStackSymbols"];

    // Step 3: Throw and catch, then ask currentCxxException() to build the NSException.
    // currentCxxException() will read the stored stack from the thread dictionary
    // and attach it to the returned exception via the reserved["callStackSymbols"] key.
    try {
        throw exc;
    } catch (...) {
        NSException *result = [NSException currentCxxException];
        // Clean up so the thread dict doesn't bleed into other tests.
        [[[NSThread currentThread] threadDictionary] removeObjectForKey:@"callStackSymbols"];
        return result;
    }
}

extern "C" NSException * _Nullable _currentCxxExceptionForObjCExceptionSubclass(void) {
    // Throw an actual ObjC NSException *subclass* instance so that
    // __cxa_current_exception_type()->name() returns "TestNSExceptionSubclass",
    // not "NSException".  This is the concrete scenario from the crash report:
    // a real subclass propagated through a noexcept C++ boundary → std::terminate
    // → handleTerminateOnCxxException → currentCxxException() called with the
    // subclass type_info active.
    //
    // Old strcmp check: strcmp("TestNSExceptionSubclass", "NSException") != 0
    //   → fell through to throw; → __cxa_rethrow with no catch context
    //   → std::terminate again → infinite recursion → stack overflow.
    //
    // New isObjCException() vtable check: reads the vtable pointer from type_info
    // and compares it against objc_ehtype_vtable+2, which is shared by ALL ObjC
    // exception classes regardless of their name → returns nil without throw;.
    try {
        @throw [[TestNSExceptionSubclass alloc] initWithName:@"TestNSExceptionSubclass"
                                                      reason:@"simulated NSException subclass"
                                                    userInfo:nil];
    } catch (...) {
        // __cxa_current_exception_type()->name() == "TestNSExceptionSubclass" here,
        // not "NSException" — the old strcmp check would have missed this.
        // isObjCException() must recognise it via vtable and return nil without throw;.
        return [NSException currentCxxException];
    }
}

extern "C" NSException * _Nullable _currentCxxExceptionInsideCatchBlock(void) {
    // Throw a real C++ std::exception so that __cxa_current_exception_type() returns its
    // type_info and the exception is in an *active catch context*.
    //
    // Inside the catch block below, currentCxxException() will:
    //   1. See a non-null tinfo (std::runtime_error) → passes the !tinfo guard
    //   2. isObjCException(tinfo) == false           → passes the ObjC guard
    //   3. Execute `throw;`                           → __cxa_rethrow (the path under test)
    //   4. Catch via catch(std::exception& exc)       → captures exc.what() as the reason
    //
    // This is the only path that exercises the throw; statement without being inside a
    // std::terminate handler (where __cxa_rethrow would re-trigger terminate on Darwin 25+).
    try {
        throw std::runtime_error("test cxx exception");
    } catch (...) {
        return [NSException currentCxxException];
    }
}

// ── Recursion-depth probe ─────────────────────────────────────────────────────
//
// Reproduces the exact runtime conditions of the crash:
//
//   1. An ObjC NSException *subclass* propagates through a `noexcept` C++ boundary
//      → std::terminate is called with the subclass as the active (but *uncaught*)
//      exception.  __cxa_current_exception_type() returns its type_info; however
//      __cxa_begin_catch was never called, so there is no active catch context.
//
//   2. Inside the terminate handler we call +[NSException currentCxxException],
//      mirroring what handleTerminateOnCxxException does in production.
//
//      • With the isObjCException() vtable fix: currentCxxException() detects the
//        ObjC exception type and returns nil without touching `throw;` → the
//        handler fires exactly once (depth == 1).
//
//      • Without the fix (old strcmp check): strcmp("TestNSExceptionSubclass",
//        "NSException") != 0 → code reaches `throw;` → __cxa_rethrow with no catch
//        context → std::terminate fires again → our handler is called recursively
//        → depth grows until the cap (5) is hit.
//
//   3. A longjmp escape prevents the test runner from actually crashing: once the
//      cap is reached we jump back to the setjmp site, restore the original
//      terminate handler, and return the depth.
//
// Returns: number of times the terminate handler fired (1 = no recursion, >1 = bug).

static jmp_buf sTerminateRecursionJmpBuf;
static int     sTerminateCallCount;

static void terminateRecursionProbeHandler() {
    ++sTerminateCallCount;
    if (sTerminateCallCount < 5) {
        // Mirror the body of handleTerminateOnCxxException (without the
        // isHandlingTermination guard so we measure raw recursion depth).
        //
        // Darwin 25+ / iOS: if throw; has no catch context it calls std::terminate
        // again, which re-enters this handler directly — sTerminateCallCount grows
        // naturally until the cap.
        //
        // macOS (test host): throw; rethrows into currentCxxException's own
        // catch(NSException*) block instead of calling std::terminate, so the
        // handler is NOT re-entered by the runtime.  We detect this by checking the
        // return value: a non-nil result means throw; was reached and the exception
        // was rethrown/caught — exactly the path that would recurse on Darwin 25+.
        // In that case we call ourselves to simulate the recursive terminate call.
        NSException *result = [NSException currentCxxException];
        if (result != nil) {
            terminateRecursionProbeHandler(); // simulate what Darwin 25+ does natively
        }
    }
    longjmp(sTerminateRecursionJmpBuf, 1);
}

extern "C" int _measureTerminateRecursionDepth(void) {
    sTerminateCallCount = 0;

    auto savedHandler = std::get_terminate();
    std::set_terminate(terminateRecursionProbeHandler);

    if (setjmp(sTerminateRecursionJmpBuf) == 0) {
        // Throw the ObjC subclass through a noexcept boundary.
        // This triggers std::terminate with the subclass as the active-but-uncaught
        // exception — the exact state the production crash is in.
        []() noexcept {
            @throw [[TestNSExceptionSubclass alloc] initWithName:@"TestNSExceptionSubclass"
                                                          reason:@"recursion depth probe"
                                                        userInfo:nil];
        }();
    }

    std::set_terminate(savedHandler);
    return sTerminateCallCount;
}
