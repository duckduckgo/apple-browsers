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

import XCTest
@testable import BrowserServicesKit

class RecursiveLockWithSideEffectsTests: XCTestCase {

    func testWhenLockIsHeldByConcurrentThread_otherThreadWaitsAndSideEffectsAreIsolated() {
        let lock = RecursiveLockWithSideEffects()
        let thread1Started = expectation(description: "Thread 1 started")
        let thread2Started = expectation(description: "Thread 2 started")
        let thread1Done = expectation(description: "Thread 1 done")
        let thread2Done = expectation(description: "Thread 2 done")

        var thread1SideEffectCalled = false
        var thread2SideEffectCalled = false
        var sharedValue = 0

        // Thread 1 - Takes lock first and holds it
        DispatchQueue.global().async {
            XCTAssertFalse(lock.isLocked)
            lock.withLock {
                thread1Started.fulfill()
                self.wait(for: [thread2Started], timeout: 1)

                lock.dispatchSideEffect {
                    thread1SideEffectCalled = true
                }

                sharedValue = 42
                Thread.sleep(forTimeInterval: 0.1) // Hold lock to ensure thread 2 has to wait

                XCTAssertEqual(sharedValue, 42)
                XCTAssertFalse(thread1SideEffectCalled)
                XCTAssertFalse(thread2SideEffectCalled)
            }
            XCTAssertTrue(thread1SideEffectCalled)
            thread1Done.fulfill()
        }

        // Thread 2 - Has to wait for lock
        DispatchQueue.global().async {
            self.wait(for: [thread1Started], timeout: 1)
            thread2Started.fulfill()
            XCTAssertFalse(lock.isLocked)
            lock.withLock {
                XCTAssertEqual(sharedValue, 42)
                lock.dispatchSideEffect {
                    thread2SideEffectCalled = true
                }

                sharedValue = 99

                XCTAssertEqual(sharedValue, 99)
                XCTAssertFalse(thread2SideEffectCalled)
            }

            XCTAssertTrue(thread2SideEffectCalled)
            thread2Done.fulfill()
        }

        wait(for: [thread1Done, thread2Done], timeout: 1.0)
        XCTAssertEqual(sharedValue, 99)
        XCTAssertTrue(thread1SideEffectCalled)
        XCTAssertTrue(thread2SideEffectCalled)
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
