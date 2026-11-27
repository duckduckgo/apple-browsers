//
//  AuditLogNotificationTests.swift
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

final class AuditLogNotificationTests: XCTestCase {
    private let account = SyncAccount.mock
    private var manager: AccountManagingMock!
    private var store: MockKeyValueFileStore!
    private var notifications: [SyncLoginNotification] = []
    private var errors: [Error] = []
    private var enabled = true
    private var reviewedDate: Date?

    override func setUpWithError() throws {
        manager = AccountManagingMock()
        store = MockKeyValueFileStore()
        notifications = []
        errors = []
        enabled = true
        reviewedDate = nil
    }

    private func makePoller(notify: ((SyncLoginNotification) async -> Void)? = nil) -> AuditLogPoller {
        AuditLogPoller(accountManager: manager, keyValueStore: store,
                       canPoll: { [unowned self] _ in self.enabled }, initializeReviewState: { _, _ in },
                       onError: { [unowned self] in self.errors.append($0) },
                       notify: notify ?? { [unowned self] in self.notifications.append($0) },
                       reviewedThrough: { [unowned self] _ in self.reviewedDate }, sleep: { _ in })
    }

    private func checkpoint() throws -> AuditLogCheckpoint {
        guard let data = try store.object(forKey: AuditLogPoller.checkpointKey(for: account.userId)) as? Data else {
            return AuditLogCheckpoint()
        }
        return try JSONDecoder().decode(AuditLogCheckpoint.self, from: data)
    }

    private func seed(cursor: String? = "start", pending: [SyncLoginEvent] = []) throws {
        try store.set(JSONEncoder().encode(AuditLogCheckpoint(cursor: cursor, pendingEvents: pending)),
                      forKey: AuditLogPoller.checkpointKey(for: account.userId))
    }

    private func entry(_ id: String, type: AuditLogEventType = .login, deviceID: String = "other", name: String = "Legacy",
                       info: Bool = false, date: TimeInterval = 100) -> AuditLogEntryDecodingResult {
        .decoded(AuditLogEvent(id: id, type: type, occurredAt: Date(timeIntervalSince1970: date),
                              device: RegisteredDevice(id: deviceID, name: name, type: "phone", credentialId: "ddg"),
                              actor: nil, hasDeviceInfo: info))
    }

    private func pages(_ values: [AuditLogPage]) {
        var remaining = values
        manager.fetchAuditLogHandler = { _, _, _ in remaining.removeFirst() }
    }

    private func pending(_ id: String, date: TimeInterval = 50) -> SyncLoginEvent {
        SyncLoginEvent(id: id, occurredAt: Date(timeIntervalSince1970: date), deviceName: id)
    }

    func testCompletePollGroupsLoginsAndEnrichesAcrossForwardPagesIncludingSameSecond() async throws {
        try seed()
        pages([
            AuditLogPage(entries: [entry("login"), entry("logout", type: .logout), entry("self", deviceID: account.deviceId)], after: "page1", before: nil),
            AuditLogPage(entries: [entry("info", type: .deviceInfoAdded, name: "Real name", info: true), entry("second", deviceID: "second")], after: "page2", before: nil),
            AuditLogPage(entries: [], after: "end", before: nil)
        ])
        let poller = makePoller()
        try await poller.startPolling(for: account)?.value
        let notification = try XCTUnwrap(notifications.first)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notification.accountID, account.userId)
        XCTAssertEqual(Set(notification.events.map(\.id)), ["login", "second"])
        XCTAssertEqual(notification.events.first { $0.id == "login" }?.deviceName, "Real name")
        XCTAssertEqual(try checkpoint().cursor, "end")
        XCTAssertEqual(Set(try checkpoint().pendingEvents.map(\.id)), ["login", "second"])
    }

    func testInitialAndInvalidCursorBaselinesNeverNotifyOrAddHistoricalCardEntries() async throws {
        manager.fetchAuditLogStub = AuditLogPage(entries: [entry("historical")], after: "head", before: nil)
        let poller = makePoller()
        try await poller.startPolling(for: account)?.value
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
        try seed(pending: [pending("existing")])
        var calls = 0
        manager.fetchAuditLogHandler = { [unowned self] _, _, _ in
            calls += 1
            if calls == 1 { throw AuditLogError.invalidCursor }
            return self.manager.fetchAuditLogStub
        }
        try await poller.startPolling(for: account)?.value
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertEqual(try checkpoint().pendingEvents.map(\.id), ["existing"])
        XCTAssertEqual(try checkpoint().cursor, "head")
    }

    func testSchedulingCompletesBeforeCheckpointAndFailureDoesNotBlockProgress() async throws {
        try seed()
        pages([AuditLogPage(entries: [entry("login")], after: "page", before: nil), AuditLogPage(entries: [], after: "end", before: nil)])
        var completed = false
        let poller = makePoller { [unowned self] _ in
            XCTAssertEqual(try? self.checkpoint().cursor, "start")
            // Platform callbacks handle scheduling failure and return normally.
            await Task.yield()
            completed = true
        }
        try await poller.startPolling(for: account)?.value
        XCTAssertTrue(completed)
        XCTAssertEqual(try checkpoint().cursor, "end")
        XCTAssertEqual(try checkpoint().pendingEvents.map(\.id), ["login"])
    }

    func testDismissalDuringDeliveryIsNotOverwrittenAndNewerEventsSurviveSameSecond() async throws {
        try seed(pending: [pending("shown", date: 100), pending("arrived", date: 100)])
        pages([AuditLogPage(entries: [entry("new")], after: "page", before: nil), AuditLogPage(entries: [], after: "end", before: nil)])
        var poller: AuditLogPoller!
        poller = makePoller { _ in try? poller.dismissEvents(withIDs: ["shown"], for: self.account.userId) }
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(Set(try checkpoint().pendingEvents.map(\.id)), ["arrived", "new"])
    }

    func testReviewWhilePollIsRunningPrunesExistingAndNewEvents() async throws {
        try seed(pending: [pending("existing")])
        pages([AuditLogPage(entries: [entry("reviewed"), entry("later", date: 101)], after: "page", before: nil),
               AuditLogPage(entries: [], after: "end", before: nil)])
        let poller = makePoller { [unowned self] _ in self.reviewedDate = Date(timeIntervalSince1970: 100) }
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(try checkpoint().pendingEvents.map(\.id), ["later"])
        try poller.removeReviewedEvents(through: Date(timeIntervalSince1970: 101), for: account.userId)
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
    }

    func testRetryAfterPersistenceFailureUsesSameIdentifierEvenWhenBatchGrows() async throws {
        try seed()
        let poller = makePoller()
        pages([AuditLogPage(entries: [entry("one")], after: "page", before: nil), AuditLogPage(entries: [], after: "end", before: nil)])
        store.throwOnSet = NSError(domain: "test", code: 1)
        let result = await poller.startPolling(for: account)?.result
        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(try checkpoint().cursor, "start")
        store.throwOnSet = nil
        pages([AuditLogPage(entries: [entry("two"), entry("one"), entry("one")], after: "page", before: nil),
               AuditLogPage(entries: [], after: "end2", before: nil)])
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(notifications[0].identifier, notifications[1].identifier)
        XCTAssertEqual(notifications[1].events.count, 2)
        XCTAssertEqual(try checkpoint().pendingEvents.count, 2)
    }

    func testCancellationDuringDeliveryCannotRestoreCheckpointAfterLogout() async throws {
        try seed()
        pages([AuditLogPage(entries: [entry("login")], after: "page", before: nil), AuditLogPage(entries: [], after: "end", before: nil)])
        var poller: AuditLogPoller!
        poller = makePoller { _ in try? poller.clearState(for: self.account.userId) }
        let result = await poller.startPolling(for: account)?.result
        XCTAssertThrowsError(try result?.get())
        XCTAssertNil(try checkpoint().cursor)
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }

    func testFetchFailureDoesNotNotifyOrPartiallyPersistEvents() async throws {
        try seed()
        var calls = 0
        manager.fetchAuditLogHandler = { [unowned self] _, _, _ in
            calls += 1
            if calls == 1 { return AuditLogPage(entries: [self.entry("login")], after: "page", before: nil) }
            throw URLError(.notConnectedToInternet)
        }
        let poller = makePoller()
        let result = await poller.startPolling(for: account)?.result
        XCTAssertThrowsError(try result?.get())
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertEqual(try checkpoint().cursor, "start")
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
    }
    func testServerRebuildDoesNotNotifyAgainAfterCardWasDismissed() async throws {
        manager.fetchAuditLogStub = AuditLogPage(entries: [entry("baseline")], after: "baseline-cursor", before: nil)
        let poller = makePoller()
        try await poller.startPolling(for: account)?.value
        pages([AuditLogPage(entries: [entry("new"), entry("baseline")], after: "page", before: nil),
               AuditLogPage(entries: [], after: "end", before: nil)])
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].events.map(\.id), ["new"])
        try poller.dismissEvents(withIDs: ["new"], for: account.userId)
        pages([AuditLogPage(entries: [entry("new"), entry("baseline")], after: "rebuilt", before: nil),
               AuditLogPage(entries: [], after: "rebuilt-end", before: nil)])
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(notifications.count, 1)
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
        XCTAssertEqual(try checkpoint().cursor, "rebuilt-end")
    }

    func testNewEventInSameSecondAsPreviousPollIsNotLost() async throws {
        try seed()
        let poller = makePoller()
        pages([AuditLogPage(entries: [entry("one")], after: "page", before: nil), AuditLogPage(entries: [], after: "end", before: nil)])
        try await poller.startPolling(for: account)?.value
        pages([AuditLogPage(entries: [entry("two"), entry("one")], after: "page2", before: nil), AuditLogPage(entries: [], after: "end2", before: nil)])
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(notifications[1].events.map(\.id), ["two"])
    }

    func testReviewedLoginsAreExcludedFromBothNotificationAndCard() async throws {
        try seed()
        reviewedDate = Date(timeIntervalSince1970: 100)
        pages([AuditLogPage(entries: [entry("later", date: 101), entry("reviewed", date: 100)], after: "page", before: nil),
               AuditLogPage(entries: [], after: "end", before: nil)])
        let poller = makePoller()
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].events.map(\.id), ["later"])
        XCTAssertEqual(try checkpoint().pendingEvents.map(\.id), ["later"])
        XCTAssertEqual(try checkpoint().recentEventIDs, ["later", "reviewed"])
    }

    func testUnreadableUnsupportedAndUnknownEntriesAdvanceCursorWithoutNotifying() async throws {
        try seed()
        pages([AuditLogPage(entries: [.unreadable(id: "encrypted", reason: .keyUnavailable),
                                     .unsupportedVersion(id: "future", version: "2"), .unknownType(id: "unknown", type: "future")],
                           after: "page", before: nil), AuditLogPage(entries: [], after: "end", before: nil)])
        let poller = makePoller()
        try await poller.startPolling(for: account)?.value
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
        XCTAssertEqual(try checkpoint().cursor, "end")
        XCTAssertEqual(try checkpoint().recentEventIDs, ["encrypted", "future", "unknown"])
    }

    func testRecentRawIDsAreBoundedToTheNewestHundredAcrossPagesAndEmptyPolls() async throws {
        try seed()
        let older = (0..<60).reversed().map { AuditLogEntryDecodingResult.unreadable(id: "event-\($0)", reason: .keyUnavailable) }
        let newer = (60..<120).reversed().map { AuditLogEntryDecodingResult.unreadable(id: "event-\($0)", reason: .keyUnavailable) }
        pages([AuditLogPage(entries: older, after: "page1", before: nil), AuditLogPage(entries: newer, after: "page2", before: nil),
               AuditLogPage(entries: [], after: "end", before: nil)])
        let poller = makePoller()
        try await poller.startPolling(for: account)?.value
        let expected = (20..<120).reversed().map { "event-\($0)" }
        XCTAssertEqual(try checkpoint().recentEventIDs, expected)
        pages([AuditLogPage(entries: [], after: "empty", before: nil)])
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(try checkpoint().recentEventIDs, expected)
    }

    func testNoOpDismissalOrReviewDoesNotPublishStateChange() throws {
        try seed(pending: [pending("pending")])
        let poller = makePoller()
        var updates = 0
        let subscription = poller.stateDidChange.sink { updates += 1 }
        defer { subscription.cancel() }
        try poller.dismissEvents(withIDs: ["not-present"], for: account.userId)
        try poller.removeReviewedEvents(through: Date(timeIntervalSince1970: 0), for: account.userId)
        XCTAssertEqual(updates, 0)
        try poller.dismissEvents(withIDs: ["pending"], for: account.userId)
        XCTAssertEqual(updates, 1)
    }

    private func assertCheckpointRecovery(from data: Data, readPendingFirst: Bool = false) async throws {
        let key = AuditLogPoller.checkpointKey(for: account.userId)
        try store.set(data, forKey: key)
        manager.fetchAuditLogStub = AuditLogPage(entries: [entry("historical")], after: "fresh-baseline", before: nil)
        let poller = makePoller()
        if readPendingFirst {
            XCTAssertTrue(try poller.pendingEvents(for: account.userId).isEmpty)
            XCTAssertNil(try store.object(forKey: key))
        }
        try await poller.startPolling(for: account)?.value
        XCTAssertEqual(manager.fetchAuditLogCalls.count, 1)
        XCTAssertNil(manager.fetchAuditLogCalls.first?.1)
        XCTAssertEqual(try checkpoint().cursor, "fresh-baseline")
        XCTAssertEqual(try checkpoint().recentEventIDs, ["historical"])
        XCTAssertTrue(try checkpoint().pendingEvents.isEmpty)
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }

    func testOldDraftCheckpointReinitializesWithoutHistoricalNotification() async throws {
        try await assertCheckpointRecovery(from: Data(#"{"cursor":"old-draft","pendingEvents":[]}"#.utf8), readPendingFirst: true)
    }

    func testCorruptCheckpointReinitializesWithoutHistoricalNotification() async throws {
        try await assertCheckpointRecovery(from: Data("{broken JSON".utf8))
    }

    func testCheckpointStorageReadFailureDoesNotDiscardValidState() async throws {
        try seed(pending: [pending("pending")])
        let key = AuditLogPoller.checkpointKey(for: account.userId)
        let original = try XCTUnwrap(try store.object(forKey: key) as? Data)
        store.throwOnRead = NSError(domain: "test", code: 1)
        let poller = makePoller()
        XCTAssertThrowsError(try poller.pendingEvents(for: account.userId))
        let result = await poller.startPolling(for: account)?.result
        XCTAssertThrowsError(try result?.get())
        XCTAssertTrue(manager.fetchAuditLogCalls.isEmpty)
        XCTAssertEqual(errors.count, 1)
        store.throwOnRead = nil
        XCTAssertEqual(try store.object(forKey: key) as? Data, original)
    }

}
