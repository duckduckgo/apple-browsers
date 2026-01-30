//
//  TerminationDeciderHandlerTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class TerminationDeciderHandlerTests: XCTestCase {

    var replyCallCount = 0
    var lastReplyValue: Bool?

    override func setUp() async throws {
        replyCallCount = 0
        lastReplyValue = nil
    }

    // MARK: - Sync Tests

    /// Verifies all deciders are notified when all return .next
    func testAllDecidersReturnNextNotifiesAllDeciders() {
        // Given
        let decider1 = MockDecider(name: "Decider1", response: .sync(.next))
        let decider2 = MockDecider(name: "Decider2", response: .sync(.next))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next))

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: mockReply
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateNow)
        XCTAssertEqual(replyCallCount, 0, "Should not call reply for synchronous .terminateNow")

        XCTAssertEqual(decider1.completionCallCount, 1)
        XCTAssertEqual(decider1.lastCompletionValue, true)

        XCTAssertEqual(decider2.completionCallCount, 1)
        XCTAssertEqual(decider2.lastCompletionValue, true)

        XCTAssertEqual(decider3.completionCallCount, 1)
        XCTAssertEqual(decider3.lastCompletionValue, true)
    }

    /// Verifies no deciders are notified when first decider cancels in sync non-async mode
    func testFirstDeciderCancelsInSyncModeDoesNotNotifyAnyDeciders() {
        // Given
        let decider1 = MockDecider(name: "Decider1", response: .sync(.cancel))
        let decider2 = MockDecider(name: "Decider2", response: .sync(.next))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next))

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: mockReply
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertEqual(replyCallCount, 0, "Sync cancel in non-async mode should not call reply")

        XCTAssertEqual(decider1.completionCallCount, 0, "Sync .cancel in non-async mode doesn't notify deciders")
        XCTAssertEqual(decider2.completionCallCount, 0, "Decider2 should not be invoked")
        XCTAssertEqual(decider3.completionCallCount, 0, "Decider3 should not be invoked")
    }

    /// Verifies no deciders are notified when middle decider cancels in sync non-async mode
    func testMiddleDeciderCancelsNotifiesOnlyInvokedDeciders() {
        // Given
        let decider1 = MockDecider(name: "Decider1", response: .sync(.next))
        let decider2 = MockDecider(name: "Decider2", response: .sync(.cancel))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next))

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: mockReply
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateCancel)

        XCTAssertEqual(decider1.completionCallCount, 0)
        XCTAssertEqual(decider2.completionCallCount, 0)
        XCTAssertEqual(decider3.completionCallCount, 0, "Decider3 should not be invoked")
    }

    // MARK: - Async Tests

    /// Verifies all deciders are notified when first decider returns async .next
    func testFirstDeciderAsyncThenNextNotifiesAllDeciders() async {
        // Given
        let asyncTask = Task<TerminationDecision, Never> { .next }
        let decider1 = MockDecider(name: "Decider1", response: .async(asyncTask), expectation: expectation(description: "Decider1 completion"))
        let decider2 = MockDecider(name: "Decider2", response: .sync(.next), expectation: expectation(description: "Decider2 completion"))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next), expectation: expectation(description: "Decider3 completion"))
        let replyExpectation = expectation(description: "Reply called")

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: { [weak self] value in
                self?.mockReply(value: value)
                replyExpectation.fulfill()
            }
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateLater)

        await fulfillment(of: [decider1.expectation!, decider2.expectation!, decider3.expectation!, replyExpectation], timeout: 1.0)

        XCTAssertEqual(decider1.completionCallCount, 1)
        XCTAssertEqual(decider1.lastCompletionValue, true)

        XCTAssertEqual(decider2.completionCallCount, 1)
        XCTAssertEqual(decider2.lastCompletionValue, true)

        XCTAssertEqual(decider3.completionCallCount, 1)
        XCTAssertEqual(decider3.lastCompletionValue, true)

        XCTAssertEqual(replyCallCount, 1)
        XCTAssertEqual(lastReplyValue, true)
    }

    /// Verifies only first decider is notified when its async task returns .cancel
    func testFirstDeciderAsyncThenCancelNotifiesOnlyFirstDecider() async {
        // Given
        let asyncTask = Task<TerminationDecision, Never> { .cancel }
        let decider1 = MockDecider(name: "Decider1", response: .async(asyncTask), expectation: expectation(description: "Decider1 completion"))
        let decider2 = MockDecider(name: "Decider2", response: .sync(.next))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next))
        let replyExpectation = expectation(description: "Reply called")

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: { [weak self] value in
                self?.mockReply(value: value)
                replyExpectation.fulfill()
            }
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateLater)

        await fulfillment(of: [decider1.expectation!, replyExpectation], timeout: 1.0)

        XCTAssertEqual(decider1.completionCallCount, 1)
        XCTAssertEqual(decider1.lastCompletionValue, false)

        XCTAssertEqual(decider2.completionCallCount, 0, "Decider2 should not be notified")
        XCTAssertEqual(decider3.completionCallCount, 0, "Decider3 should not be notified")

        XCTAssertEqual(replyCallCount, 1)
        XCTAssertEqual(lastReplyValue, false)
    }

    /// Verifies first two deciders are notified when second decider's async task returns .cancel
    func testSecondDeciderAsyncThenCancelNotifiesFirstTwoDeciders() async {
        // Given
        let asyncTask = Task<TerminationDecision, Never> { .cancel }
        let decider1 = MockDecider(name: "Decider1", response: .sync(.next), expectation: expectation(description: "Decider1 completion"))
        let decider2 = MockDecider(name: "Decider2", response: .async(asyncTask), expectation: expectation(description: "Decider2 completion"))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next))
        let replyExpectation = expectation(description: "Reply called")

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: { [weak self] value in
                self?.mockReply(value: value)
                replyExpectation.fulfill()
            }
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateLater)

        await fulfillment(of: [decider1.expectation!, decider2.expectation!, replyExpectation], timeout: 1.0)

        XCTAssertEqual(decider1.completionCallCount, 1)
        XCTAssertEqual(decider1.lastCompletionValue, false)

        XCTAssertEqual(decider2.completionCallCount, 1)
        XCTAssertEqual(decider2.lastCompletionValue, false)

        XCTAssertEqual(decider3.completionCallCount, 0, "Decider3 should not be notified")

        XCTAssertEqual(replyCallCount, 1)
        XCTAssertEqual(lastReplyValue, false)
    }

    /// Verifies invoked deciders are notified when sync .cancel occurs in async mode
    func testSyncCancelInAsyncModeNotifiesInvokedDeciders() async {
        // Given
        let asyncTask = Task<TerminationDecision, Never> { .next }
        let decider1 = MockDecider(name: "Decider1", response: .async(asyncTask), expectation: expectation(description: "Decider1 completion"))
        let decider2 = MockDecider(name: "Decider2", response: .sync(.cancel), expectation: expectation(description: "Decider2 completion"))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next))
        let replyExpectation = expectation(description: "Reply called")

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: { [weak self] value in
                self?.mockReply(value: value)
                replyExpectation.fulfill()
            }
        )

        // When
        let reply = handler.executeTerminationDeciders()
        XCTAssertEqual(reply, .terminateLater)

        await fulfillment(of: [decider1.expectation!, decider2.expectation!, replyExpectation], timeout: 1.0)

        // Then
        XCTAssertEqual(decider1.completionCallCount, 1)
        XCTAssertEqual(decider1.lastCompletionValue, false)

        XCTAssertEqual(decider2.completionCallCount, 1)
        XCTAssertEqual(decider2.lastCompletionValue, false)

        XCTAssertEqual(decider3.completionCallCount, 0, "Decider3 should not be notified")
    }

    /// Verifies all deciders are notified when multiple async deciders all return .next
    func testMultipleAsyncDecidersAllReturnNextNotifiesAll() async {
        // Given
        let asyncTask1 = Task<TerminationDecision, Never> { .next }
        let asyncTask2 = Task<TerminationDecision, Never> { .next }
        let decider1 = MockDecider(name: "Decider1", response: .async(asyncTask1), expectation: expectation(description: "Decider1 completion"))
        let decider2 = MockDecider(name: "Decider2", response: .async(asyncTask2), expectation: expectation(description: "Decider2 completion"))
        let decider3 = MockDecider(name: "Decider3", response: .sync(.next), expectation: expectation(description: "Decider3 completion"))
        let replyExpectation = expectation(description: "Reply called")

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2, decider3],
            replyToApplicationShouldTerminate: { [weak self] value in
                self?.mockReply(value: value)
                replyExpectation.fulfill()
            }
        )

        // When
        let reply = handler.executeTerminationDeciders()
        XCTAssertEqual(reply, .terminateLater)

        await fulfillment(of: [decider1.expectation!, decider2.expectation!, decider3.expectation!, replyExpectation], timeout: 1.0)

        // Then
        XCTAssertEqual(decider1.completionCallCount, 1)
        XCTAssertEqual(decider1.lastCompletionValue, true)

        XCTAssertEqual(decider2.completionCallCount, 1)
        XCTAssertEqual(decider2.lastCompletionValue, true)

        XCTAssertEqual(decider3.completionCallCount, 1)
        XCTAssertEqual(decider3.lastCompletionValue, true)

        XCTAssertEqual(replyCallCount, 1)
        XCTAssertEqual(lastReplyValue, true)
    }

    // MARK: - Closure Decider Helper Tests

    /// Verifies .terminationDecider() creates a decider that executes the provided closure
    func testTerminationDeciderHelperExecutesClosure() {
        // Given
        var closureExecuted = false
        let decider: ClosureApplicationTerminationDecider = .terminationDecider { isAsync in
            closureExecuted = true
            return .sync(.next)
        }

        // When
        let query = decider.shouldTerminate(isAsync: false)

        // Then
        XCTAssertTrue(closureExecuted)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .next)
    }

    /// Verifies .perform() creates a decider that executes action and returns .sync(.next)
    func testPerformHelperExecutesActionAndReturnsNext() {
        // Given
        var actionExecuted = false
        let decider: ClosureApplicationTerminationDecider = .perform {
            actionExecuted = true
        }

        // When
        let query = decider.shouldTerminate(isAsync: false)

        // Then
        XCTAssertTrue(actionExecuted)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .next)
    }

    /// Verifies .perform() decider works in handler sequence
    func testPerformHelperWorksInDeciderSequence() {
        // Given
        var action1Executed = false
        var action2Executed = false
        let decider1: ClosureApplicationTerminationDecider = .perform { action1Executed = true }
        let decider2: ClosureApplicationTerminationDecider = .perform { action2Executed = true }

        let handler = TerminationDeciderHandler(
            deciders: [decider1, decider2],
            replyToApplicationShouldTerminate: mockReply
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateNow)
        XCTAssertTrue(action1Executed)
        XCTAssertTrue(action2Executed)
    }

    // MARK: - Edge Cases

    /// Verifies .terminateNow is returned when deciders list is empty
    func testEmptyDecidersListReturnsTerminateNow() {
        // Given
        let handler = TerminationDeciderHandler(
            deciders: [],
            replyToApplicationShouldTerminate: mockReply
        )

        // When
        let reply = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply, .terminateNow)
        XCTAssertEqual(replyCallCount, 0, "No reply call for sync .terminateNow")
    }

    /// Verifies reentry prevention returns .terminateLater without processing when already terminating
    func testReentryPreventionReturnsTerminateLater() async {
        // Given
        let asyncTask = Task<TerminationDecision, Never> {
            try? await Task.sleep(interval: 0.2)
            return .next
        }
        let deciderExpectation = expectation(description: "Decider completion")
        let decider = MockDecider(name: "Decider1", response: .async(asyncTask), expectation: deciderExpectation)
        let replyExpectation = expectation(description: "Reply called")

        let handler = TerminationDeciderHandler(
            deciders: [decider],
            replyToApplicationShouldTerminate: { [weak self] value in
                self?.mockReply(value: value)
                replyExpectation.fulfill()
            }
        )

        // When
        let reply1 = handler.executeTerminationDeciders()
        XCTAssertEqual(reply1, .terminateLater)

        let reply2 = handler.executeTerminationDeciders()

        // Then
        XCTAssertEqual(reply2, .terminateLater)

        await fulfillment(of: [deciderExpectation, replyExpectation], timeout: 1.0)

        XCTAssertEqual(decider.completionCallCount, 1)
    }

    // MARK: - Helpers

    /// Mock decider for testing termination decision flow
    final class MockDecider: ApplicationTerminationDecider {
        let name: String
        let response: TerminationQuery
        var completionCallCount = 0
        var lastCompletionValue: Bool?
        let expectation: XCTestExpectation?

        init(name: String, response: TerminationQuery, expectation: XCTestExpectation? = nil) {
            self.name = name
            self.response = response
            self.expectation = expectation
        }

        func shouldTerminate(isAsync: Bool) -> TerminationQuery {
            return response
        }

        func deciderSequenceCompleted(shouldProceed: Bool) {
            completionCallCount += 1
            lastCompletionValue = shouldProceed
            expectation?.fulfill()
        }
    }

    /// Helper method to track reply calls
    func mockReply(value: Bool) {
        replyCallCount += 1
        lastReplyValue = value
    }
}
