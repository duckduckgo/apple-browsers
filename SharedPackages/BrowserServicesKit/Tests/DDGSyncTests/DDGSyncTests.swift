//
//  DDGSyncTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import CryptoKit
import XCTest
@_spi(Testing) import Persistence

@testable import DDGSync

enum SyncOperationEvent: Equatable {
    case started(_ taskID: Int)
    case fetch(_ taskID: Int)
    case handleResponse(_ taskID: Int)
    case finished(_ taskID: Int)
}

final class DDGSyncTests: XCTestCase {
    var dataProvidersSource: MockDataProvidersSource!
    var dependencies: MockSyncDependencies!

    var syncStartedExpectation: XCTestExpectation!
    var fetchExpectation: XCTestExpectation!
    var handleSyncResponseExpectation: XCTestExpectation!
    var syncFinishedExpectation: XCTestExpectation!
    var isInProgressCancellable: AnyCancellable?
    var recordedEvents: [SyncOperationEvent] = []
    var taskID = 1

    override func setUpWithError() throws {
        try super.setUpWithError()

        recordedEvents = []
        taskID = 1

        dataProvidersSource = MockDataProvidersSource()
        dependencies = MockSyncDependencies()
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [
            URL(string: "https://dev.null/sync/credentials")!: HTTPRequestingMock(result: .init(data: "{\"credentials\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())),
            URL(string: "https://dev.null/sync/bookmarks")!: HTTPRequestingMock(result: .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())),
            URL(string: "https://dev.null/sync/data")!: HTTPRequestingMock(result: .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]},\"credentials\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init()))
        ]

        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)
    }

    override func tearDownWithError() throws {
        isInProgressCancellable?.cancel()
        isInProgressCancellable = nil

        try super.tearDownWithError()
    }

    // MARK: - Setup

    func setUpExpectations(started syncStartedExpectedCount: Int, fetch fetchExpectedCount: Int, handleResponse handleSyncResponseExpectedCount: Int, finished syncFinishedExpectedCount: Int) {
        if syncStartedExpectedCount > 0 {
            syncStartedExpectation = expectation(description: "syncStarted")
            syncStartedExpectation.expectedFulfillmentCount = syncStartedExpectedCount
        }

        if fetchExpectedCount > 0 {
            fetchExpectation = expectation(description: "fetch")
            fetchExpectation.expectedFulfillmentCount = fetchExpectedCount
        }

        if handleSyncResponseExpectedCount > 0 {
            handleSyncResponseExpectation = expectation(description: "handleSyncResponse")
            handleSyncResponseExpectation.expectedFulfillmentCount = handleSyncResponseExpectedCount
        }

        if syncFinishedExpectedCount > 0 {
            syncFinishedExpectation = expectation(description: "syncFinished")
            syncFinishedExpectation.expectedFulfillmentCount = syncFinishedExpectedCount
        }
    }

    func setUpDataProviderCallbacks(for dataProvider: DataProvidingMock) {
        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": self.taskID])]
            self.recordedEvents.append(.fetch(self.taskID))
            self.fetchExpectation.fulfill()
            return syncables
        }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            let taskID = sent[0].payload["taskNumber"] as! Int
            self.recordedEvents.append(.handleResponse(taskID))
            self.handleSyncResponseExpectation.fulfill()
        }
    }

    func bindInProgressPublisher(for syncService: DDGSyncing) {
        isInProgressCancellable = syncService.isSyncInProgressPublisher.sink { isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
            } else {
                self.recordedEvents.append(.finished(self.taskID))
                self.syncFinishedExpectation.fulfill()
                self.taskID += 1
            }
        }
    }

    // MARK: - Tests

    func testAuditLogDumpForDebugWithoutAccountThrows() async {
        (dependencies.secureStore as! SecureStorageStub).theAccount = nil
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        do {
            _ = try await syncService.auditLogDumpForDebug()
            XCTFail("Expected missing account to throw")
        } catch let error as SyncError {
            XCTAssertEqual(error, .accountNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuditLogDumpForDebugPropagatesRequestFailure() async {
        let accountManager = dependencies.account as! AccountManagingMock
        accountManager.fetchAuditLogError = SyncError.unexpectedStatusCode(418)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        do {
            _ = try await syncService.auditLogDumpForDebug()
            XCTFail("Expected request failure to throw")
        } catch let error as SyncError {
            XCTAssertEqual(error, .unexpectedStatusCode(418))
            XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuditLogDumpForDebugDumpsDecodedPageReturnedByAccountManager() async throws {
        let accountManager = dependencies.account as! AccountManagingMock
        accountManager.fetchAuditLogStub = AuditLogPage(
            entries: [.unreadable(id: "event-id", reason: .keyUnavailable)],
            after: "head-cursor",
            before: "older-cursor")
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let report = try await syncService.auditLogDumpForDebug()

        XCTAssertTrue(report.contains("event-id"))
        XCTAssertTrue(report.contains("head-cursor"))
        XCTAssertTrue(report.contains("older-cursor"))
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 1)
        XCTAssertNil(accountManager.fetchAuditLogCalls.first?.1)
        XCTAssertNil(accountManager.fetchAuditLogCalls.first?.2)
    }

    @MainActor
    func testMakeAuditLogReaderWithoutAccountThrows() {
        (dependencies.secureStore as! SecureStorageStub).theAccount = nil
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        XCTAssertThrowsError(try syncService.makeAuditLogReader()) { error in
            XCTAssertEqual(error as? SyncError, .accountNotFound)
        }
    }

    @MainActor
    func testAuditLogReaderMapsEventsAndOwnsBeforeCursor() async throws {
        let accountManager = dependencies.account as! AccountManagingMock
        let device = RegisteredDevice(id: "device-id", name: "iPhone", type: "phone")
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [
            .decoded(AuditLogEvent(id: "login-id", type: .login, occurredAt: Date(timeIntervalSince1970: 10),
                                   device: device, actor: nil, hasDeviceInfo: false)),
            .decoded(AuditLogEvent(id: "logout-id", type: .logout, occurredAt: Date(timeIntervalSince1970: 20),
                                   device: device, actor: nil, hasDeviceInfo: false)),
            .unknownType(id: "ignored-id", type: "future")
        ], after: "head-cursor", before: "older-cursor")
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let reader = try syncService.makeAuditLogReader()

        let page = try await reader.nextPage()
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: nil, before: nil)
        let last = try await reader.nextPage()
        _ = try await reader.nextPage()

        XCTAssertEqual(page.events.map(\.id), ["login-id", "logout-id"])
        XCTAssertEqual(page.events.map(\.kind), [.synced, .removed])
        XCTAssertTrue(page.hasMore)
        XCTAssertFalse(last.hasMore)
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, 2)
        XCTAssertEqual(accountManager.fetchAuditLogCalls.first?.2, 100)
        XCTAssertNil(accountManager.fetchAuditLogCalls.first?.1)
        guard case .before("older-cursor") = accountManager.fetchAuditLogCalls[1].1 else {
            return XCTFail("Expected the reader to use its own before cursor")
        }
    }

    @MainActor
    func testAuditLogReaderUsesOldestInfoBetweenLoginsAcrossPages() async throws {
        let reader = auditLogReader(pages: [
            AuditLogPage(entries: [
                auditLogEntry("too-new", .deviceInfoAdded, 6, name: "After next login", hasInfo: true),
                auditLogEntry("logout", .logout, 5, name: "Logout name"),
                auditLogEntry("relogin", .login, 4, name: "Own info", hasInfo: true),
                auditLogEntry("later-info", .deviceInfoAdded, 3, name: "Later info", hasInfo: true),
                auditLogEntry("first-info", .deviceInfoAdded, 2, name: "First info", hasInfo: true),
                auditLogEntry("orphan", .deviceInfoAdded, 1.5, name: "Other device", deviceID: "other", hasInfo: true)
            ], after: nil, before: "older"),
            AuditLogPage(entries: [auditLogEntry("first-login", .login, 1), auditLogEntry("earlier-login", .login, 0),
                                   auditLogEntry("older-logout", .logout, -1)], after: nil, before: nil)
        ])

        let first = try await reader.nextPage()
        let older = try await reader.nextPage()

        XCTAssertEqual(first.events.map(\.id), ["logout", "relogin"])
        XCTAssertEqual(first.events.map { $0.device.name }, ["Logout name", "Own info"])
        XCTAssertEqual(older.events.map { $0.device.name }, ["First info", "Legacy", "Legacy"])
        XCTAssertEqual(older.events.first?.device.id, "device")
        XCTAssertEqual(older.events.first?.device.credentialId, "3party")
        XCTAssertFalse(older.hasMore)
    }

    @MainActor
    func testAuditLogReaderUsesStreamOrderForSameSecondEvents() async throws {
        let cases: [(entries: [AuditLogEntryDecodingResult], names: [String])] = [
            ([auditLogEntry("info", .deviceInfoAdded, 1, name: "Same second", hasInfo: true),
              auditLogEntry("login", .login, 1)], ["Same second"]),
            ([auditLogEntry("newer-login", .login, 1),
              auditLogEntry("info", .deviceInfoAdded, 1, name: "Between logins", hasInfo: true),
              auditLogEntry("older-login", .login, 1)], ["Legacy", "Between logins"]),
            ([auditLogEntry("newer-info", .deviceInfoAdded, 1, name: "Newer", hasInfo: true),
              auditLogEntry("older-info", .deviceInfoAdded, 1, name: "Oldest", hasInfo: true),
              auditLogEntry("login", .login, 1)], ["Oldest"]),
            ([auditLogEntry("readable-info", .deviceInfoAdded, 1, name: "Readable", hasInfo: true),
              auditLogEntry("unreadable-info", .deviceInfoAdded, 1),
              auditLogEntry("login", .login, 1)], ["Legacy"])
        ]
        for testCase in cases {
            let reader = auditLogReader(pages: [AuditLogPage(entries: testCase.entries, after: nil, before: nil)])
            let page = try await reader.nextPage()
            XCTAssertEqual(page.events.map { $0.device.name }, testCase.names)
        }
    }

    @MainActor
    func testAuditLogReaderDeduplicatesBeforeChangingPendingCandidates() async throws {
        let reader = auditLogReader(pages: [
            AuditLogPage(entries: [auditLogEntry("relogin", .login, 1),
                                   auditLogEntry("newer-info", .deviceInfoAdded, 1, name: "Newer", hasInfo: true),
                                   auditLogEntry("oldest-info", .deviceInfoAdded, 1, name: "Oldest", hasInfo: true)],
                         after: nil, before: "older"),
            AuditLogPage(entries: [auditLogEntry("relogin", .login, 1),
                                   auditLogEntry("newer-info", .deviceInfoAdded, 1, name: "Newer", hasInfo: true),
                                   auditLogEntry("first-login", .login, 1)], after: nil, before: nil)
        ])
        _ = try await reader.nextPage()
        let older = try await reader.nextPage()

        XCTAssertEqual(older.events.map(\.id), ["first-login"])
        XCTAssertEqual(older.events.first?.device.name, "Oldest")
    }

    @MainActor
    func testAuditLogReaderKeepsCursorAndCandidatesWhenFetchFails() async throws {
        var cursors = [String?]()
        let reader = SyncAuditLogReader(account: .mock) { _, cursor in
            cursors.append(cursor)
            if cursor == nil {
                return AuditLogPage(entries: [self.auditLogEntry("info", .deviceInfoAdded, 1, name: "Enriched", hasInfo: true)],
                                    after: nil, before: "older")
            }
            if cursors.count == 2 { throw SyncError.unexpectedStatusCode(418) }
            return AuditLogPage(entries: [self.auditLogEntry("login", .login, 1)], after: nil, before: nil)
        }
        let first = try await reader.nextPage()
        XCTAssertTrue(first.events.isEmpty)
        do {
            _ = try await reader.nextPage()
            XCTFail("Expected the failed fetch to propagate")
        } catch {
            XCTAssertEqual(error as? SyncError, .unexpectedStatusCode(418))
        }
        let retried = try await reader.nextPage()

        XCTAssertEqual(cursors, [nil, "older", "older"])
        XCTAssertEqual(retried.events.first?.device.name, "Enriched")
    }

    @MainActor
    func testAuditLogReaderRejectsCancelledResponseWithoutAdvancing() async throws {
        var continuation: CheckedContinuation<AuditLogPage, Never>?
        var cursors = [String?]()
        let reader = SyncAuditLogReader(account: .mock) { _, cursor in
            cursors.append(cursor)
            if cursors.count == 1 {
                return await withCheckedContinuation { continuation = $0 }
            }
            return AuditLogPage(entries: [self.auditLogEntry("login", .login, 1)], after: nil, before: nil)
        }
        let request = Task { try await reader.nextPage() }
        while continuation == nil { await Task.yield() }
        request.cancel()
        continuation?.resume(returning: AuditLogPage(entries: [auditLogEntry("login", .login, 1)], after: nil, before: "older"))
        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        let retried = try await reader.nextPage()
        XCTAssertEqual(cursors, [nil, nil])
        XCTAssertEqual(retried.events.map(\.id), ["login"])
    }

    @MainActor
    func testAuditLogReaderStopsOnRepeatedCursor() async throws {
        var requests = 0
        let reader = SyncAuditLogReader(account: .mock) { _, _ in
            requests += 1
            return AuditLogPage(entries: [], after: nil, before: "same")
        }
        let first = try await reader.nextPage()
        let second = try await reader.nextPage()
        let exhausted = try await reader.nextPage()
        XCTAssertTrue(first.hasMore)
        XCTAssertFalse(second.hasMore)
        XCTAssertFalse(exhausted.hasMore)
        XCTAssertEqual(requests, 2)
    }

    @MainActor
    func testAuditLogReadersAreIsolatedByVisitAndBoundToStartingAccount() async throws {
        let accountManager = dependencies.account as! AccountManagingMock
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [auditLogEntry("info", .deviceInfoAdded, 1, name: "Enriched", hasInfo: true)],
                                                       after: nil, before: "older")
        let reader = try syncService.makeAuditLogReader()
        _ = try await reader.nextPage()
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [auditLogEntry("login", .login, 1)], after: nil, before: nil)
        let freshReader = try syncService.makeAuditLogReader()
        let fresh = try await freshReader.nextPage()
        let older = try await reader.nextPage()
        XCTAssertEqual(fresh.events.first?.device.name, "Legacy")
        XCTAssertEqual(older.events.first?.device.name, "Enriched")

        let previousAccount = SyncAccount.mock
        (dependencies.secureStore as! SecureStorageStub).theAccount = nil
        let calls = accountManager.fetchAuditLogCalls.count
        do {
            _ = try syncService.makeAuditLogReader()
            XCTFail("Expected missing account")
        } catch {
            XCTAssertEqual(error as? SyncError, .accountNotFound)
        }
        // A reader created before logout must not issue another request with the old account.
        (dependencies.secureStore as! SecureStorageStub).theAccount = previousAccount
        accountManager.fetchAuditLogStub = AuditLogPage(entries: [], after: nil, before: "older")
        let pendingReader = try syncService.makeAuditLogReader()
        (dependencies.secureStore as! SecureStorageStub).theAccount = nil
        do {
            _ = try await pendingReader.nextPage()
            XCTFail("Expected the old account reader to be rejected")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(accountManager.fetchAuditLogCalls.count, calls)
    }

    @MainActor
    func testAuditLogReaderDiscardsAuthenticationFailureAfterAccountChanges() async throws {
        let secureStore = dependencies.secureStore as! SecureStorageStub
        let accountManager = dependencies.account as! AccountManagingMock
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let reader = try syncService.makeAuditLogReader()
        let replacement = SyncAccount(deviceId: "new-device", deviceName: "New Device", deviceType: "phone", userId: "new-account",
                                      primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        accountManager.fetchAuditLogHandler = { _, _, _ in
            secureStore.theAccount = replacement
            throw SyncError.unexpectedStatusCode(401)
        }

        do {
            _ = try await reader.nextPage()
            XCTFail("Expected the old account's response to be discarded")
        } catch is CancellationError {
            // Expected: an old request must not log out the replacement account.
        }
        XCTAssertEqual(secureStore.theAccount?.userId, replacement.userId)
    }

    @MainActor
    private func auditLogReader(pages: [AuditLogPage]) -> SyncAuditLogReader {
        var remainingPages = pages
        return SyncAuditLogReader(account: .mock) { _, _ in remainingPages.removeFirst() }
    }

    private func auditLogEntry(_ id: String, _ type: AuditLogEventType, _ time: TimeInterval,
                               name: String = "Legacy", deviceID: String = "device", hasInfo: Bool = false) -> AuditLogEntryDecodingResult {
        .decoded(AuditLogEvent(id: id, type: type, occurredAt: Date(timeIntervalSince1970: time),
                              device: RegisteredDevice(id: deviceID, name: name, type: "phone", credentialId: "3party"),
                              actor: nil, hasDeviceInfo: hasInfo))
    }

    func testRecoveryCodeWhenScopedAccessCredentialsAndPairingV2CodeAreEnabledReturnsV2Code() throws {
        dependencies.isScopedAccessCredentialsEnabled = { true }
        dependencies.isPairingV2CodeEnabled = { true }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let recoveryCode = try XCTUnwrap(syncService.recoveryCode)
        let syncCode = try SyncCode.decodeBase64URLString(recoveryCode)
        let expectedSyncCode = try SyncCode.decodeBase64String(try XCTUnwrap(SyncAccount.mock.recoveryCodeV2))

        XCTAssertEqual(syncCode.recovery, expectedSyncCode.recovery)
        guard case .v2(let payload) = syncCode.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(payload.cid, SyncCredentialID.defaultCredential)
        XCTAssertEqual(Base64URL.decode(payload.secret), SyncAccount.mock.primaryKey)
    }

    func testRecoveryCodeWhenPairingV2CodeIsDisabledReturnsLegacyV1Code() throws {
        dependencies.isScopedAccessCredentialsEnabled = { true }
        dependencies.isPairingV2CodeEnabled = { false }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let recoveryCode = try XCTUnwrap(syncService.recoveryCode)
        let syncCode = try SyncCode.decodeBase64String(recoveryCode)
        let expectedSyncCode = try SyncCode.decodeBase64String(try XCTUnwrap(SyncAccount.mock.legacyRecoveryCodeV1))

        XCTAssertEqual(syncCode.recovery, expectedSyncCode.recovery)
        XCTAssertNoThrow(try XCTUnwrap(syncCode.recovery).defaultCredentialRecoveryKey())
    }

    func testRecoveryCodeWhenPairingV2CodeIsEnabledAndPairingV2ScanningIsDisabledReturnsLegacyV1Code() throws {
        dependencies.isPairingV2CodeEnabled = { true }
        dependencies.isPairingV2ScanningEnabled = { false }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let recoveryCode = try XCTUnwrap(syncService.recoveryCode)
        let syncCode = try SyncCode.decodeBase64String(recoveryCode)
        let expectedSyncCode = try SyncCode.decodeBase64String(try XCTUnwrap(SyncAccount.mock.legacyRecoveryCodeV1))

        XCTAssertEqual(syncCode.recovery, expectedSyncCode.recovery)
        XCTAssertNoThrow(try XCTUnwrap(syncCode.recovery).defaultCredentialRecoveryKey())
    }

    func testRecoveryCodeWhenScopedAccessCredentialsAreDisabledAndPairingV2CodeIsEnabledReturnsV2Code() throws {
        dependencies.isScopedAccessCredentialsEnabled = { false }
        dependencies.isPairingV2CodeEnabled = { true }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let recoveryCode = try XCTUnwrap(syncService.recoveryCode)
        let syncCode = try SyncCode.decodeBase64URLString(recoveryCode)
        let expectedSyncCode = try SyncCode.decodeBase64String(try XCTUnwrap(SyncAccount.mock.recoveryCodeV2))

        XCTAssertEqual(syncCode.recovery, expectedSyncCode.recovery)
        guard case .v2(let payload) = syncCode.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(payload.cid, SyncCredentialID.defaultCredential)
    }

    func testThatRegularSyncOperationsAreSerialized() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 3, fetch: 3, handleResponse: 3, finished: 3)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 3)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch, .patch, .patch])
    }

    func testThatFirstSyncAndRegularSyncOperationsAreSerialized() {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 3, fetch: 3, handleResponse: 3, finished: 3)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 4)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.get, .patch, .patch, .patch])
    }

    func testWhenNewSyncAccountIsCreatedWithMultipleModelsThenInitialFetchDoesNotHappen() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.active)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 2)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch, .patch])
    }

    func testWhenDeviceIsAddedToExistingSyncAccountWithMultipleModelsThenInitialFetchHappens() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 4)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.get, .get, .patch, .patch])
    }

    /// Test initial fetch for newly added models.
    ///
    /// Start with:
    /// * Sync in active state
    /// * bookmarks provider that has been synced
    /// * credentials provider that hasn't been synced
    ///
    /// Request sync twice and test that:
    /// * the first sync operation calls 3 requests: initial for credentials, and regular for bookmarks and credentials
    /// * the second sync operation calls 2 request: regular sync for bookmarks and credentials
    func testThatWhenNewModelIsAddedThenItPerformsInitialFetch() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.active)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        try bookmarksDataProvider.registerFeature(withState: .readyToSync)
        bookmarksDataProvider.updateSyncTimestamps(server: "1234", local: nil)
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 2, fetch: 2, handleResponse: 2, finished: 2)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 5)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.get, .patch, .patch, .patch, .patch])
        XCTAssertEqual(api.createRequestCallArgs[0].url.lastPathComponent, "credentials")
    }

    func testWhenSyncOperationIsCancelledThenCurrentOperationReturnsEarlyAndOtherScheduledOperationsDoNotEmitSyncStarted() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 2, fetch: 1, handleResponse: 1, finished: 2)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        isInProgressCancellable = syncService.isSyncInProgressPublisher.sink { [weak syncService] isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
                if self.taskID == 2 {
                    syncService?.scheduler.cancelSyncAndSuspendSyncQueue()
                }
            } else {
                self.recordedEvents.append(.finished(self.taskID))
                self.syncFinishedExpectation.fulfill()
                self.taskID += 1
            }
        }

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .finished(2)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch])
    }

    func testWhenSyncQueueIsSuspendedThenNewOperationsDoNotStart() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        syncStartedExpectation.isInverted = true
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true
        syncFinishedExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs, [])
    }

    func testWhenSyncQueueIsResumedThenScheduledOperationStarts() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.resumeSyncQueue()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch])
    }

    func testWhenSyncGetsDisabledBeforeStartingOperationThenOperationReturnsEarly() throws {
        throw XCTSkip("Flakey test")
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        try dependencies.secureStore.removeAccount()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .finished(1),
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertTrue(api.createRequestCallArgs.isEmpty)
    }

    func testThatSyncOperationRequestReturningHTTP401CausesLoggingOutOfSync() throws {
        throw XCTSkip("Flakey test")
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 0, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [:]
        let http401Response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 401, httpVersion: nil, headerFields: [:])!
        dependencies.request.result = HTTPResult(data: Data(), response: http401Response)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        XCTAssertEqual(syncService.authState, .active)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 2)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .finished(1)
        ])

        XCTAssertEqual(syncService.authState, .inactive)
    }

    func testThatSyncOperationRequestThrowingHTTP401CausesLoggingOutOfSync() throws {
        throw XCTSkip("Flakey test")
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 0, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [:]
        dependencies.request.error = SyncError.unexpectedStatusCode(401)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        XCTAssertEqual(syncService.authState, .active)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .finished(1)
        ])

        XCTAssertEqual(syncService.authState, .inactive)
    }

    func testWhenRemovePreservedSyncAccountAndSyncIsActiveThenItDoesNothing() throws {
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertNotNil((dependencies.secureStore as! SecureStorageStub).theAccount)

        try syncService.removePreservedSyncAccount()

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertNotNil((dependencies.secureStore as! SecureStorageStub).theAccount)
        XCTAssertEqual((dependencies.errorEvents as! MockErrorHandler).handledErrors, [])
    }

    func testAuditLogReviewStateDecodesPersistedFields() throws {
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let accountID = SyncAccount.mock.userId
        let key = "\(DDGSync.Constants.auditLogReviewStateKey).\(accountID)"
        let fixtures: [(String, SyncAuditLogReviewState)] = [
            (#"{"reviewedThrough":12345,"isInitialized":true}"#,
             SyncAuditLogReviewState(reviewedThrough: Date(timeIntervalSinceReferenceDate: 12345), isInitialized: true)),
            (#"{"isInitialized":true}"#,
             SyncAuditLogReviewState(reviewedThrough: nil, isInitialized: true)),
            (#"{"reviewedThrough":null,"isInitialized":false}"#,
             SyncAuditLogReviewState(reviewedThrough: nil, isInitialized: false))
        ]
        for (json, expected) in fixtures {
            try dependencies.keyValueStore.set(Data(json.utf8), forKey: key)
            XCTAssertEqual(try syncService.auditLogReviewState(for: accountID), expected)
        }
    }

    func testAuditLogReviewStateIsAccountScopedAndDebugResetCanMoveItBackwards() throws {
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let futureDate = Date().addingTimeInterval(365 * 24 * 60 * 60)
        let reviewState = SyncAuditLogReviewState(reviewedThrough: futureDate, isInitialized: true)
        try syncService.setAuditLogReviewState(reviewState, for: SyncAccount.mock.userId)

        XCTAssertEqual(try syncService.auditLogReviewState(for: SyncAccount.mock.userId), reviewState)
        XCTAssertNil(try syncService.auditLogReviewState(for: "another-account"))
        try syncService.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: Date(), isInitialized: true),
                                                 for: SyncAccount.mock.userId)
        XCTAssertEqual(try syncService.auditLogReviewState(for: SyncAccount.mock.userId), reviewState)

        let resetDate = Date(timeIntervalSince1970: 12345)
        try syncService.resetAuditLogReviewStateForDebug(to: resetDate)
        XCTAssertEqual(try syncService.auditLogReviewState(for: SyncAccount.mock.userId)?.reviewedThrough, resetDate)
        XCTAssertLessThan(resetDate, futureDate)
    }

    func testAuditLogReviewStateIsClearedWhenAccountIsRemoved() throws {
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let account = SyncAccount.mock
        try syncService.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: Date(), isInitialized: true), for: account.userId)
        (dependencies.secureStore as! SecureStorageStub).theAccount = SyncAccount(deviceId: account.deviceId,
                                                                                   deviceName: account.deviceName,
                                                                                   deviceType: account.deviceType,
                                                                                   userId: account.userId,
                                                                                   primaryKey: account.primaryKey,
                                                                                   secretKey: account.secretKey,
                                                                                   token: account.token,
                                                                                   state: .inactive)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(try (dependencies.secureStore as! SecureStorageStub).account())
        XCTAssertNil(try syncService.auditLogReviewState(for: account.userId))
    }

    func testAccountRemovalContinuesWhenReviewStateCleanupFails() throws {
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        let account = SyncAccount.mock
        try syncService.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: Date(), isInitialized: true), for: account.userId)
        (dependencies.secureStore as! SecureStorageStub).theAccount = SyncAccount(deviceId: account.deviceId,
                                                                                   deviceName: account.deviceName,
                                                                                   deviceType: account.deviceType,
                                                                                   userId: account.userId,
                                                                                   primaryKey: account.primaryKey,
                                                                                   secretKey: account.secretKey,
                                                                                   token: account.token,
                                                                                   state: .inactive)
        (dependencies.keyValueStore as! MockKeyValueFileStore).throwOnRemove = MockKeyValueFileStore.MockError.removeError
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(try (dependencies.secureStore as! SecureStorageStub).account())
    }

    func testWhenLoginResponseContainsProtectedKeysThenAllKeysAreCached() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let protectedKeys = [
            makeProtectedKey(kid: "key-3party", encryptedWith: "3party"),
            makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg"),
            makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg"),
            makeProtectedKey(kid: "key-ddg-secondary", encryptedWith: "ddg")
        ]
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(account: .mock,
                                                                                devices: [],
                                                                                keys: protectedKeys)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                        deviceName: "iPhone",
                                        deviceType: "iOS")

        let cachedProtectedKeysData = try XCTUnwrap((dependencies.secureStore as? SecureStorageStub)?.theProtectedKeysData)
        let cachedProtectedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedProtectedKeysData)

        XCTAssertEqual(Set(cachedProtectedKeys.map(\.kid)), Set(["key-3party", "key-ddg", "key-ddg-secondary"]))
        XCTAssertEqual(Set(cachedProtectedKeys.map(\.encryptedWith)), Set(["3party", "ddg"]))
        XCTAssertEqual(cachedProtectedKeys.count, 3)
    }

    func testWhenAccountCreationSucceedsThenCurrentDeviceMigrationIsScheduled() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let migrationScheduled = expectation(description: "Device info migration scheduled")
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            migrationScheduled.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        try await syncService.createAccount(deviceName: "iPhone", deviceType: "iOS")
        await fulfillment(of: [migrationScheduled], timeout: 1)

        let migrationCall = try XCTUnwrap(migrationCoordinator.calls.first)
        XCTAssertEqual(migrationCall.account.deviceId, SyncAccount.mock.deviceId)
        XCTAssertTrue(migrationCoordinator.successfulUnifiedWriteCalls.isEmpty)
    }

    func testWhenAccountCreationPublishesDeviceInfoThenSuccessfulWriteIsRecordedWithoutSchedulingMigration() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.createAccountStub = AccountCreationResult(account: .mock,
                                                                  didPublishDeviceInfo: true)
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        try await syncService.createAccount(deviceName: "iPhone", deviceType: "iOS")

        XCTAssertTrue(migrationCoordinator.calls.isEmpty)
        XCTAssertEqual(migrationCoordinator.successfulUnifiedWriteCalls.map(\.account.deviceId),
                       [SyncAccount.mock.deviceId])
    }

    func testWhenLoginSucceedsThenCurrentDeviceMigrationIsScheduled() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(account: .mock, devices: [])
        let migrationScheduled = expectation(description: "Device info migration scheduled")
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            migrationScheduled.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                        deviceName: "iPhone",
                                        deviceType: "iOS")
        await fulfillment(of: [migrationScheduled], timeout: 1)

        let migrationCall = try XCTUnwrap(migrationCoordinator.calls.first)
        XCTAssertEqual(migrationCall.account.deviceId, SyncAccount.mock.deviceId)
    }

    func testWhenMigrationCompletesDuringCancellationThenAnotherMigrationCanRun() async {
        let state = DeviceInfoUpdateState()
        for _ in 0..<25 {
            let started = expectation(description: "Migration started")
            let (gate, continuation) = AsyncStream<Void>.makeStream()
            state.scheduleMigration {
                started.fulfill()
                for await _ in gate {}
            }
            await fulfillment(of: [started], timeout: 1)

            async let cancellation: Void = state.cancelAllAndWait()
            continuation.finish()
            await cancellation

            XCTAssertFalse(state.isMigrationRunning)
        }
    }

    func testWhenCancelledMigrationFinishesAfterReplacementThenReplacementRemainsTracked() async {
        let state = DeviceInfoUpdateState()
        let started = expectation(description: "Original migration started")
        let cancelled = expectation(description: "Original migration cancelled")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        // Awaiting an independent task keeps the original operation alive after cancellation.
        let releaseOriginal = Task { for await _ in gate {} }
        defer { continuation.finish() }
        state.scheduleMigration {
            await withTaskCancellationHandler {
                started.fulfill()
                await releaseOriginal.value
            } onCancel: {
                cancelled.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        let cancellation = Task { await state.cancelAllAndWait() }
        await fulfillment(of: [cancelled], timeout: 1)
        state.cancelAll()

        let replacementStarted = expectation(description: "Replacement migration started")
        let replacementCancelled = expectation(description: "Replacement migration cancelled")
        let (replacementGate, replacementContinuation) = AsyncStream<Void>.makeStream()
        defer { replacementContinuation.finish() }
        state.scheduleMigration {
            await withTaskCancellationHandler {
                replacementStarted.fulfill()
                for await _ in replacementGate {}
            } onCancel: {
                replacementCancelled.fulfill()
            }
        }
        await fulfillment(of: [replacementStarted], timeout: 1)

        continuation.finish()
        await cancellation.value
        XCTAssertTrue(state.isMigrationRunning)

        await state.cancelAllAndWait()
        await fulfillment(of: [replacementCancelled], timeout: 1)
        XCTAssertFalse(state.isMigrationRunning)
    }

    func testWhenUnifiedReadObservationsAreReturnedThenTheyFireWithoutRequiringWriteFlag() async throws {
        dependencies.canReadUnifiedDeviceList = { true }
        dependencies.canWriteUnifiedDeviceList = { false }
        let events = UnifiedDeviceListEventMappingMock()
        dependencies.unifiedDeviceListEvents = events
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: false,
            unifiedReadObservations: [
                .event(.ownRowResolvedDeviceInfo),
                .event(.otherRowResolvedPlaceholder(.ddg))
            ])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.fetchDevices()

        XCTAssertEqual(events.events, [
            .ownRowResolvedDeviceInfo,
            .otherRowResolvedPlaceholder(.ddg)
        ])
    }

    func testWhenUnifiedWriteIsDisabledThenOwnRowFallbackObservationsDoNotFire() async throws {
        dependencies.canReadUnifiedDeviceList = { true }
        dependencies.canWriteUnifiedDeviceList = { false }
        let events = UnifiedDeviceListEventMappingMock()
        dependencies.unifiedDeviceListEvents = events
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: false,
            unifiedReadObservations: [
                .event(.ownRowResolvedLegacy(.blobDecryptFailed)),
                .event(.ownRowResolvedPlaceholder(.blobDecryptFailed)),
                .ownRowMissingDeviceInfo(.legacy),
                .ownRowMissingDeviceInfo(.placeholder),
                .event(.ownRowResolvedDeviceInfo),
                .event(.otherRowResolvedPlaceholder(.ddg))
            ])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.fetchDevices()

        XCTAssertEqual(events.events, [
            .ownRowResolvedDeviceInfo,
            .otherRowResolvedPlaceholder(.ddg)
        ])
    }

    func testWhenOwnRowDeviceInfoIsMissingThenMigrationMarkerDistinguishesNotPublishedFromAbsent() async throws {
        dependencies.canReadUnifiedDeviceList = { true }
        dependencies.canWriteUnifiedDeviceList = { true }
        let events = UnifiedDeviceListEventMappingMock()
        dependencies.unifiedDeviceListEvents = events
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: false,
            unifiedReadObservations: [.ownRowMissingDeviceInfo(.legacy)])
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.fetchDevices()
        migrationCoordinator.hasCompletedMigrationStub = true
        _ = try await syncService.fetchDevices()

        XCTAssertEqual(events.events, [
            .ownRowResolvedLegacy(.notPublishedYet),
            .ownRowResolvedLegacy(.blobAbsent)
        ])
    }

    func testWhenMigrationCompletesDuringDeviceFetchThenStaleResultDoesNotScheduleRepairUntilNextPoll() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        let migrationStarted = expectation(description: "Device info migration started")
        let migrationFinished = expectation(description: "Device info migration finished")
        let deviceFetchStarted = expectation(description: "Device fetch started")
        let unexpectedRepair = expectation(description: "Current device info repair not scheduled")
        unexpectedRepair.isInverted = true
        let (migrationGate, migrationGateContinuation) = AsyncStream<Void>.makeStream()
        let (deviceFetchGate, deviceFetchGateContinuation) = AsyncStream<Void>.makeStream()
        defer {
            migrationGateContinuation.finish()
            deviceFetchGateContinuation.finish()
        }
        accountManager.fetchDevicesForAccountHandler = { _ in
            deviceFetchStarted.fulfill()
            for await _ in deviceFetchGate {}
            return RegisteredDeviceMappingResult(devices: [.mock], needsCurrentDeviceInfoRepair: true)
        }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            migrationStarted.fulfill()
            for await _ in migrationGate {}
            migrationFinished.fulfill()
        }
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            unexpectedRepair.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        try await syncService.createAccount(deviceName: "iPhone", deviceType: "iOS")
        await fulfillment(of: [migrationStarted], timeout: 1)
        async let fetchedDevices = syncService.fetchDevices()
        await fulfillment(of: [deviceFetchStarted], timeout: 1)
        migrationGateContinuation.finish()
        await fulfillment(of: [migrationFinished], timeout: 1)
        await Task.yield()
        deviceFetchGateContinuation.finish()
        let devices = try await fetchedDevices
        await fulfillment(of: [unexpectedRepair], timeout: 0.1)

        XCTAssertEqual(devices.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertTrue(migrationCoordinator.repairCalls.isEmpty)

        let repairScheduledOnNextPoll = expectation(description: "Current device info repair scheduled on next poll")
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            repairScheduledOnNextPoll.fulfill()
        }
        accountManager.fetchDevicesForAccountHandler = nil
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: true)

        _ = try await syncService.fetchDevices()
        await fulfillment(of: [repairScheduledOnNextPoll], timeout: 1)

        XCTAssertEqual(migrationCoordinator.repairCalls.map(\.account.deviceId), [SyncAccount.mock.deviceId])
    }

    func testWhenFetchedCurrentDeviceNeedsInfoRepairThenRepairIsScheduledOncePerSession() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: true)
        let repairScheduled = expectation(description: "Current device info repair scheduled")
        let repairFinished = expectation(description: "Current device info repair finished")
        let (repairGate, repairGateContinuation) = AsyncStream<Void>.makeStream()
        defer { repairGateContinuation.finish() }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            repairScheduled.fulfill()
            for await _ in repairGate {}
            repairFinished.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let devices = try await syncService.fetchDevices()
        await fulfillment(of: [repairScheduled], timeout: 1)
        repairGateContinuation.finish()
        await fulfillment(of: [repairFinished], timeout: 1)
        await Task.yield()
        _ = try await syncService.fetchDevices()

        XCTAssertEqual(devices.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertEqual(migrationCoordinator.repairCalls.map(\.account.deviceId), [SyncAccount.mock.deviceId])
    }

    func testWhenAccountChangesDuringDeviceFetchThenOldResultDoesNotConsumeRepairAttempt() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        let originalAccount = SyncAccount.mock
        let replacementAccount = SyncAccount(
            deviceId: "replacementDeviceId",
            deviceName: "replacementDeviceName",
            deviceType: originalAccount.deviceType,
            userId: "replacementUserId",
            primaryKey: originalAccount.primaryKey,
            secretKey: originalAccount.secretKey,
            token: originalAccount.token,
            state: .active)
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        let originalFetchStarted = expectation(description: "Original account device fetch started")
        let (originalFetchGate, originalFetchGateContinuation) = AsyncStream<Void>.makeStream()
        defer { originalFetchGateContinuation.finish() }
        accountManager.fetchDevicesForAccountHandler = { account in
            if account.deviceId == originalAccount.deviceId {
                originalFetchStarted.fulfill()
                for await _ in originalFetchGate {}
            }
            return RegisteredDeviceMappingResult(devices: [.mock], needsCurrentDeviceInfoRepair: true)
        }
        let repairScheduled = expectation(description: "Replacement account device info repair scheduled")
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            repairScheduled.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        async let originalDevices = syncService.fetchDevices()
        await fulfillment(of: [originalFetchStarted], timeout: 1)
        secureStore.theAccount = replacementAccount
        originalFetchGateContinuation.finish()
        _ = try await originalDevices
        _ = try await syncService.fetchDevices()
        await fulfillment(of: [repairScheduled], timeout: 1)

        XCTAssertEqual(migrationCoordinator.repairCalls.map(\.account.deviceId), [replacementAccount.deviceId])
    }

    func testWhenStoredAccountIsRefreshedDuringDeviceFetchThenRepairUsesLatestAccount() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        let originalAccount = SyncAccount.mock
        let refreshedAccount = SyncAccount(
            deviceId: originalAccount.deviceId,
            deviceName: "refreshedDeviceName",
            deviceType: originalAccount.deviceType,
            userId: originalAccount.userId,
            primaryKey: Data("refreshedPrimaryKey".utf8),
            secretKey: Data("refreshedSecretKey".utf8),
            token: "refreshedToken",
            state: .active)
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        let deviceFetchStarted = expectation(description: "Device fetch started")
        let (deviceFetchGate, deviceFetchGateContinuation) = AsyncStream<Void>.makeStream()
        defer { deviceFetchGateContinuation.finish() }
        accountManager.fetchDevicesForAccountHandler = { _ in
            deviceFetchStarted.fulfill()
            for await _ in deviceFetchGate {}
            return RegisteredDeviceMappingResult(devices: [.mock], needsCurrentDeviceInfoRepair: true)
        }
        let repairScheduled = expectation(description: "Current device info repair scheduled")
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            repairScheduled.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        async let devices = syncService.fetchDevices()
        await fulfillment(of: [deviceFetchStarted], timeout: 1)
        secureStore.theAccount = refreshedAccount
        deviceFetchGateContinuation.finish()
        _ = try await devices
        await fulfillment(of: [repairScheduled], timeout: 1)

        XCTAssertEqual(migrationCoordinator.repairCalls.count, 1)
        let repairAccount = try XCTUnwrap(migrationCoordinator.repairCalls.first?.account)
        XCTAssertEqual(repairAccount.deviceName, refreshedAccount.deviceName)
        XCTAssertEqual(repairAccount.primaryKey, refreshedAccount.primaryKey)
        XCTAssertEqual(repairAccount.secretKey, refreshedAccount.secretKey)
        XCTAssertEqual(repairAccount.token, refreshedAccount.token)
    }

    func testWhenFetchedCurrentDeviceNeedsInfoRepairButWriteIsDisabledThenRepairIsNotScheduled() async throws {
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: true)
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.fetchDevices()

        XCTAssertTrue(migrationCoordinator.repairCalls.isEmpty)
    }

    func testWhenScopedPasswordRecoveryFailsDuringLoginThenNativeLoginStillSucceeds() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        (dependencies.secureStore as? SecureStorageStub)?.theScopedPassword = Data(repeating: 9, count: 32)
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(
            account: .mock,
            devices: [.mock],
            accessCredentials: [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: "invalid")]
        )
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.recoverScopedPasswordError = SyncError.invalidDataInResponse("broken scoped credential")
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let devices = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                                  deviceName: "iPhone",
                                                  deviceType: "iOS")

        XCTAssertEqual(devices.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertNotNil((dependencies.secureStore as? SecureStorageStub)?.theAccount)
        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
    }

    func testWhenScopedPasswordRecoveryFeatureFlagIsDisabledDuringLoginThenRecoveryIsSkipped() async throws {
        dependencies.isScopedAccessCredentialsEnabled = { false }
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(
            account: .mock,
            devices: [.mock],
            accessCredentials: [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: "encrypted")]
        )
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.recoverScopedPasswordStub = Data(repeating: 8, count: 32)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                        deviceName: "iPhone",
                                        deviceType: "iOS")

        XCTAssertTrue(scopedAccess.recoverScopedPasswordCalls.isEmpty)
        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword)
    }

    func testWhenLoginResponseContainsRecoverableScopedPasswordThenScopedPasswordIsCached() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let scopedPassword = Data(repeating: 8, count: 32)
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(
            account: .mock,
            devices: [.mock],
            accessCredentials: [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: "encrypted")]
        )
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                        deviceName: "iPhone",
                                        deviceType: "iOS")

        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword, scopedPassword)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
    }

    func testWhenWriteIsDisabledAndRenamingDeviceDuringMigrationThenLegacyRefreshRunsAfterCancellationAndMigrationIsRescheduled() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        dependencies.canUsePatchEndpointForLegacyDeviceRename = { false }
        let migrationStarted = expectation(description: "Device info migration started")
        let migrationFinished = expectation(description: "Device info migration finished")
        let migrationRescheduled = expectation(description: "Device info migration rescheduled")
        let (migrationCancellationGate, migrationCancellationContinuation) = AsyncStream<Void>.makeStream()
        defer { migrationCancellationContinuation.finish() }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            guard migrationCoordinator.calls.count == 1 else {
                migrationRescheduled.fulfill()
                return
            }
            migrationStarted.fulfill()
            for await _ in migrationCancellationGate {}
            migrationFinished.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let renamedAccount = SyncAccount(
            deviceId: SyncAccount.mock.deviceId,
            deviceName: "Renamed Device",
            deviceType: SyncAccount.mock.deviceType,
            userId: SyncAccount.mock.userId,
            primaryKey: SyncAccount.mock.primaryKey,
            secretKey: SyncAccount.mock.secretKey,
            token: SyncAccount.mock.token,
            state: .active)
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.refreshTokenStub = LoginResult(account: renamedAccount, devices: [.mock])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        await fulfillment(of: [migrationStarted], timeout: 1)
        dependencies.canWriteUnifiedDeviceList = { false }

        _ = try await syncService.updateDeviceName(renamedAccount.deviceName)
        await fulfillment(of: [migrationFinished, migrationRescheduled], timeout: 1)

        XCTAssertTrue(accountManager.refreshTokenCalled)
        XCTAssertTrue(migrationCoordinator.renameCalls.isEmpty)
        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theAccount?.deviceName, renamedAccount.deviceName)
        XCTAssertEqual(migrationCoordinator.calls.count, 2)
        XCTAssertEqual(migrationCoordinator.calls.last?.account.deviceName, renamedAccount.deviceName)
        XCTAssertEqual(migrationCoordinator.resetCallCount, 0)
    }

    func testWhenWriteFlagChangesDuringLegacyRenameThenInitialStateDeterminesRoutingAndMigrationState() async throws {
        var writeFlagEvaluationCount = 0
        dependencies.canWriteUnifiedDeviceList = {
            writeFlagEvaluationCount += 1
            return writeFlagEvaluationCount > 1
        }
        dependencies.canUsePatchEndpointForLegacyDeviceRename = { false }
        let migrationScheduled = expectation(description: "Device info migration scheduled")
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            migrationScheduled.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let renamedAccount = SyncAccount(
            deviceId: SyncAccount.mock.deviceId,
            deviceName: "Renamed Device",
            deviceType: SyncAccount.mock.deviceType,
            userId: SyncAccount.mock.userId,
            primaryKey: SyncAccount.mock.primaryKey,
            secretKey: SyncAccount.mock.secretKey,
            token: SyncAccount.mock.token,
            state: .active)
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.refreshTokenStub = LoginResult(account: renamedAccount, devices: [.mock])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.updateDeviceName(renamedAccount.deviceName)
        await fulfillment(of: [migrationScheduled], timeout: 1)

        XCTAssertEqual(writeFlagEvaluationCount, 1)
        XCTAssertTrue(accountManager.refreshTokenCalled)
        XCTAssertTrue(migrationCoordinator.renameCalls.isEmpty)
        XCTAssertEqual(migrationCoordinator.resetCallCount, 0)
    }

    func testWhenRenamingDeviceFailsWithUnifiedWritesEnabledThenMigrationStateIsPreserved() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.renameCurrentDeviceError = SyncError.noResponseBody
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        do {
            _ = try await syncService.updateDeviceName("Renamed Device")
            XCTFail("Expected device rename to fail")
        } catch SyncError.noResponseBody {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(migrationCoordinator.resetCallCount, 0)
        XCTAssertTrue(migrationCoordinator.calls.isEmpty)
        XCTAssertEqual(migrationCoordinator.renameCalls.count, 1)
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.mode, .unified)
    }

    func testWhenWriteIsDisabledAndLegacyPatchIsEnabledThenRenameOmitsUnifiedInfoWithoutRefreshingToken() async throws {
        dependencies.canWriteUnifiedDeviceList = { false }
        dependencies.canUsePatchEndpointForLegacyDeviceRename = { true }
        let expectedDevices = [RegisteredDevice(id: "renamed-device", name: "Renamed Device", type: "iOS")]
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.renameCurrentDeviceStub = expectedDevices
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let devices = try await syncService.updateDeviceName("Renamed Device")

        XCTAssertEqual(devices.map(\.id), expectedDevices.map(\.id))
        XCTAssertFalse(accountManager.refreshTokenCalled)
        XCTAssertEqual(migrationCoordinator.renameCalls.count, 1)
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.name, "Renamed Device")
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.account.deviceId, SyncAccount.mock.deviceId)
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.mode, .legacyOnly)
    }

    func testWhenWriteIsEnabledThenRenameUsesUnifiedUpdateWithoutRefreshingToken() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let expectedDevices = [RegisteredDevice(id: "renamed-device", name: "Renamed Device", type: "iOS")]
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.renameCurrentDeviceStub = expectedDevices
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let devices = try await syncService.updateDeviceName("Renamed Device")

        XCTAssertEqual(devices.map(\.id), expectedDevices.map(\.id))
        XCTAssertFalse(accountManager.refreshTokenCalled)
        XCTAssertEqual(migrationCoordinator.renameCalls.count, 1)
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.name, "Renamed Device")
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.account.deviceId, SyncAccount.mock.deviceId)
        XCTAssertEqual(migrationCoordinator.renameCalls.first?.mode, .unified)
    }

    func testWhenWriteIsEnabledAndRenamingDuringMigrationThenMigrationIsCancelledAndAwaitedBeforeUnifiedRename() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let migrationStarted = expectation(description: "Device info migration started")
        let migrationFinished = expectation(description: "Device info migration finished")
        let unifiedRenameStarted = expectation(description: "Unified rename started")
        let (migrationGate, migrationGateContinuation) = AsyncStream<Void>.makeStream()
        defer { migrationGateContinuation.finish() }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            migrationStarted.fulfill()
            for await _ in migrationGate {}
            migrationFinished.fulfill()
        }
        migrationCoordinator.renameCurrentDeviceHandler = {
            unifiedRenameStarted.fulfill()
            return [.mock]
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        await fulfillment(of: [migrationStarted], timeout: 1)

        let devices = try await syncService.updateDeviceName("Renamed Device")
        await fulfillment(of: [migrationFinished, unifiedRenameStarted], timeout: 1, enforceOrder: true)

        XCTAssertEqual(devices.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertEqual(migrationCoordinator.calls.count, 1)
        XCTAssertEqual(migrationCoordinator.renameCalls.count, 1)
    }

    func testWhenWriteIsEnabledAndRenamingDuringRepairThenRepairIsCancelledAndAwaitedBeforeUnifiedRename() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: true)
        let repairStarted = expectation(description: "Device info repair started")
        let repairFinished = expectation(description: "Device info repair finished")
        let unifiedRenameStarted = expectation(description: "Unified rename started")
        let (repairGate, repairGateContinuation) = AsyncStream<Void>.makeStream()
        defer { repairGateContinuation.finish() }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            repairStarted.fulfill()
            for await _ in repairGate {}
            repairFinished.fulfill()
        }
        migrationCoordinator.renameCurrentDeviceHandler = {
            unifiedRenameStarted.fulfill()
            return [.mock]
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        _ = try await syncService.fetchDevices()
        await fulfillment(of: [repairStarted], timeout: 1)

        _ = try await syncService.updateDeviceName("Renamed Device")
        await fulfillment(of: [repairFinished, unifiedRenameStarted], timeout: 1, enforceOrder: true)

        XCTAssertEqual(migrationCoordinator.repairCalls.count, 1)
        XCTAssertEqual(migrationCoordinator.renameCalls.count, 1)
    }

    func testWhenRepairingFetchCompletesDuringRenameThenRepairWaitsForNextPoll() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        let deviceFetchStarted = expectation(description: "Device fetch started")
        let unifiedRenameStarted = expectation(description: "Unified rename started")
        let unexpectedRepair = expectation(description: "Current device info repair not scheduled during rename")
        unexpectedRepair.isInverted = true
        let (deviceFetchGate, deviceFetchGateContinuation) = AsyncStream<Void>.makeStream()
        let (renameGate, renameGateContinuation) = AsyncStream<Void>.makeStream()
        defer {
            deviceFetchGateContinuation.finish()
            renameGateContinuation.finish()
        }
        accountManager.fetchDevicesForAccountHandler = { _ in
            deviceFetchStarted.fulfill()
            for await _ in deviceFetchGate {}
            return RegisteredDeviceMappingResult(devices: [.mock], needsCurrentDeviceInfoRepair: true)
        }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.renameCurrentDeviceHandler = {
            unifiedRenameStarted.fulfill()
            for await _ in renameGate {}
            return [.mock]
        }
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            unexpectedRepair.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        async let fetchedDevices = syncService.fetchDevices()
        await fulfillment(of: [deviceFetchStarted], timeout: 1)
        async let renamedDevices = syncService.updateDeviceName("Renamed Device")
        await fulfillment(of: [unifiedRenameStarted], timeout: 1)
        deviceFetchGateContinuation.finish()
        _ = try await fetchedDevices
        await fulfillment(of: [unexpectedRepair], timeout: 0.1)
        renameGateContinuation.finish()
        _ = try await renamedDevices

        XCTAssertTrue(migrationCoordinator.repairCalls.isEmpty)

        let repairScheduledOnNextPoll = expectation(description: "Current device info repair scheduled on next poll")
        migrationCoordinator.repairCurrentDeviceInfoHandler = {
            repairScheduledOnNextPoll.fulfill()
        }
        accountManager.fetchDevicesForAccountHandler = nil
        accountManager.fetchDevicesForAccountStub = RegisteredDeviceMappingResult(
            devices: [.mock],
            needsCurrentDeviceInfoRepair: true)

        _ = try await syncService.fetchDevices()
        await fulfillment(of: [repairScheduledOnNextPoll], timeout: 1)

        XCTAssertEqual(migrationCoordinator.repairCalls.map(\.account.deviceId), [SyncAccount.mock.deviceId])
    }

    func testWhenUnifiedRenameReturns401ThenExistingUnauthenticatedHandlingLogsOut() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.renameCurrentDeviceError = SyncError.unexpectedStatusCode(401)
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        do {
            _ = try await syncService.updateDeviceName("Renamed Device")
            XCTFail("Expected rename to throw")
        } catch let error as SyncError {
            XCTAssertEqual(error, .unauthenticatedWhileLoggedIn)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theAccount)
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertEqual(migrationCoordinator.resetCallCount, 1)
    }

    func testWhenRenameWithoutUnifiedInfoReturns401ThenExistingUnauthenticatedHandlingLogsOut() async throws {
        dependencies.canWriteUnifiedDeviceList = { false }
        dependencies.canUsePatchEndpointForLegacyDeviceRename = { true }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.renameCurrentDeviceError = SyncError.unexpectedStatusCode(401)
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        do {
            _ = try await syncService.updateDeviceName("Renamed Device")
            XCTFail("Expected rename to throw")
        } catch let error as SyncError {
            XCTAssertEqual(error, .unauthenticatedWhileLoggedIn)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theAccount)
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertEqual(migrationCoordinator.resetCallCount, 1)
    }

    func testWhenRefreshResponseContainsRecoverableScopedPasswordThenScopedPasswordIsCached() async throws {
        dependencies.canUsePatchEndpointForLegacyDeviceRename = { false }
        let scopedPassword = Data(repeating: 7, count: 32)
        (dependencies.account as? AccountManagingMock)?.refreshTokenStub = LoginResult(
            account: .mock,
            devices: [.mock],
            accessCredentials: [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: "encrypted")]
        )
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.updateDeviceName("Updated iPhone")

        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword, scopedPassword)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
    }

    func testWhenDisconnectRemovesAccountThenScopedPasswordAndProtectedKeysAreCleared() async throws {
        let protectedKey = makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg")
        let protectedKeysData = try JSONEncoder.snakeCaseKeys.encode([protectedKey])
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = .mock
        (dependencies.secureStore as? SecureStorageStub)?.theScopedPassword = Data(repeating: 6, count: 32)
        (dependencies.secureStore as? SecureStorageStub)?.theProtectedKeysData = protectedKeysData
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let accountInfoKeys = try XCTUnwrap(dependencies.accountInfoKeys as? AccountInfoKeyManagingMock)
        let accountInfoKeyCacheCleared = expectation(description: "Account-info key cache cleared")
        accountInfoKeys.clearCachedKeyHandler = { account in
            XCTAssertEqual(account.deviceId, SyncAccount.mock.deviceId)
            accountInfoKeyCacheCleared.fulfill()
        }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        try await syncService.disconnect()
        await fulfillment(of: [accountInfoKeyCacheCleared], timeout: 1)

        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theAccount)
        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword)
        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theProtectedKeysData)
        XCTAssertEqual(accountInfoKeys.clearCachedKeyCalls.map(\.deviceId), [SyncAccount.mock.deviceId])
        XCTAssertEqual(migrationCoordinator.resetCallCount, 1)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndCredentialExistsThenRecoveredScopedPasswordIsUsed() async throws {
        let scopedPassword = Data(repeating: 8, count: 32)
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.ensureThirdPartyScopedPasswordStub = EnsuredThirdPartyCredential(scopedPassword: scopedPassword,
                                                                                     protectedKeysToCache: [])
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        let scopedPasswordCached = expectation(description: "Scoped password cached")
        secureStore.persistScopedPasswordCalled = {
            scopedPasswordCached.fulfill()
        }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let code = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")
        let decoded = try SyncCode.decodeBase64URLString(code)
        await fulfillment(of: [scopedPasswordCached], timeout: 5.0)

        XCTAssertEqual(scopedAccess.ensureThirdPartyScopedPasswordCalls.count, 1)
        XCTAssertEqual(secureStore.theScopedPassword, scopedPassword)
        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(Base64URL.decode(payload.secret), scopedPassword)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndScopedPasswordCacheWriteFailsThenRecoveryCodeIsPrepared() async throws {
        let scopedPassword = Data(repeating: 8, count: 32)
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.ensureThirdPartyScopedPasswordStub = EnsuredThirdPartyCredential(scopedPassword: scopedPassword,
                                                                                     protectedKeysToCache: [])
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        secureStore.mockWriteError = .failedToWriteSecureStore(status: -1)
        let scopedPasswordCacheAttempted = expectation(description: "Scoped password cache attempted")
        secureStore.persistScopedPasswordCalled = {
            scopedPasswordCacheAttempted.fulfill()
        }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let code = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")
        let decoded = try SyncCode.decodeBase64URLString(code)
        await fulfillment(of: [scopedPasswordCacheAttempted], timeout: 5.0)

        XCTAssertEqual(scopedAccess.ensureThirdPartyScopedPasswordCalls.count, 1)
        XCTAssertNil(secureStore.theScopedPassword)
        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(Base64URL.decode(payload.secret), scopedPassword)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndCredentialDoesNotExistThenScopedPasswordIsGenerated() async throws {
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        let scopedPassword = Data(repeating: 6, count: 32)
        scopedAccess.ensureThirdPartyScopedPasswordStub = EnsuredThirdPartyCredential(scopedPassword: scopedPassword,
                                                                                     protectedKeysToCache: [])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")

        XCTAssertEqual(scopedAccess.ensureThirdPartyScopedPasswordCalls.count, 1)
        XCTAssertEqual(scopedPassword.count, 32)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndScopedAccessFeatureIsDisabledThenRecoveryCodeIsPrepared() async throws {
        dependencies.isScopedAccessCredentialsEnabled = { false }
        let scopedPassword = Data(repeating: 8, count: 32)
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.ensureThirdPartyScopedPasswordStub = EnsuredThirdPartyCredential(scopedPassword: scopedPassword,
                                                                                     protectedKeysToCache: [])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let code = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")
        let decoded = try SyncCode.decodeBase64URLString(code)

        XCTAssertEqual(scopedAccess.ensureThirdPartyScopedPasswordCalls.count, 1)
        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(Base64URL.decode(payload.secret), scopedPassword)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndReturnedSnapshotIsMissingMatchingWrapperThenCachedWrapperIsPreserved() async throws {
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        let defaultWrapper = makeProtectedKey(kid: "account-info-key",
                                              encryptedWith: SyncCredentialID.defaultCredential,
                                              purpose: ProtectedKeyPurpose.accountInfo)
        let thirdPartyWrapper = makeProtectedKey(kid: "account-info-key",
                                                 encryptedWith: SyncCredentialID.thirdParty,
                                                 purpose: ProtectedKeyPurpose.accountInfo)
        let unrelatedKey = makeProtectedKey(kid: "other-key", encryptedWith: SyncCredentialID.defaultCredential)
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([
            defaultWrapper,
            thirdPartyWrapper,
            unrelatedKey
        ])
        scopedAccess.ensureThirdPartyScopedPasswordStub = EnsuredThirdPartyCredential(scopedPassword: Data(repeating: 6, count: 32),
                                                                                     protectedKeysToCache: [defaultWrapper, unrelatedKey])
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")

        let cachedProtectedKeysData = try XCTUnwrap(secureStore.theProtectedKeysData)
        let cachedProtectedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedProtectedKeysData)
        XCTAssertEqual(cachedProtectedKeys.count, 3)
        XCTAssertEqual(Set(cachedProtectedKeys.filter { $0.purpose == ProtectedKeyPurpose.accountInfo }.map(\.encryptedWith)),
                       Set([SyncCredentialID.defaultCredential, SyncCredentialID.thirdParty]))
    }

    func testWhenPreparingThirdPartyRecoveryCodeFailsThenExistingProtectedKeysCacheIsPreserved() async throws {
        let cachedKey = makeProtectedKey(kid: "cached-key", encryptedWith: SyncCredentialID.defaultCredential)
        let cachedData = try JSONEncoder.snakeCaseKeys.encode([cachedKey])
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        secureStore.theProtectedKeysData = cachedData
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.ensureThirdPartyScopedPasswordError = ScopedAccessCredentialError.accountExtendFailed
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        do {
            _ = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")
            XCTFail("Expected scoped credential preparation to fail")
        } catch ScopedAccessCredentialError.accountExtendFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(secureStore.theProtectedKeysData, cachedData)
    }

    func testWhenUpgradingThirdPartyAccountAndScopedAccessFeatureIsDisabledThenAccountIsUpgraded() async throws {
        dependencies.isScopedAccessCredentialsEnabled = { false }
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let upgradeCoordinator = ThirdPartyAccountUpgradeCoordinatingMock()
        dependencies.createThirdPartyAccountUpgradeCoordinatorStub = upgradeCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let devices = try await syncService.upgradeThirdPartyAccountToDefaultCredential("third-party-recovery-code",
                                                                                       deviceName: "Mac",
                                                                                       deviceType: "desktop")

        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.map(\.recoveryCode), ["third-party-recovery-code"])
        XCTAssertEqual(devices.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theAccount?.userId, SyncAccount.mock.userId)
    }

    func testWhenThirdPartyUpgradeSucceedsThenCurrentDeviceMigrationIsScheduled() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let upgradeCoordinator = ThirdPartyAccountUpgradeCoordinatingMock()
        dependencies.createThirdPartyAccountUpgradeCoordinatorStub = upgradeCoordinator
        let migrationScheduled = expectation(description: "Device info migration scheduled")
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        migrationCoordinator.migrateCurrentDeviceHandler = {
            migrationScheduled.fulfill()
        }
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.upgradeThirdPartyAccountToDefaultCredential("third-party-recovery-code",
                                                                             deviceName: "Mac",
                                                                             deviceType: "desktop")
        await fulfillment(of: [migrationScheduled], timeout: 1)

        let migrationCall = try XCTUnwrap(migrationCoordinator.calls.first)
        XCTAssertEqual(migrationCall.account.deviceId, SyncAccount.mock.deviceId)
    }

    func testWhenGeneratingThirdPartyRecoveryCodeThenPayloadMatchesV2Spec() throws {
        let scopedPassword = Data(repeating: 7, count: 32)

        let code = try XCTUnwrap(ScopedAccessCredentialManager(endpoints: Endpoints(baseURL: URL(string: "https://example.com")!),
                                                               api: RemoteAPIRequestCreatingMock(),
                                                               crypter: CryptingMock(),
                                                               accountInfoKeyFactory: AccountInfoKeyFactoryMock(),
                                                               canWriteUnifiedDeviceList: { true })
            .makeRecoveryCode(for: .mock, scopedPassword: scopedPassword))
        let decoded = try SyncCode.decodeBase64URLString(code)

        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }

        XCTAssertEqual(payload.userId, "userId")
        XCTAssertEqual(payload.cid, "3party")
        XCTAssertEqual(payload.v, "2.0")
        XCTAssertFalse(payload.secret.isEmpty)
        // `secret` is base64URL(no padding) of the raw SP bytes.
        XCTAssertEqual(Base64URL.decode(payload.secret), scopedPassword)
    }

    func testWhenDecodingV2RecoveryCodeWithoutSecretThenDecodingFails() throws {
        let json = """
        {
          "recovery": {
            "user_id": "userId",
            "cid": "3party",
            "v": "2.0"
          }
        }
        """
        let code = Base64URL.encode(Data(json.utf8))

        XCTAssertThrowsError(try SyncCode.decodeBase64URLString(code))
    }

    func testWhenDecodingV2RecoveryCodeWithNewMinorVersionThenDecodingSucceeds() throws {
        let json = """
        {
          "recovery": {
            "user_id": "userId",
            "secret": "secret",
            "cid": "3party",
            "v": "2.1"
          }
        }
        """
        let code = Base64URL.encode(Data(json.utf8))

        let decoded = try SyncCode.decodeBase64URLString(code)

        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(payload.v, "2.1")
    }

    func testWhenDecodingV2RecoveryCodeWithUnsupportedMajorVersionThenDecodingFails() throws {
        let json = """
        {
          "recovery": {
            "user_id": "userId",
            "secret": "secret",
            "cid": "3party",
            "v": "3.0"
          }
        }
        """
        let code = Base64URL.encode(Data(json.utf8))

        XCTAssertThrowsError(try SyncCode.decodeBase64URLString(code)) { error in
            XCTAssertEqual(error as? SyncCode.RecoveryCodeVersionError, .unsupported("3.0"))
        }
    }

    func testWhenDecodingV2RecoveryCodeWithMalformedVersionThenDecodingFails() throws {
        let json = """
        {
          "recovery": {
            "user_id": "userId",
            "secret": "secret",
            "cid": "3party",
            "v": "-1"
          }
        }
        """
        let code = Base64URL.encode(Data(json.utf8))

        XCTAssertThrowsError(try SyncCode.decodeBase64URLString(code)) { error in
            XCTAssertEqual(error as? SyncCode.RecoveryCodeVersionError, .malformed("-1"))
        }
    }

    private func makeProtectedKey(kid: String, encryptedWith: String, purpose: String = "browser") -> ProtectedKey {
        ProtectedKey(kid: kid,
                     encryptedPrivateKey: "encrypted-private-key",
                     publicKey: .mock,
                     encryptedWith: encryptedWith,
                     purpose: purpose)
    }

    private func scopedAccessMainKey(from secret: Data, userID: String) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret),
                                                salt: Data(userID.utf8),
                                                info: Data("Main Key".utf8),
                                                outputByteCount: 32)
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}
