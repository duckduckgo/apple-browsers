//
//  AuditLogPollerTests.swift
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

import XCTest
@_spi(Testing) import Persistence
@testable import DDGSync

final class AuditLogPollerTests: XCTestCase {
    private var accountManager: AccountManagingMock!
    private var store: MockKeyValueFileStore!
    private var isEnabled = true
    private var initializedPages: [AuditLogPage] = []
    private var errors: [Error] = []
    private var delays: [UInt64] = []

    override func setUpWithError() throws {
        accountManager = AccountManagingMock()
        store = MockKeyValueFileStore()
        isEnabled = true
        initializedPages = []
        errors = []
        delays = []
    }

    private func makePoller(sleep: ((UInt64) async throws -> Void)? = nil) -> AuditLogPoller {
        AuditLogPoller(accountManager: accountManager,
                       keyValueStore: store,
                       canPoll: { [unowned self] _ in self.isEnabled },
                       initializeReviewState: { [unowned self] page, _ in self.initializedPages.append(page) },
                       onError: { [unowned self] in self.errors.append($0) },
                       notify: { _ in }, reviewedThrough: { _ in nil },
                       sleep: sleep ?? { [unowned self] in self.delays.append($0) })
    }

    private func cursor(for account: SyncAccount = .mock) throws -> String? {
        guard let data = try store.object(forKey: AuditLogPoller.checkpointKey(for: account.userId)) as? Data else { return nil }
        return try JSONDecoder().decode(AuditLogCheckpoint.self, from: data).cursor
    }

    private func setCursor(_ cursor: String = "saved") throws {
        try store.set(JSONEncoder().encode(AuditLogCheckpoint(cursor: cursor)), forKey: AuditLogPoller.checkpointKey(for: SyncAccount.mock.userId))
    }

    func testFirstPollStoresHeadWithoutFollowingHistoricalPages() async throws {
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [.unreadable(id: "old", reason: .keyUnavailable)], after: "head", before: "older")
        let poller = makePoller()

        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "head")
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
        XCTAssertNil(accountManager.fetchAuditLogCalls[0].1)
        XCTAssertEqual(accountManager.fetchAuditLogCalls[0].2, 100)
        XCTAssertEqual(initializedPages.count, 1)
        XCTAssertTrue(delays.isEmpty)
    }

    func testEmptyInitialPageStillStoresHeadAndInitializesReviewState() async throws {
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "cursor")
        XCTAssertEqual(initializedPages.count, 1)
    }

    func testPollResumesFromPersistedCursorAndStoresEmptyPageCursor() async throws {
        try setCursor()
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        guard case .after("saved") = accountManager.fetchAuditLogCalls[0].1 else { return XCTFail("Expected saved forward cursor") }
        XCTAssertEqual(try cursor(), "cursor")
        XCTAssertTrue(initializedPages.isEmpty)
    }

    func testPollContinuesThroughUnreadableAndUnknownEntriesUntilRawPageIsEmpty() async throws {
        try setCursor()
        var pages = [
            AuditLogPage(entries: [.unreadable(id: "unreadable", reason: .keyUnavailable)], after: "next", before: nil),
            AuditLogPage(entries: [.unknownType(id: "unknown", type: "future")], after: "last", before: nil),
            AuditLogPage(entries: [], after: "empty", before: nil)
        ]
        accountManager.fetchAuditLogHandler = { _, _, _ in pages.removeFirst() }
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        let cursors = accountManager.fetchAuditLogCalls.compactMap { call -> String? in
            guard case .after(let cursor) = call.1 else { return nil }
            return cursor
        }
        XCTAssertEqual(cursors, ["saved", "next", "last"])
        XCTAssertEqual(try cursor(), "empty")
        XCTAssertEqual(delays, [2_000_000_000, 2_000_000_000])
        XCTAssertTrue(initializedPages.isEmpty)
    }

    func testRequestFailuresRetainCursorAndRetryOnNextPoll() async throws {
        for error in [SyncError.unexpectedStatusCode(418), .unexpectedStatusCode(429), .unexpectedStatusCode(500), .unexpectedStatusCode(400)] {
            try setCursor()
            accountManager.fetchAuditLogError = error
            let poller = makePoller()
            try? await poller.startPolling(for: .mock)?.value
            XCTAssertEqual(try cursor(), "saved")
            accountManager.fetchAuditLogError = nil
            try? await poller.startPolling(for: .mock)?.value
            XCTAssertEqual(try cursor(), "cursor")
        }
        XCTAssertEqual(errors.count, 4)
    }

    func testNetworkFailureRetainsCursor() async throws {
        try setCursor()
        accountManager.fetchAuditLogError = URLError(.notConnectedToInternet)
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "saved")
        XCTAssertEqual(errors.count, 1)
    }

    func testFailureAfterSuccessfulPageRetainsCursorFromBeforeThePoll() async throws {
        try setCursor()
        accountManager.fetchAuditLogHandler = { [unowned self] _, _, _ in
            if self.accountManager.fetchAuditLogCalls.count == 1 {
                return AuditLogPage(entries: [.unreadable(id: "event", reason: .keyUnavailable)], after: "processed", before: nil)
            }
            throw SyncError.unexpectedStatusCode(418)
        }
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "saved")
        XCTAssertEqual(errors.count, 1)
    }

    func testInvalidCursorReinitializesOnce() async throws {
        try setCursor()
        accountManager.fetchAuditLogHandler = { _, cursor, _ in
            if cursor != nil { throw AuditLogError.invalidCursor }
            return AuditLogPage(entries: [], after: "fresh", before: nil)
        }
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 2)
        XCTAssertNil(accountManager.fetchAuditLogCalls[1].1)
        XCTAssertEqual(try cursor(), "fresh")
        XCTAssertEqual(initializedPages.count, 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func testFailedReinitializationPreservesCursorForNextAttempt() async throws {
        try setCursor()
        accountManager.fetchAuditLogHandler = { _, cursor, _ in
            if cursor != nil { throw AuditLogError.invalidCursor }
            throw SyncError.unexpectedStatusCode(500)
        }
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "saved")
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 2)
        XCTAssertEqual(errors.count, 1)
    }

    func testMissingAfterCursorDoesNotReplaceCheckpoint() async throws {
        try setCursor()
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: nil, before: nil)
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "saved")
        XCTAssertTrue(errors.first is AuditLogError)
    }

    func testDisabledPollerDoesNotRequestOrChangeCursorAndCanBeEnabledAtRuntime() async throws {
        try setCursor()
        isEnabled = false
        let poller = makePoller()
        XCTAssertNil(poller.startPolling(for: .mock))
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        XCTAssertEqual(try cursor(), "saved")

        isEnabled = true
        try? await poller.startPolling(for: .mock)?.value
        XCTAssertEqual(try cursor(), "cursor")
    }

    func testEligibilityReadFailureDoesNotStartPolling() {
        let expectedError = NSError(domain: "test", code: 1)
        let poller = AuditLogPoller(accountManager: accountManager,
                                   keyValueStore: store,
                                   canPoll: { _ in throw expectedError },
                                   initializeReviewState: { _, _ in XCTFail("Polling should not start") },
                                   onError: { [unowned self] in self.errors.append($0) }, notify: { _ in }, reviewedThrough: { _ in nil })

        XCTAssertNil(poller.startPolling(for: .mock))
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        XCTAssertEqual(errors.first as NSError?, expectedError)
    }

    func testAwaitableEligibilityFailureOnlyThrows() async throws {
        let expectedError = NSError(domain: "test", code: 1)
        let poller = AuditLogPoller(accountManager: accountManager,
                                   keyValueStore: store,
                                   canPoll: { _ in throw expectedError },
                                   initializeReviewState: { _, _ in XCTFail("Polling should not start") },
                                   onError: { _ in XCTFail("The awaiting caller reports the error") }, notify: { _ in }, reviewedThrough: { _ in nil })
        do {
            _ = try await poller.pollIfNeeded(for: .mock)
            XCTFail("Expected the eligibility error")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
    }

    func testCancellationDuringFinalEligibilityCheckDoesNotSaveCheckpoint() async throws {
        weak var currentPoller: AuditLogPoller?
        let poller = AuditLogPoller(accountManager: accountManager,
                                   keyValueStore: store,
                                   canPoll: { [accountManager] _ in
                                       if accountManager?.fetchAuditLogCalls.isEmpty == false {
                                           currentPoller?.cancel()
                                       }
                                       return true
                                   },
                                   initializeReviewState: { _, _ in XCTFail("Cancelled polling should not initialize review state") },
                                   onError: { _ in XCTFail("Cancellation should not report an error") }, notify: { _ in }, reviewedThrough: { _ in nil })
        currentPoller = poller

        try? await poller.startPolling(for: .mock)?.value

        XCTAssertNil(try cursor())
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
    }

    func testReviewStateInitializationCanCancelPollingWithoutSavingCheckpoint() async throws {
        weak var currentPoller: AuditLogPoller?
        let poller = AuditLogPoller(accountManager: accountManager,
                                   keyValueStore: store,
                                   canPoll: { _ in true },
                                   initializeReviewState: { _, _ in currentPoller?.cancel() },
                                   onError: { _ in XCTFail("Cancellation should not report an error") }, notify: { _ in }, reviewedThrough: { _ in nil })
        currentPoller = poller

        try? await poller.startPolling(for: .mock)?.value

        XCTAssertNil(try cursor())
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
    }

    func testReviewStateInitializationCanClearPollingWithoutRestoringCheckpoint() async throws {
        weak var currentPoller: AuditLogPoller?
        let poller = AuditLogPoller(accountManager: accountManager,
                                   keyValueStore: store,
                                   canPoll: { [unowned self] _ in self.isEnabled },
                                   initializeReviewState: { [unowned self] _, account in
                                       self.isEnabled = false
                                       try currentPoller?.clearState(for: account.userId)
                                   },
                                   onError: { _ in XCTFail("Cancellation should not report an error") }, notify: { _ in }, reviewedThrough: { _ in nil })
        currentPoller = poller

        try? await poller.startPolling(for: .mock)?.value

        XCTAssertNil(try cursor())
        XCTAssertNil(poller.startPolling(for: .mock))
    }

    func testDisableDuringFetchDiscardsResponse() async throws {
        try setCursor()
        accountManager.fetchAuditLogHandler = { [unowned self] _, _, _ in
            self.isEnabled = false
            return AuditLogPage(entries: [], after: "discarded", before: nil)
        }
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value

        XCTAssertEqual(try cursor(), "saved")
        XCTAssertTrue(errors.isEmpty)
    }

    func testOnlyOnePollRunsAndCancelledRequestCannotWriteAfterLogout() async throws {
        try setCursor()
        let started = expectation(description: "Request started")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        accountManager.fetchAuditLogHandler = { _, _, _ in
            started.fulfill()
            // Model a transport which returns a late response despite cancellation.
            await withCheckedContinuation { response in
                Task.detached {
                    for await _ in gate { break }
                    response.resume()
                }
            }
            return AuditLogPage(entries: [], after: "stale", before: nil)
        }
        let poller = makePoller()
        let task = try XCTUnwrap(poller.startPolling(for: .mock))
        await fulfillment(of: [started], timeout: 1)
        XCTAssertNil(poller.startPolling(for: .mock))
        try poller.clearState(for: SyncAccount.mock.userId)
        XCTAssertNil(poller.startPolling(for: .mock))
        continuation.yield(())
        continuation.finish()
        try? await task.value

        XCTAssertNil(try cursor())
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func testCancellationDuringPacingKeepsOriginalCursorAndNextPollRepeatsThePoll() async throws {
        try setCursor()
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [.unreadable(id: "event", reason: .keyUnavailable)], after: "checkpoint", before: nil)
        let sleeping = expectation(description: "Continuation pacing started")
        let poller = makePoller(sleep: { _ in
            sleeping.fulfill()
            try await Task.sleep(nanoseconds: 60_000_000_000)
        })
        let task = try XCTUnwrap(poller.startPolling(for: .mock))
        await fulfillment(of: [sleeping], timeout: 1)
        poller.cancel()
        try? await task.value
        XCTAssertEqual(try cursor(), "saved")
        XCTAssertTrue(errors.isEmpty)

        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: "resumed", before: nil)
        try? await poller.startPolling(for: .mock)?.value
        guard case .after("saved") = accountManager.fetchAuditLogCalls.last?.1 else { return XCTFail("Expected cursor from before the cancelled poll") }
        XCTAssertEqual(try cursor(), "resumed")
    }

    func testCursorIsAccountScopedAndSurvivesNewPollerInstance() async throws {
        try setCursor("first-account")
        let account = SyncAccount.mock
        let other = SyncAccount(deviceId: account.deviceId, deviceName: account.deviceName, deviceType: account.deviceType,
                                userId: "other", primaryKey: account.primaryKey, secretKey: account.secretKey, token: account.token, state: .active)
        let poller = makePoller()
        try? await poller.startPolling(for: other)?.value
        XCTAssertNil(accountManager.fetchAuditLogCalls[0].1)
        XCTAssertEqual(try cursor(), "first-account")
        XCTAssertEqual(try cursor(for: other), "cursor")

        let relaunchedPoller = makePoller()
        try? await relaunchedPoller.startPolling(for: .mock)?.value
        guard case .after("first-account") = accountManager.fetchAuditLogCalls.last?.1 else { return XCTFail("Expected persisted cursor") }
    }

    func testAwaitablePollPropagatesFailureAndCanRetry() async throws {
        try setCursor()
        accountManager.fetchAuditLogError = SyncError.unexpectedStatusCode(401)
        let poller = makePoller()
        do {
            _ = try await poller.pollIfNeeded(for: .mock)
            XCTFail("Expected the request error")
        } catch {
            guard case SyncError.unexpectedStatusCode(401) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try cursor(), "saved")
        XCTAssertTrue(errors.isEmpty)

        accountManager.fetchAuditLogError = nil
        let completed = try await poller.pollIfNeeded(for: .mock)
        XCTAssertTrue(completed)
        XCTAssertEqual(try cursor(), "cursor")
    }

    func testCancellingAwaitingCallerCancelsPollWithoutAdvancingCursor() async throws {
        try setCursor()
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [.unreadable(id: "event", reason: .keyUnavailable)], after: "new", before: nil)
        let sleeping = expectation(description: "Continuation pacing started")
        let poller = makePoller(sleep: { _ in
            sleeping.fulfill()
            try await Task.sleep(nanoseconds: 60_000_000_000)
        })
        let caller = Task { try await poller.pollIfNeeded(for: .mock) }
        await fulfillment(of: [sleeping], timeout: 1)
        let overlapping = try await poller.pollIfNeeded(for: .mock)
        XCTAssertFalse(overlapping)
        caller.cancel()
        do {
            _ = try await caller.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertEqual(try cursor(), "saved")
        XCTAssertTrue(errors.isEmpty)
    }

    func testPersistenceFailureLeavesPreviousCheckpointAndRetriesLater() async throws {
        try setCursor()
        store.throwOnSet = NSError(domain: "test", code: 1)
        let poller = makePoller()
        try? await poller.startPolling(for: .mock)?.value
        XCTAssertEqual(try cursor(), "saved")
        XCTAssertEqual(errors.count, 1)

        store.throwOnSet = nil
        try? await poller.startPolling(for: .mock)?.value
        XCTAssertEqual(try cursor(), "cursor")
    }

}
