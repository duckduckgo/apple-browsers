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

    func testWhenDebugMigrationIsResetThenItCanRunAgain() async throws {
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        try await syncService.runDeviceInfoMigrationForDebug()
        syncService.resetDeviceInfoMigrationForDebug()
        try await syncService.runDeviceInfoMigrationForDebug()

        XCTAssertEqual(migrationCoordinator.calls.count, 2)
        XCTAssertEqual(migrationCoordinator.resetCallCount, 1)
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

    func testWhenRenamingDeviceDuringMigrationThenMigrationIsCancelledBeforeRenameAndRescheduled() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
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

        _ = try await syncService.updateDeviceName(renamedAccount.deviceName)
        await fulfillment(of: [migrationFinished, migrationRescheduled], timeout: 1)

        XCTAssertTrue(accountManager.refreshTokenCalled)
        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theAccount?.deviceName, renamedAccount.deviceName)
        XCTAssertEqual(migrationCoordinator.calls.count, 2)
        XCTAssertEqual(migrationCoordinator.calls.last?.account.deviceName, renamedAccount.deviceName)
        XCTAssertEqual(migrationCoordinator.resetCallCount, 1)
    }

    func testWhenRenamingDeviceWithUnifiedWritesDisabledThenMigrationStateIsPreserved() async throws {
        dependencies.canWriteUnifiedDeviceList = { false }
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

        XCTAssertEqual(migrationCoordinator.resetCallCount, 0)
    }

    func testWhenRenamingDeviceFailsWithUnifiedWritesEnabledThenMigrationStateIsPreserved() async throws {
        dependencies.canWriteUnifiedDeviceList = { true }
        let migrationCoordinator = DeviceInfoMigrationCoordinatingMock()
        dependencies.createDeviceInfoMigrationCoordinatorStub = migrationCoordinator
        let accountManager = try XCTUnwrap(dependencies.account as? AccountManagingMock)
        accountManager.refreshTokenError = SyncError.noResponseBody
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
    }

    func testWhenRefreshResponseContainsRecoverableScopedPasswordThenScopedPasswordIsCached() async throws {
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
