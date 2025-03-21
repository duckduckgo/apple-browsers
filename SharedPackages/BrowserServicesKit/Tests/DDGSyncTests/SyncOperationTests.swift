//
//  SyncOperationTests.swift
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

import XCTest

@testable import Gzip
@testable import DDGSync

class SyncOperationTests: XCTestCase {
    var apiMock: RemoteAPIRequestCreatingMock!
    var request: HTTPRequestingMock!
    var endpoints: Endpoints!
    var payloadCompressor: SyncGzipPayloadCompressorMock!
    var storage: SecureStorageStub!
    var crypter: CryptingMock!
    var requestMaker: InspectableSyncRequestMaker!

    override func setUpWithError() throws {
        try super.setUpWithError()

        apiMock = RemoteAPIRequestCreatingMock()
        request = HTTPRequestingMock()
        apiMock.request = request
        endpoints = Endpoints(baseURL: URL(string: "https://example.com")!)
        payloadCompressor = SyncGzipPayloadCompressorMock()
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

        requestMaker = InspectableSyncRequestMaker(
            requestMaker: .init(storage: storage, api: apiMock, endpoints: endpoints, payloadCompressor: payloadCompressor)
        )
    }

    func testWhenThereAreNoChangesThenGetRequestIsFired() async throws {
        let feature = Feature(name: "bookmarks")
        let dataProvider = DataProvidingMock(feature: feature)
        let syncOperation = SyncOperation(dataProviders: [dataProvider], storage: storage, crypter: crypter, requestMaker: requestMaker)

        request.error = .noResponseBody
        await assertThrowsAnyError({
            try await syncOperation.sync(fetchOnly: false)
        }, errorHandler: { error in
            guard let syncOperationError = error as? SyncOperationError, let featureError = syncOperationError.perFeatureErrors[feature] as? SyncError else {
                XCTFail("Unexpected error thrown: \(error)")
                return
            }
            XCTAssertEqual(featureError, .noResponseBody)
        })
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .get)
    }

    func testWhenThereAreChangesThenPatchRequestIsFired() async throws {
        let feature = Feature(name: "bookmarks")
        let dataProvider = DataProvidingMock(feature: feature)
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        dataProvider._fetchChangedObjects = { _ in
            [Syncable(jsonObject: [:])]
        }
        let syncOperation = SyncOperation(dataProviders: [dataProvider], storage: storage, crypter: crypter, requestMaker: requestMaker)

        request.error = .noResponseBody
        await assertThrowsAnyError({
            try await syncOperation.sync(fetchOnly: false)
        }, errorHandler: { error in
            guard let syncOperationError = error as? SyncOperationError, let featureError = syncOperationError.perFeatureErrors[feature] as? SyncError else {
                XCTFail("Unexpected error thrown: \(error)")
                return
            }
            XCTAssertEqual(featureError, .noResponseBody)
        })
        XCTAssertEqual(apiMock.createRequestCallCount, 1)
        XCTAssertEqual(apiMock.createRequestCallArgs[0].method, .patch)
    }

    func testThatForMultipleDataProvidersRequestsSeparateRequestsAreSentConcurrently() async throws {
        let dataProvider1 = DataProvidingMock(feature: .init(name: "bookmarks"))
        try dataProvider1.registerFeature(withState: .readyToSync)
        dataProvider1.updateSyncTimestamps(server: "1234", local: nil)
        dataProvider1._fetchChangedObjects = { _ in
            [
                Syncable(jsonObject: ["id": "1", "name": "bookmark1", "url": "https://example.com"]),
                Syncable(jsonObject: ["id": "2", "name": "bookmark2", "url": "https://example.com"]),
            ]
        }
        let dataProvider2 = DataProvidingMock(feature: .init(name: "settings"))
        try dataProvider2.registerFeature(withState: .readyToSync)
        dataProvider2.updateSyncTimestamps(server: "5678", local: nil)
        dataProvider2._fetchChangedObjects = { _ in
            [
                Syncable(jsonObject: ["key": "setting-a", "value": "value-a"]),
                Syncable(jsonObject: ["key": "setting-b", "value": "value-b"])
            ]
        }
        let dataProvider3 = DataProvidingMock(feature: .init(name: "autofill"))
        try dataProvider3.registerFeature(withState: .readyToSync)
        dataProvider3.updateSyncTimestamps(server: "9012", local: nil)
        dataProvider3._fetchChangedObjects = { _ in
            [
                Syncable(jsonObject: ["id": "1", "login": "login1", "password": "password1", "url": "https://example.com"]),
                Syncable(jsonObject: ["id": "2", "login": "login2", "password": "password2", "url": "https://example.com"])
            ]
        }

        let syncOperation = SyncOperation(dataProviders: [dataProvider1, dataProvider2, dataProvider3], storage: storage, crypter: crypter, requestMaker: requestMaker)

        request.error = .noResponseBody
        await assertThrowsAnyError {
            try await syncOperation.sync(fetchOnly: false)
        }

        let bookmarks = BookmarksPayload(
            bookmarks: .init(
                updates: [
                    .init(id: "1", name: "bookmark1", url: "https://example.com"),
                    .init(id: "2", name: "bookmark2", url: "https://example.com")
                ],
                modifiedSince: "1234"
            )
        )
        let settings = SettingsPayload(
            settings: .init(
                updates: [
                    .init(key: "setting-a", value: "value-a"),
                    .init(key: "setting-b", value: "value-b")
                ],
                modifiedSince: "5678"
            )
        )
        let autofill = AutofillPayload(
            autofill: .init(
                updates: [
                    .init(id: "1", login: "login1", password: "password1", url: "https://example.com"),
                    .init(id: "2", login: "login2", password: "password2", url: "https://example.com")
                ],
                modifiedSince: "9012"
            )
        )

        let bodies = try XCTUnwrap(apiMock.createRequestCallArgs.map(\.body))
        XCTAssertEqual(apiMock.createRequestCallCount, 3)
        XCTAssertEqual(bodies.count, 3)

        var payloadCount = 3

        for body in bodies.compactMap({$0}) {
            do {
                let payload = try JSONDecoder.snakeCaseKeys.decode(BookmarksPayload.self, from: body.gunzipped())
                XCTAssertEqual(payload, bookmarks)
                payloadCount -= 1
            } catch {
                do {
                    let payload = try JSONDecoder.snakeCaseKeys.decode(SettingsPayload.self, from: body.gunzipped())
                    XCTAssertEqual(payload, settings)
                    payloadCount -= 1
                } catch {
                    let payload = try JSONDecoder.snakeCaseKeys.decode(AutofillPayload.self, from: body.gunzipped())
                    XCTAssertEqual(payload, autofill)
                    payloadCount -= 1
                }
            }
        }

        XCTAssertEqual(payloadCount, 0)
    }

    func testThatForMultipleDataProvidersErrorsFromAllFeaturesAreThrown() async throws {

        struct DataProviderError: Error, Equatable {
            let feature: Feature
        }

        let feature1 = Feature(name: "bookmarks")
        let dataProvider1 = DataProvidingMock(feature: feature1)
        dataProvider1.updateSyncTimestamps(server: "1234", local: nil)
        dataProvider1._fetchChangedObjects = { _ in throw DataProviderError(feature: feature1) }

        let feature2 = Feature(name: "settings")
        let dataProvider2 = DataProvidingMock(feature: feature2)
        dataProvider1.updateSyncTimestamps(server: "5678", local: nil)
        dataProvider2._fetchChangedObjects = { _ in throw DataProviderError(feature: feature2) }

        let feature3 = Feature(name: "autofill")
        let dataProvider3 = DataProvidingMock(feature: feature3)
        dataProvider1.updateSyncTimestamps(server: "9012", local: nil)
        dataProvider3._fetchChangedObjects = { _ in [] }

        let syncOperation = SyncOperation(dataProviders: [dataProvider1, dataProvider2, dataProvider3], storage: storage, crypter: crypter, requestMaker: requestMaker)

        request.result = .init(data: "{\"autofill\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())

        await assertThrowsAnyError({
            try await syncOperation.sync(fetchOnly: false)
        }, errorHandler: { error in
            guard let syncOperationError = error as? SyncOperationError else {
                XCTFail("Unexpected error type: \(type(of: error))")
                return
            }
            XCTAssertEqual(syncOperationError.perFeatureErrors.count, 2)
            XCTAssertEqual(syncOperationError.perFeatureErrors[feature1] as? DataProviderError, DataProviderError(feature: feature1))
            XCTAssertEqual(syncOperationError.perFeatureErrors[feature2] as? DataProviderError, DataProviderError(feature: feature2))
        })
    }

    func testThatSentModelsAreEchoedInResults() async throws {
        let objectsToSync = [
            Syncable(jsonObject: ["id": "1", "name": "bookmark1", "url": "https://example.com"]),
            Syncable(jsonObject: ["id": "2", "name": "bookmark2", "url": "https://example.com"]),
        ]
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        var sentModels: [Syncable] = []
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        dataProvider._fetchChangedObjects = { _ in objectsToSync }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            sentModels = sent
        }

        let syncOperation = SyncOperation(dataProviders: [dataProvider], storage: storage, crypter: crypter, requestMaker: requestMaker)

        request.result = .init(data: nil, response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 304, httpVersion: nil, headerFields: nil)!)

        try await syncOperation.sync(fetchOnly: false)

        XCTAssertTrue(try sentModels.isJSONRepresentationEquivalent(to: objectsToSync))
    }

    func testWhenPatchPayloadCompressionSucceedsThenPayloadIsSentCompressed() async throws {
        let objectsToSync = [
            Syncable(jsonObject: ["id": "1", "name": "bookmark1", "url": "https://example.com"]),
        ]
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        var sentModels: [Syncable] = []
        var errors: [any Error] = []
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        dataProvider._fetchChangedObjects = { _ in objectsToSync }
        dataProvider._handleSyncError = { errors.append($0) }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            sentModels = sent
        }

        let syncOperation = SyncOperation(dataProviders: [dataProvider], storage: storage, crypter: crypter, requestMaker: requestMaker)
        request.result = .init(data: nil, response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 304, httpVersion: nil, headerFields: nil)!)

        try await syncOperation.sync(fetchOnly: false)

        XCTAssertTrue(try sentModels.isJSONRepresentationEquivalent(to: objectsToSync))
        XCTAssertEqual(requestMaker.makePatchRequestCallCount, 1)
        XCTAssertEqual(requestMaker.makePatchRequestCallArgs[0].isCompressed, true)
        XCTAssertTrue(errors.isEmpty)
    }

    func testWhenPatchPayloadCompressionFailsThenPayloadIsSentUncompressed() async throws {
        let errorCode = 100200300
        payloadCompressor.error = GzipError(code: Int32(errorCode), msg: nil)

        let objectsToSync = [
            Syncable(jsonObject: ["id": "1", "name": "bookmark1", "url": "https://example.com"]),
        ]
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        var sentModels: [Syncable] = []
        var errors: [any Error] = []
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        dataProvider._fetchChangedObjects = { _ in objectsToSync }
        dataProvider._handleSyncError = { errors.append($0) }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            sentModels = sent
        }

        let syncOperation = SyncOperation(dataProviders: [dataProvider], storage: storage, crypter: crypter, requestMaker: requestMaker)
        request.result = .init(data: nil, response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 304, httpVersion: nil, headerFields: nil)!)

        try await syncOperation.sync(fetchOnly: false)

        XCTAssertTrue(try sentModels.isJSONRepresentationEquivalent(to: objectsToSync))
        XCTAssertEqual(requestMaker.makePatchRequestCallCount, 2)
        XCTAssertEqual(requestMaker.makePatchRequestCallArgs[0].isCompressed, true)
        XCTAssertEqual(requestMaker.makePatchRequestCallArgs[1].isCompressed, false)
        XCTAssertEqual(errors.count, 1)
        let error = try XCTUnwrap(errors.first)
        guard case SyncError.patchPayloadCompressionFailed(errorCode) = error else {
            XCTFail("Unexpected error thrown: \(error)")
            return
        }
    }
}

private extension Array where Element == Syncable {
    func isJSONRepresentationEquivalent(to other: [Element]) throws -> Bool {
        let thisData = try JSONSerialization.data(withJSONObject: map(\.payload))
        let otherData = try JSONSerialization.data(withJSONObject: other.map(\.payload))
        return thisData == otherData
    }
}
