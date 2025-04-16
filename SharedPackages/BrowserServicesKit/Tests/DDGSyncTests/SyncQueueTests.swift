//
//  SyncQueueTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

@testable import DDGSync

class SyncQueueTests: XCTestCase {
    var apiMock: RemoteAPIRequestCreatingMock!
    var request: HTTPRequestingMock!
    var endpoints: Endpoints!
    var storage: SecureStorageStub!
    var crypter: CryptingMock!
    var requestMaker: SyncRequestMaking!
    var payloadCompressor: SyncPayloadCompressing!

    override func setUpWithError() throws {
        try super.setUpWithError()

        apiMock = RemoteAPIRequestCreatingMock()
        request = HTTPRequestingMock()
        apiMock.request = request
        payloadCompressor = SyncGzipPayloadCompressorMock()
        endpoints = Endpoints(baseURL: URL(string: "https://example.com")!)
        storage = SecureStorageStub()
        crypter = CryptingMock()
        try storage.persistAccount(
            SyncAccount(
                deviceId: "deviceId",
                deviceName: "deviceName",
                deviceType: "deviceType",
                userId: "userId",
                primaryKey: "primaryKey".data(using: .utf8)!,
                secretKey: "secretKey".data(using: .utf8)!,
                token: "token",
                state: .active
            )
        )

        requestMaker = SyncRequestMaker(storage: storage, api: apiMock, endpoints: endpoints, payloadCompressor: payloadCompressor)
    }

    func testWhenDataSyncingFeatureFlagIsDisabledThenNewOperationsAreNotEnqueued() async {
        let syncQueue = SyncQueue(
            dataProviders: [],
            storage: storage,
            crypter: crypter,
            api: apiMock,
            endpoints: endpoints,
            payloadCompressor: payloadCompressor
        )
        XCTAssertFalse(syncQueue.operationQueue.isSuspended)

        var syncDidStartEvents = [Bool]()
        let cancellable = syncQueue.isSyncInProgressPublisher.removeDuplicates().filter({ $0 }).sink { syncDidStartEvents.append($0) }

        syncQueue.isDataSyncingFeatureFlagEnabled = false

        await syncQueue.startSync()
        await syncQueue.startSync()
        await syncQueue.startSync()

        XCTAssertTrue(syncDidStartEvents.isEmpty)

        syncQueue.isDataSyncingFeatureFlagEnabled = true

        await syncQueue.startSync()
        await syncQueue.startSync()
        await syncQueue.startSync()

        cancellable.cancel()
        XCTAssertEqual(syncDidStartEvents.count, 3)
    }

    func testThatInProgressPublisherEmitsValuesWhenSyncStartsAndEndsWithSuccess() async throws {
        let feature = Feature(name: "bookmarks")
        let dataProvider = DataProvidingMock(feature: feature)
        let syncQueue = SyncQueue(
            dataProviders: [dataProvider],
            storage: storage,
            crypter: crypter,
            api: apiMock,
            endpoints: endpoints,
            payloadCompressor: payloadCompressor
        )

        var isInProgressEvents = [Bool]()

        let cancellable = syncQueue.isSyncInProgressPublisher.sink(receiveValue: { isInProgressEvents.append($0) })
        defer { cancellable.cancel() }

        request.result = .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())
        await syncQueue.startSync()
        XCTAssertEqual(isInProgressEvents, [false, true, false])

        await syncQueue.startSync()
        XCTAssertEqual(isInProgressEvents, [false, true, false, true, false])
    }

    func testThatInProgressPublisherEmitsValuesWhenSyncStartsAndEndsWithError() async throws {
        let feature = Feature(name: "bookmarks")
        let dataProvider = DataProvidingMock(feature: feature)
        let syncQueue = SyncQueue(
            dataProviders: [dataProvider],
            storage: storage,
            crypter: crypter,
            api: apiMock,
            endpoints: endpoints,
            payloadCompressor: payloadCompressor
        )

        var isInProgressEvents = [Bool]()

        let cancellable = syncQueue.isSyncInProgressPublisher.sink(receiveValue: { isInProgressEvents.append($0) })
        defer { cancellable.cancel() }

        request.error = .noResponseBody
        await syncQueue.startSync()
        XCTAssertEqual(isInProgressEvents, [false, true, false])

        await syncQueue.startSync()
        XCTAssertEqual(isInProgressEvents, [false, true, false, true, false])
    }
}

struct FeaturePayload<Model: Decodable & Equatable>: Decodable, Equatable {
    let updates: [Model]
    let modifiedSince: String
}

struct BookmarksPayload: Decodable, Equatable {
    let bookmarks: FeaturePayload<Bookmark>

    struct Bookmark: Decodable, Equatable {
        let id: String
        let name: String
        let url: String
    }
}

struct SettingsPayload: Decodable, Equatable {
    let settings: FeaturePayload<Setting>

    struct Setting: Decodable, Equatable {
        let key: String
        let value: String
    }
}

struct AutofillPayload: Decodable, Equatable {
    let autofill: FeaturePayload<Autofill>

    struct Autofill: Decodable, Equatable {
        let id: String
        let login: String
        let password: String
        let url: String
    }
}

fileprivate extension SyncQueue {

    func startSync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startSync()
            operationQueue.addBarrierBlock {
                continuation.resume()
            }
        }
    }
}
