//
//  AuditLogPollingIntegrationTests.swift
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

import Combine
import XCTest
import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import DDGSync

@MainActor
final class AuditLogPollingIntegrationTests: XCTestCase {
    private var dependencies: MockSyncDependencies!
    private var store: PollingStore!
    private var source: MockDataProvidersSource!
    private var accountManager: AccountManagingMock { dependencies.account as! AccountManagingMock }
    private var cursorKey: String { AuditLogPoller.cursorKey(for: SyncAccount.mock.userId) }

    override func setUpWithError() throws {
        dependencies = MockSyncDependencies()
        dependencies.isLoginAuditLogEnabled = { true }
        store = PollingStore()
        dependencies.keyValueStore = store
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock
        try store.set(true, forKey: DDGSync.Constants.syncEnabledKey)
        source = MockDataProvidersSource()
    }

    private func makeService() -> DDGSync {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        service.initializeIfNeeded()
        return service
    }

    private func requestSync(_ service: DDGSync, expectingCursor cursor: String) async throws {
        let saved = expectation(description: "Cursor saved: \(cursor)")
        store.onSet = { [cursorKey] key, value in
            if key == cursorKey, value as? String == cursor { saved.fulfill() }
        }
        service.scheduler.requestSyncImmediately()
        await fulfillment(of: [saved], timeout: 2)
        store.onSet = nil
        // The checkpoint is written just before the tracked task finishes. Wait for that task to release its slot.
        service.scheduler.cancelSyncAndSuspendSyncQueue()
        service.scheduler.resumeSyncQueue()
    }

    func testSchedulerInitializesPollingAndNextSyncUsesSavedCursorWithoutAdvancingReviewDate() async throws {
        let date = Date(timeIntervalSince1970: 100)
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [
            .decoded(AuditLogEvent(id: "newest", type: .login, occurredAt: date, device: .mock, actor: nil, hasDeviceInfo: false))
        ], after: "initial", before: "history")
        let service = makeService()
        try await requestSync(service, expectingCursor: "initial")
        XCTAssertEqual(try service.auditLogReviewState(for: SyncAccount.mock.userId)?.reviewedThrough, date)

        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: "polled", before: nil)
        try await requestSync(service, expectingCursor: "polled")

        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 2)
        guard case .after("initial") = accountManager.fetchAuditLogCalls[1].1 else { return XCTFail("Expected forward cursor") }
        XCTAssertEqual(try service.auditLogReviewState(for: SyncAccount.mock.userId)?.reviewedThrough, date)
    }

    func testScreenFetchDoesNotChangePollingCursor() async throws {
        let service = makeService()
        try await requestSync(service, expectingCursor: "cursor")
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: "screen-head", before: "screen-older")

        let reader = try service.makeAuditLogReader()
        let page = try await reader.nextPage()
        XCTAssertTrue(page.hasMore)
        XCTAssertNil(accountManager.fetchAuditLogCalls.last?.1)
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: "screen-head", before: nil)
        let olderPage = try await reader.nextPage()

        XCTAssertFalse(olderPage.hasMore)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "cursor")
        guard case .before("screen-older") = accountManager.fetchAuditLogCalls.last?.1 else { return XCTFail("Expected backward cursor") }
    }

    func testInitialPollingPreservesExistingReviewDate() async throws {
        let service = makeService()
        let reviewed = SyncAuditLogReviewState(reviewedThrough: Date(timeIntervalSince1970: 50), isInitialized: true)
        try service.setAuditLogReviewState(reviewed, for: SyncAccount.mock.userId)
        try await requestSync(service, expectingCursor: "cursor")

        XCTAssertEqual(try service.auditLogReviewState(for: SyncAccount.mock.userId), reviewed)
    }

    func testEmptyInitialPollingSeedsInitializedReviewState() async throws {
        let service = makeService()
        try await requestSync(service, expectingCursor: "cursor")

        XCTAssertEqual(try service.auditLogReviewState(for: SyncAccount.mock.userId),
                       SyncAuditLogReviewState(reviewedThrough: nil, isInitialized: true))
    }

    func testAuditLogFlagChangesTakeEffectOnNextSync() async throws {
        dependencies.isLoginAuditLogEnabled = { false }
        let service = makeService()
        service.scheduler.requestSyncImmediately()
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)

        dependencies.isLoginAuditLogEnabled = { true }
        try await requestSync(service, expectingCursor: "cursor")
        dependencies.isLoginAuditLogEnabled = { false }
        service.scheduler.requestSyncImmediately()
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "cursor")

        dependencies.isLoginAuditLogEnabled = { true }
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: "enabled-again", before: nil)
        try await requestSync(service, expectingCursor: "enabled-again")
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 2)
    }

    func testRuntimeFlagDisableCancelsPendingPollAndLateResponseIsDiscarded() async throws {
        let started = expectation(description: "Poll started")
        let finished = expectation(description: "Late response returned")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        accountManager.fetchAuditLogHandler = { _, _, _ in
            started.fulfill()
            await withCheckedContinuation { response in
                Task.detached {
                    for await _ in gate { break }
                    response.resume()
                }
            }
            finished.fulfill()
            return AuditLogPage(entries: [], after: "discarded", before: nil)
        }
        let service = makeService()
        service.scheduler.requestSyncImmediately()
        await fulfillment(of: [started], timeout: 2)
        dependencies.isLoginAuditLogEnabled = { false }
        (dependencies.privacyConfigurationManager as! MockPrivacyConfigurationManager).updatesSubject.send(())
        continuation.yield(())
        continuation.finish()
        await fulfillment(of: [finished], timeout: 2)
        // A second request stays disabled and cannot create a cursor.
        service.scheduler.requestSyncImmediately()
        XCTAssertNil(try store.object(forKey: cursorKey))
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
    }

    func testDataSyncingKillSwitchBlocksPollingAtStartupAndCanChangeAtRuntime() async throws {
        let config = PrivacyConfigTestsUtils.MockPrivacyConfiguration()
        config.isSubfeatureEnabledCheck = { flag, _ in flag.rawValue != SyncSubfeature.level1AllowDataSyncing.rawValue }
        let manager = dependencies.privacyConfigurationManager as! MockPrivacyConfigurationManager
        manager.privacyConfig = config
        let service = makeService()
        service.scheduler.requestSyncImmediately()
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        XCTAssertNil(try store.object(forKey: cursorKey))

        config.isSubfeatureEnabledCheck = { _, _ in true }
        manager.updatesSubject.send(())
        try await requestSync(service, expectingCursor: "cursor")
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)

        config.isSubfeatureEnabledCheck = { flag, _ in flag.rawValue != SyncSubfeature.level1AllowDataSyncing.rawValue }
        manager.updatesSubject.send(())
        service.scheduler.requestSyncImmediately()
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
    }

    func testSuspendedSchedulerDoesNotPollUntilResumed() async throws {
        let service = makeService()
        service.scheduler.cancelSyncAndSuspendSyncQueue()
        service.scheduler.requestSyncImmediately()
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)

        service.scheduler.resumeSyncQueue()
        try await requestSync(service, expectingCursor: "cursor")
    }

    func testLogoutClearsPollingCursorAndReviewState() async throws {
        let migration = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migration
        let service = makeService()
        try await requestSync(service, expectingCursor: "cursor")
        let secureStore = dependencies.secureStore
        let cursorKey = self.cursorKey
        var didClearCursor = false
        store.onRemove = { [weak store] key in
            guard key == cursorKey else { return }
            didClearCursor = true
            do {
                XCTAssertNil(try secureStore.account())
                XCTAssertEqual(migration.resetCallCount, 1)
                XCTAssertNil(try store?.object(forKey: DDGSync.Constants.syncEnabledKey))
            } catch {
                XCTFail("Unable to inspect account cleanup: \(error)")
            }
        }

        try await service.disconnect()

        XCTAssertTrue(didClearCursor)
        XCTAssertNil(try store.object(forKey: cursorKey))
        XCTAssertNil(try service.auditLogReviewState(for: SyncAccount.mock.userId))
        XCTAssertEqual(service.authState, .inactive)
    }

    func testLogoutStillClearsAuditStateWhenSyncEnabledWriteFails() async throws {
        let service = makeService()
        try await requestSync(service, expectingCursor: "cursor")
        let expectedError = NSError(domain: "test", code: 1)
        store.onSet = { key, value in
            if key == DDGSync.Constants.syncEnabledKey, value == nil { throw expectedError }
        }

        do {
            try await service.disconnect()
            XCTFail("Expected the Sync flag write failure")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }

        XCTAssertNil(service.account)
        XCTAssertNil(try store.object(forKey: cursorKey))
        XCTAssertNil(try service.auditLogReviewState(for: SyncAccount.mock.userId))
    }

    func testUnauthorizedPollingPreservesAccountAndCursor() async throws {
        accountManager.fetchAuditLogError = SyncError.unexpectedStatusCode(401)
        try store.set("old", forKey: cursorKey)
        let service = makeService()
        do {
            _ = try await service.pollAuditLog()
            XCTFail("Expected the request error")
        } catch {
            guard case SyncError.unexpectedStatusCode(401) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertNotNil(service.account)
        XCTAssertEqual(service.authState, .active)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "old")
    }

    func testPollingDoesNotRequireEngineInitialization() async throws {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        XCTAssertTrue(try service.isAuditLogPollingAvailable())
        let completed = try await service.pollAuditLog()
        XCTAssertTrue(completed)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "cursor")
        XCTAssertEqual(service.authState, .initializing)
        XCTAssertEqual(source.makeDataProvidersCallCount, 0)
    }

    func testPollingWorksWhileNormalSyncRemainsSuspended() async throws {
        let service = makeService()
        service.scheduler.cancelSyncAndSuspendSyncQueue()
        let completed = try await service.pollAuditLog()
        XCTAssertTrue(completed)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "cursor")
        service.scheduler.requestSyncImmediately()
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
    }

    func testUnavailableEnabledMarkerPreservesStateAndRetriesLater() async throws {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        try store.set("old", forKey: cursorKey)
        let expectedError = NSError(domain: "storage", code: 1)
        store.onRead = { key in
            if key == DDGSync.Constants.syncEnabledKey { throw expectedError }
        }
        do {
            _ = try await service.pollAuditLog()
            XCTFail("Expected the storage error")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        XCTAssertNotNil((dependencies.secureStore as! SecureStorageStub).theAccount)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "old")
        store.onRead = nil
        let completed = try await service.pollAuditLog()
        XCTAssertTrue(completed)
    }

    func testUnavailableAccountPreservesCredentialsAndRetriesLater() async throws {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        let secureStore = dependencies.secureStore as! SecureStorageStub
        try store.set("old", forKey: cursorKey)
        secureStore.mockReadError = .failedToReadSecureStore(status: -25308)
        do {
            _ = try await service.pollAuditLog()
            XCTFail("Expected the keychain error")
        } catch {
            guard case SyncError.failedToReadSecureStore = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        XCTAssertNotNil(secureStore.theAccount)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "old")
        secureStore.mockReadError = nil
        let completed = try await service.pollAuditLog()
        XCTAssertTrue(completed)
    }

    func testUnavailableCheckpointDoesNotFetchOrReplaceState() async throws {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        try store.set("old", forKey: cursorKey)
        let expectedError = NSError(domain: "storage", code: 1)
        store.onRead = { [cursorKey] key in
            if key == cursorKey { throw expectedError }
        }
        do {
            _ = try await service.pollAuditLog()
            XCTFail("Expected the checkpoint read error")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        store.onRead = nil
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "old")
        let completed = try await service.pollAuditLog()
        XCTAssertTrue(completed)
    }

    func testSuspendingForegroundSyncDoesNotCancelIndependentPoll() async throws {
        let service = makeService()
        let started = expectation(description: "Independent poll started")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        accountManager.fetchAuditLogHandler = { _, _, _ in
            started.fulfill()
            for await _ in gate { break }
            return AuditLogPage(entries: [], after: "independent", before: nil)
        }
        let poll = Task { try await service.pollAuditLog() }
        await fulfillment(of: [started], timeout: 1)
        service.scheduler.cancelSyncAndSuspendSyncQueue()
        continuation.yield(())
        continuation.finish()
        let completed = try await poll.value
        XCTAssertTrue(completed)
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "independent")
    }

    func testMissingEnabledMarkerSkipsPollingWithoutRemovingAccount() async throws {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        try store.removeObject(forKey: DDGSync.Constants.syncEnabledKey)
        XCTAssertFalse(try service.isAuditLogPollingAvailable())
        let completed = try await service.pollAuditLog()
        XCTAssertFalse(completed)
        XCTAssertTrue(accountManager.fetchAuditLogCalls.isEmpty)
        XCTAssertNotNil((dependencies.secureStore as! SecureStorageStub).theAccount)
    }

    func testChangedCredentialsDiscardLateResponse() async throws {
        let service = DDGSync(dataProvidersSource: source, dependencies: dependencies)
        try store.set("old", forKey: cursorKey)
        let secureStore = dependencies.secureStore as! SecureStorageStub
        accountManager.fetchAuditLogHandler = { account, _, _ in
            secureStore.theAccount = SyncAccount(deviceId: account.deviceId, deviceName: account.deviceName, deviceType: account.deviceType,
                                                userId: account.userId, primaryKey: account.primaryKey, secretKey: account.secretKey,
                                                token: "replacement", state: .active)
            return AuditLogPage(entries: [], after: "stale", before: nil)
        }
        do {
            _ = try await service.pollAuditLog()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertEqual(try store.object(forKey: cursorKey) as? String, "old")
        XCTAssertEqual(secureStore.theAccount?.token, "replacement")
    }

    func testInitializingWithSyncDisabledClearsCursorWhenCredentialsAreRemoved() throws {
        try store.set("old", forKey: cursorKey)
        try store.removeObject(forKey: DDGSync.Constants.syncEnabledKey)
        let migration = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migration
        let secureStore = dependencies.secureStore
        let cursorKey = self.cursorKey
        var didClearCursor = false
        store.onRemove = { key in
            guard key == cursorKey else { return }
            didClearCursor = true
            do {
                XCTAssertNil(try secureStore.account())
                XCTAssertEqual(migration.resetCallCount, 1)
            } catch {
                XCTFail("Unable to inspect account cleanup: \(error)")
            }
        }
        let service = makeService()

        XCTAssertTrue(didClearCursor)
        XCTAssertNil(service.account)
        XCTAssertNil(try store.object(forKey: cursorKey))
    }
}

private final class PollingStore: ThrowingKeyValueStoring {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    var onRead: ((String) throws -> Void)?
    var onSet: ((String, Any?) throws -> Void)?
    var onRemove: ((String) -> Void)?

    func object(forKey key: String) throws -> Any? {
        try onRead?(key)
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: Any?, forKey key: String) throws {
        lock.lock()
        values[key] = value
        lock.unlock()
        try onSet?(key, value)
    }

    func removeObject(forKey key: String) throws {
        lock.lock()
        values[key] = nil
        lock.unlock()
        onRemove?(key)
    }
}
