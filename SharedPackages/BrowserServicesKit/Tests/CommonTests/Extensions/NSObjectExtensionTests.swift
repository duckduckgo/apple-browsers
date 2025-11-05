//
//  NSObjectExtensionTests.swift
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

import Foundation
import Testing

@testable import Common

struct NSObjectExtensionTests {

    // MARK: - Test Classes

    private class TestObject: NSObject {
        var testProperty: String = "test"
        lazy var lazyProperty: String = "lazy"
        lazy var optionalLazyProperty: String? = "optional lazy"
        var anon_lazyProperty: String?

        @objc private var privateIvar: String = "private"
        @objc var publicIvar: Int = 123

        var privateIvarValue: String {
            privateIvar
        }

        var onDeinitCalled: (() -> Void)?

        deinit {
            if let callback = onDeinitCalled {
                // Dispatch async to ensure we can verify state after deinit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    callback()
                }
            }
        }
    }

    // MARK: - DeinitObserver Tests

    @Test("DeinitObserver disarm prevents callback execution")
    @MainActor
    func deinitObserverDisarmPreventsCallback() async throws {
        var callbackExecuted = false
        var deinitCalled = false

        try await withTimeout(.seconds(1)) {
            await withCheckedContinuation { continuation in
                autoreleasepool {
                    let testObject = TestObject()
                    testObject.onDeinitCalled = {
                        deinitCalled = true
                        continuation.resume()
                    }

                    // Use onDeinit to get the observer, then disarm it
                    let observer = testObject.onDeinit {
                        callbackExecuted = true
                    }

                    // Disarm the observer before object goes out of scope
                    observer.disarm()

                    // testObject goes out of scope when autoreleasepool ends
                }
            }
        }

        // Deinit should have been called, but callback should NOT have been executed
        #expect(deinitCalled == true)
        #expect(callbackExecuted == false)
    }

    @Test("DeinitObserver executes callback on deinit")
    @MainActor
    func deinitObserverExecutesCallback() async throws {
        var callbackExecuted = false

        try await withTimeout(.seconds(1)) {
            await withCheckedContinuation { continuation in
                autoreleasepool {
                    _=NSObject.DeinitObserver {
                        callbackExecuted = true
                        continuation.resume()
                    }
                    // Observer goes out of scope when autoreleasepool ends
                }
            }
        }

        #expect(callbackExecuted)
    }

    // MARK: - onDeinit Tests

    @Test("onDeinit adds observer and returns it")
    @MainActor
    func onDeinitAddsObserver() {
        let testObject = TestObject()
        var callbackExecuted = false

        let observer = testObject.onDeinit {
            callbackExecuted = true
        }

        #expect(testObject.deinitObservers.count == 1)
        #expect(testObject.deinitObservers.contains(observer))
        #expect(callbackExecuted == false) // Should not be executed yet
    }

    @Test("onDeinit with DeinitObserver reuses existing observer")
    @MainActor
    func onDeinitReusesDeinitObserver() {
        let observer = NSObject.DeinitObserver()
        var callbackExecuted = false

        let returnedObserver = observer.onDeinit {
            callbackExecuted = true
        }

        #expect(returnedObserver === observer)
        #expect(callbackExecuted == false) // Should not be executed yet
    }

    @Test("multiple onDeinit calls create multiple observers")
    @MainActor
    func multipleOnDeinitCalls() {
        let testObject = TestObject()
        var callback1Executed = false
        var callback2Executed = false

        testObject.onDeinit {
            callback1Executed = true
        }

        testObject.onDeinit {
            callback2Executed = true
        }

        #expect(testObject.deinitObservers.count == 2)
        #expect(callback1Executed == false) // Should not be executed yet
        #expect(callback2Executed == false) // Should not be executed yet
    }

    // MARK: - deinitObservers Tests

    @Test("deinitObservers getter returns empty set initially")
    @MainActor
    func deinitObserversInitiallyEmpty() {
        let testObject = TestObject()
        #expect(testObject.deinitObservers.isEmpty)
    }

    @Test("deinitObservers setter stores observers")
    @MainActor
    func deinitObserversStoresObservers() {
        let testObject = TestObject()
        let observer1 = NSObject.DeinitObserver()
        let observer2 = NSObject.DeinitObserver()
        let observers: Set<NSObject.DeinitObserver> = [observer1, observer2]

        testObject.deinitObservers = observers

        #expect(testObject.deinitObservers.count == 2)
        #expect(testObject.deinitObservers.contains(observer1))
        #expect(testObject.deinitObservers.contains(observer2))
    }

    // MARK: - ensureObjectDeallocated Tests

    @Test("ensureObjectDeallocated sets up deallocation check")
    @MainActor
    func ensureObjectDeallocatedSetsUpCheck() {
        let testObject = TestObject()
        var actionExecuted = false

        let customAction = NSObject.DeallocationCheckAction { _ in
            actionExecuted = true
        }

        testObject.ensureObjectDeallocated(after: 0, do: customAction)

        // The observer should be added
        #expect(testObject.deinitObservers.count == 1)
        // Action should not be executed yet (object not deallocated)
        #expect(actionExecuted == false)
    }

    @Test("assertObjectDeallocated calls ensureObjectDeallocated")
    @MainActor
    func assertObjectDeallocatedCallsEnsure() {
        let testObject = TestObject()

        testObject.assertObjectDeallocated(after: 0)

        // Should add an observer for the assertion
        #expect(testObject.deinitObservers.count == 1)
    }

    // MARK: - isLazyVar Tests

    @Test("isLazyVar returns false for uninitialized lazy var")
    func isLazyVarReturnsFalseForUninitialized() {
        let testObject = TestObject()

        let isInitialized = isLazyVar(named: "lazyProperty", initializedIn: testObject)

        #expect(isInitialized == false)
    }

    @Test("isLazyVar returns true for initialized lazy var")
    func isLazyVarReturnsTrueForInitialized() {
        let testObject = TestObject()

        // Access the lazy property to initialize it
        _ = testObject.lazyProperty

        let isInitialized = isLazyVar(named: "lazyProperty", initializedIn: testObject)

        #expect(isInitialized == true)
    }

    @Test("isLazyVar correctly distinguishes non-lazy properties")
    func isLazyVarDistinguishesNonLazyProperties() {
        let testObject = TestObject()

        // Set the non-lazy property
        testObject.anon_lazyProperty = "not lazy"

        // Check that non-lazy property triggers failure callback
        var failureCalled = false
        let nonLazyIsInitialized = isLazyVar(named: "anon_lazyProperty", initializedIn: testObject, failure: { _ in
            failureCalled = true
        })
        #expect(nonLazyIsInitialized == false)
        #expect(failureCalled == true)

        // Verify actual lazy property still works correctly
        let lazyIsInitialized = isLazyVar(named: "lazyProperty", initializedIn: testObject)
        #expect(lazyIsInitialized == false)

        // Access lazy property and verify it's now detected as initialized
        _ = testObject.lazyProperty
        let lazyIsInitializedAfterAccess = isLazyVar(named: "lazyProperty", initializedIn: testObject)
        #expect(lazyIsInitializedAfterAccess == true)

        // Non-lazy property should still trigger failure callback
        var failureCalled2 = false
        let nonLazyStillNotLazy = isLazyVar(named: "anon_lazyProperty", initializedIn: testObject, failure: { _ in
            failureCalled2 = true
        })
        #expect(nonLazyStillNotLazy == false)
        #expect(failureCalled2 == true)
    }

    @Test("isLazyVar handles nil non-lazy property correctly")
    func isLazyVarHandlesNilNonLazyProperty() {
        let testObject = TestObject()

        // anon_lazyProperty is nil by default
        #expect(testObject.anon_lazyProperty == nil)

        // Should trigger failure callback even when nil
        var failureCalled = false
        let isInitialized = isLazyVar(named: "anon_lazyProperty", initializedIn: testObject, failure: { _ in
            failureCalled = true
        })
        #expect(isInitialized == false)
        #expect(failureCalled == true)

        // Set to nil explicitly
        testObject.anon_lazyProperty = nil

        // Still should trigger failure callback
        var failureCalled2 = false
        let stillNotLazy = isLazyVar(named: "anon_lazyProperty", initializedIn: testObject, failure: { _ in
            failureCalled2 = true
        })
        #expect(stillNotLazy == false)
        #expect(failureCalled2 == true)
    }

    @Test("isLazyVar returns false for uninitialized optional lazy var")
    func isLazyVarReturnsFalseForUninitializedOptionalLazy() {
        let testObject = TestObject()

        let isInitialized = isLazyVar(named: "optionalLazyProperty", initializedIn: testObject)

        #expect(isInitialized == false)
    }

    @Test("isLazyVar returns true for initialized optional lazy var")
    func isLazyVarReturnsTrueForInitializedOptionalLazy() {
        let testObject = TestObject()

        // Access the optional lazy property to initialize it
        _ = testObject.optionalLazyProperty

        let isInitialized = isLazyVar(named: "optionalLazyProperty", initializedIn: testObject)

        #expect(isInitialized == true)
    }

}
