//
//  SubscriptionRequestCoalescerTests.swift
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

import XCTest
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionRequestCoalescerTests: XCTestCase {

    // MARK: - Sequential behaviour

    func testCoalesce_ReturnValueFromWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let subscription = SubscriptionMockFactory.appleSubscription

        let result = try await coalescer.coalesce(forceRefresh: false) { subscription }

        XCTAssertEqual(result, subscription)
    }

    func testCoalesce_ReturnsNilWhenWorkReturnsNil() async throws {
        let coalescer = SubscriptionRequestCoalescer()

        let result = try await coalescer.coalesce(forceRefresh: false) { nil }

        XCTAssertNil(result)
    }

    func testCoalesce_PropagatesErrorFromWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        struct Sentinel: Error {}

        do {
            _ = try await coalescer.coalesce(forceRefresh: false) { throw Sentinel() }
            XCTFail("Expected Sentinel to be thrown")
        } catch is Sentinel {
            // expected
        }
    }

    func testCoalesce_SequentialCallsEachRunTheirOwnWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let counter = AtomicCounter()

        _ = try await coalescer.coalesce(forceRefresh: false) { counter.increment(); return nil }
        _ = try await coalescer.coalesce(forceRefresh: false) { counter.increment(); return nil }

        XCTAssertEqual(counter.value, 2, "Sequential calls must each invoke work independently")
    }

    /// Verifies that after a call completes, its entry is removed from `inFlight`
    /// so the next call runs fresh work and does not return the previous result.
    func testCoalesce_CompletedTaskIsNotReusedBySubsequentCall() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let first = SubscriptionMockFactory.appleSubscription
        let second = SubscriptionMockFactory.expiredSubscription

        _ = try await coalescer.coalesce(forceRefresh: false) { first }
        let result = try await coalescer.coalesce(forceRefresh: false) { second }

        XCTAssertEqual(result, second,
                       "Post-completion call must run fresh work, not return the previous task's cached result")
    }

    func testCoalesce_DifferentKeysBothExecuteTheirWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let counter = AtomicCounter()

        async let r1 = coalescer.coalesce(forceRefresh: false) { counter.increment(); return nil }
        async let r2 = coalescer.coalesce(forceRefresh: true) { counter.increment(); return nil }
        _ = try await (r1, r2)

        XCTAssertEqual(counter.value, 2, "Calls with different forceRefresh values must each invoke their own work")
    }

    // MARK: - Concurrent coalescing
    //
    // The tests below use unstructured Tasks + semaphore handshake to guarantee ordering:
    //   1. `firstTask` is created and we wait for its work to signal `workIsInFlight`,
    //      confirming inFlight[mode] is populated.
    //   2. Only then is `secondTask` created, so it is guaranteed to find the in-flight
    //      entry and register its continuation rather than create a new one.
    //   3. A 1 ms sleep before releasing the gate gives `secondTask` time to call the
    //      actor and register its continuation. Actor calls complete in nanoseconds;
    //      1 ms is ~1000× headroom, making this robust without being flaky.

    func testCoalesce_ConcurrentCallsSameKeyShareOneExecution() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let subscription = SubscriptionMockFactory.appleSubscription
        let counter = AtomicCounter()
        let workIsInFlight = AsyncSemaphore()
        let releaseGate = AsyncSemaphore()

        let firstTask = Task {
            try await coalescer.coalesce(forceRefresh: false) {
                counter.increment()
                workIsInFlight.signal()   // inFlightTasks[false] is now set
                await releaseGate.wait()  // hold until second has joined
                return subscription
            }
        }

        await workIsInFlight.wait()  // first is running; inFlightTasks[false] guaranteed set

        let secondTask = Task {
            try await coalescer.coalesce(forceRefresh: false) {
                counter.increment()  // must NOT execute — second joins the first task
                return nil as DuckDuckGoSubscription?
            }
        }

        // Allow secondTask to reach the actor and join before work completes.
        try await Task.sleep(nanoseconds: 1_000_000)
        releaseGate.signal()

        let r1 = try await firstTask.value
        let r2 = try await secondTask.value

        XCTAssertEqual(counter.value, 1, "Only one work closure should run for concurrent same-key calls")
        XCTAssertEqual(r1, subscription)
        XCTAssertEqual(r2, subscription, "Both callers must receive the same result")
    }

    // MARK: - Cancellation behaviour

    /// When the originating task is cancelled while its work is in-flight, joiners waiting
    /// on their continuation must receive `CancellationError`, not hang.
    func testCoalesce_CancelledOriginator_JoinerReceivesCancellationError() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let workIsInFlight = AsyncSemaphore()
        let releaseGate = AsyncSemaphore()

        let originatorTask = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: false) {
                workIsInFlight.signal()
                await releaseGate.wait()
                try Task.checkCancellation()
                return nil
            }
        }

        await workIsInFlight.wait()

        let joinerTask = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: false) {
                XCTFail("Joiner's work must not execute")
                return nil
            }
        }

        try await Task.sleep(nanoseconds: 1_000_000)  // let joiner join the in-flight task
        originatorTask.cancel()
        releaseGate.signal()

        do {
            _ = try await originatorTask.value
            XCTFail("Originator should throw CancellationError")
        } catch is CancellationError {}

        do {
            _ = try await joinerTask.value
            XCTFail("Joiner should receive CancellationError when originator's work is cancelled")
        } catch is CancellationError {}
    }

    /// Cancelling one joiner must not affect other joiners or the shared work.
    func testCoalesce_CancelledJoiner_DoesNotAffectOtherJoinersOrWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let subscription = SubscriptionMockFactory.appleSubscription
        let workIsInFlight = AsyncSemaphore()
        let releaseGate = AsyncSemaphore()

        let originatorTask = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: false) {
                workIsInFlight.signal()
                await releaseGate.wait()
                return subscription
            }
        }

        await workIsInFlight.wait()

        let cancelledJoiner = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: false) {
                XCTFail("Joiner's work must not execute")
                return nil
            }
        }

        let survivingJoiner = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: false) {
                XCTFail("Joiner's work must not execute")
                return nil
            }
        }

        try await Task.sleep(nanoseconds: 1_000_000)  // let both joiners register their continuations
        cancelledJoiner.cancel()
        releaseGate.signal()

        _ = try? await cancelledJoiner.value  // drain (may throw CancellationError)

        let originatorResult = try await originatorTask.value
        let survivingResult = try await survivingJoiner.value

        XCTAssertEqual(originatorResult, subscription, "Originator must complete normally")
        XCTAssertEqual(survivingResult, subscription, "Surviving joiner must receive the work result unaffected by the cancelled joiner")
    }

    /// After an originator's task is cancelled and removed from `inFlight`, a new caller
    /// must run its own fresh work rather than hang or silently receive nil.
    func testCoalesce_AfterCancelledTask_NewCallerRunsFreshWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let subscription = SubscriptionMockFactory.appleSubscription
        let counter = AtomicCounter()
        let workIsInFlight = AsyncSemaphore()
        let releaseGate = AsyncSemaphore()

        let cancelledTask = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: false) {
                counter.increment()
                workIsInFlight.signal()
                await releaseGate.wait()
                try Task.checkCancellation()
                return nil
            }
        }

        await workIsInFlight.wait()
        cancelledTask.cancel()
        releaseGate.signal()
        _ = try? await cancelledTask.value  // drain the cancelled task

        let result = try await coalescer.coalesce(forceRefresh: false) {
            counter.increment()
            return subscription
        }

        XCTAssertEqual(result, subscription, "Fresh call after cancellation must return its own work's result")
        XCTAssertEqual(counter.value, 2, "Fresh call must run new work, not reuse the cancelled task")
    }

    func testCoalesce_ConcurrentCallsSameKeyBothReceiveError() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        struct Sentinel: Error {}
        let workIsInFlight = AsyncSemaphore()
        let releaseGate = AsyncSemaphore()

        let firstTask = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: true) {
                workIsInFlight.signal()
                await releaseGate.wait()
                throw Sentinel()
            }
        }

        await workIsInFlight.wait()

        let secondTask = Task<DuckDuckGoSubscription?, Error> {
            try await coalescer.coalesce(forceRefresh: true) {
                XCTFail("Second caller's work must not execute")
                return nil
            }
        }

        try await Task.sleep(nanoseconds: 1_000_000)
        releaseGate.signal()

        do {
            _ = try await firstTask.value
            XCTFail("first should throw")
        } catch is Sentinel {}

        do {
            _ = try await secondTask.value
            XCTFail("second should throw")
        } catch is Sentinel {}
    }
}

// MARK: - Test Utilities

/// Thread-safe counter — `@unchecked Sendable` so it can be captured by `@Sendable` closures
/// without triggering Swift 6 data-race warnings. Thread safety is guaranteed by the NSLock.
private final class AtomicCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

/// Minimal async semaphore used to synchronise two concurrent tasks in tests.
private final class AsyncSemaphore: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private var signalled = false
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if signalled {
                signalled = false
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if let cont = continuation {
            continuation = nil
            lock.unlock()
            cont.resume()
        } else {
            signalled = true
            lock.unlock()
        }
    }
}
