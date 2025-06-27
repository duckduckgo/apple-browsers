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

        waitForExpectations(timeout: 1)

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

        waitForExpectations(timeout: 1)

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

        waitForExpectations(timeout: 1)

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

        waitForExpectations(timeout: 2)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .finished(1)
        ])

        XCTAssertEqual(syncService.authState, .inactive)
    }
}
