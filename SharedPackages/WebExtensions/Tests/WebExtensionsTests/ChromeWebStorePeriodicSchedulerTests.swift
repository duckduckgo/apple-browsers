//
//  ChromeWebStorePeriodicSchedulerTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import os
import XCTest
@testable import WebExtensions

#if os(macOS)
@available(macOS 15.4, *)
@MainActor
final class ChromeWebStorePeriodicSchedulerTests: XCTestCase {
    func testNativeSchedulerUsesBackgroundQoSAndFlexibleRepeatingInterval() {
        let activity = NativeActivityMock(identifier: "test.extension-updates")
        let scheduler = ChromeWebStorePeriodicScheduler(interval: ChromeWebStoreUpdateCoordinator.defaultCheckInterval, activity: activity)
        XCTAssertEqual(activity.interval, 18000)
        XCTAssertEqual(activity.tolerance, 3600)
        XCTAssertTrue(activity.repeats)
        XCTAssertEqual(activity.qualityOfService, .background)
        XCTAssertEqual(activity.scheduleCount, 0, "Creating the adapter must not schedule an activity")
        scheduler.invalidate()
        XCTAssertEqual(activity.invalidationCount, 1)
    }

    func testNativeCompletionWaitsForAsyncOperationAndRunsExactlyOnce() async throws {
        let activity = NativeActivityMock(identifier: "test.extension-updates")
        let scheduler = ChromeWebStorePeriodicScheduler(interval: 7200, activity: activity)
        let entered = expectation(description: "Background operation suspended")
        let completed = expectation(description: "Native activity completed")
        let gate = OperationGate(entered: entered)
        let completions = OSAllocatedUnfairLock(initialState: [NSBackgroundActivityScheduler.Result]())
        scheduler.schedule {
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(Task.currentPriority, .background)
            await gate.wait()
        }
        let callback = try XCTUnwrap(activity.callback)
        callback { result in
            completions.withLock { $0.append(result) }
            completed.fulfill()
        }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertTrue(completions.withLock { $0.isEmpty }, "The OS completion must wait for the async check")
        await gate.resume()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(completions.withLock { $0 }, [.finished])
        scheduler.invalidate()
    }

    func testRetainedNativeCallbackCompletesAfterAdapterIsInvalidatedAndReleased() async throws {
        let activity = NativeActivityMock(identifier: "test.extension-updates")
        var scheduler: ChromeWebStorePeriodicScheduler? = ChromeWebStorePeriodicScheduler(interval: 7200, activity: activity)
        let completed = expectation(description: "Already-delivered callback completed")
        scheduler?.schedule {}
        let callback = try XCTUnwrap(activity.callback)
        scheduler?.invalidate()
        scheduler = nil
        callback { result in
            XCTAssertEqual(result, .finished)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
    }

    private final class NativeActivityMock: NSBackgroundActivityScheduler {
        var callback: (@Sendable (@escaping NSBackgroundActivityScheduler.CompletionHandler) -> Void)?
        private(set) var scheduleCount = 0
        private(set) var invalidationCount = 0

        override func schedule(_ block: @escaping @Sendable (@escaping NSBackgroundActivityScheduler.CompletionHandler) -> Void) {
            scheduleCount += 1
            callback = block
        }

        override func invalidate() {
            invalidationCount += 1
        }
    }

    private actor OperationGate {
        private let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?

        init(entered: XCTestExpectation) {
            self.entered = entered
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }
}
#endif

@available(macOS 15.4, iOS 18.4, *)
final class ChromeWebStorePeriodicSchedulerMock: ChromeWebStorePeriodicScheduling, Sendable {
    private struct State {
        var operation: (@Sendable () async -> Void)?
        var scheduleCount = 0
        var invalidationCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var operation: (@Sendable () async -> Void)? { state.withLock { $0.operation } }
    var scheduleCount: Int { state.withLock { $0.scheduleCount } }
    var invalidationCount: Int { state.withLock { $0.invalidationCount } }

    func schedule(_ operation: @escaping @Sendable () async -> Void) {
        state.withLock {
            $0.operation = operation
            $0.scheduleCount += 1
        }
    }

    func invalidate() {
        state.withLock { $0.invalidationCount += 1 }
    }

    func fire() async {
        await operation?()
    }
}
