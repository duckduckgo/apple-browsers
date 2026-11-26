//
//  RecursiveLockWithSideEffectsTests.swift
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

import Common
import XCTest
@testable import BrowserServicesKit

class RecursiveLockWithSideEffectsTests: XCTestCase {

    func testWhenLockIsHeldByConcurrentThread_otherThreadWaitsAndSideEffectsAreIsolated() {
        let lock = RecursiveLockWithSideEffects()
        let thread1Started = expectation(description: "Thread 1 started")
        let thread2Started = expectation(description: "Thread 2 started")
        let thread1Done = expectation(description: "Thread 1 done")
        let thread2Done = expectation(description: "Thread 2 done")

        let thread1SideEffectCalled = Locked(wrappedValue: false)
        let thread2SideEffectCalled = Locked(wrappedValue: false)
        let sharedValue = Locked(wrappedValue: 0)

        // Thread 1 - Takes lock first and holds it
        DispatchQueue.global().async {
            XCTAssertFalse(lock.isLocked)
            lock.withLock {
                thread1Started.fulfill()
                XCTAssertEqual(XCTWaiter.wait(for: [thread2Started], timeout: 1), .completed)

                lock.dispatchSideEffect {
                    thread1SideEffectCalled.wrappedValue = true
                }

                sharedValue.wrappedValue = 42
                Thread.sleep(forTimeInterval: 0.1) // Hold lock to ensure thread 2 has to wait

                XCTAssertEqual(sharedValue.wrappedValue, 42)
                XCTAssertFalse(thread1SideEffectCalled.wrappedValue)
                XCTAssertFalse(thread2SideEffectCalled.wrappedValue)
            }
            XCTAssertTrue(thread1SideEffectCalled.wrappedValue)
            thread1Done.fulfill()
        }

        // Thread 2 - Has to wait for lock
        DispatchQueue.global().async {
            XCTAssertEqual(XCTWaiter.wait(for: [thread1Started], timeout: 1), .completed)
            thread2Started.fulfill()
            XCTAssertFalse(lock.isLocked)
            lock.withLock {
                XCTAssertEqual(sharedValue.wrappedValue, 42)
                lock.dispatchSideEffect {
                    thread2SideEffectCalled.wrappedValue = true
                }

                sharedValue.wrappedValue = 99

                XCTAssertEqual(sharedValue.wrappedValue, 99)
                XCTAssertFalse(thread2SideEffectCalled.wrappedValue)
            }

            XCTAssertTrue(thread2SideEffectCalled.wrappedValue)
            thread2Done.fulfill()
        }

        wait(for: [thread1Done, thread2Done], timeout: 1.0)
        XCTAssertEqual(sharedValue.wrappedValue, 99)
        XCTAssertTrue(thread1SideEffectCalled.wrappedValue)
        XCTAssertTrue(thread2SideEffectCalled.wrappedValue)
    }

    func testWhenRecursiveLockIsUnlocked_sideEffectsExecuted() {
        let lock = RecursiveLockWithSideEffects()

        var sideEffect1Called = false
        var sideEffect2Called = false

        lock.withLock {
            lock.dispatchSideEffect {
                sideEffect1Called = true
                XCTAssertFalse(lock.isLocked)
            }

            lock.withLock {
                lock.dispatchSideEffect {
                    sideEffect2Called = true
                    XCTAssertFalse(lock.isLocked)
                }
            }

            XCTAssertFalse(sideEffect1Called)
            XCTAssertFalse(sideEffect2Called)
        }
        XCTAssertTrue(sideEffect1Called)
        XCTAssertTrue(sideEffect2Called)
    }

    func testWhenLockIsLocked_isLockedIsTrue() {
        let lock = RecursiveLockWithSideEffects()
        XCTAssertFalse(lock.isLocked)

        lock.withLock {
            XCTAssertTrue(lock.isLocked)
            lock.withLock {
                XCTAssertTrue(lock.isLocked)
                lock.withLock {
                    XCTAssertTrue(lock.isLocked)
                }
                XCTAssertTrue(lock.isLocked)
            }
            XCTAssertTrue(lock.isLocked)
        }
        XCTAssertFalse(lock.isLocked)
    }

}
