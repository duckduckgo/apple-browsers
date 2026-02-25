//
//  RemoteBrokerJSONServiceTests.swift
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
import Foundation
import SecureStorage
import BrowserServicesKit
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class RemoteBrokerJSONServiceTests: XCTestCase {

    let repository = BrokerUpdaterRepositoryMock()
    let resources = ResourcesRepositoryMock()
    let pixelHandler = MockDataBrokerProtectionPixelsHandler()
    let runTypeProvider = MockAppRunTypeProvider()
    let vault: DataBrokerProtectionSecureVaultMock = try! DataBrokerProtectionSecureVaultMock(providers:
                                                                                                SecureStorageProviders(
                                                                                                    crypto: EmptySecureStorageCryptoProviderMock(),
                                                                                                    database: SecureStorageDatabaseProviderMock(),
                                                                                                    keystore: EmptySecureStorageKeyStoreProviderMock()))
    var settings: DataBrokerProtectionSettings!
    let fileManager = MockFileManager()
    let authenticationManager = MockAuthenticationManager()

    var urlSession: URLSession {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    var localBrokerJSONService: BrokerJSONFallbackProvider!
    var remoteBrokerJSONService: BrokerJSONServiceProvider!

    override func setUp() {
        localBrokerJSONService = LocalBrokerJSONService(repository: repository,
                                                        resources: resources,
                                                        vault: vault,
                                                        pixelHandler: pixelHandler,
                                                        runTypeProvider: runTypeProvider)

        let defaults = UserDefaults(suiteName: "com.dbp.tests.\(UUID().uuidString)")!
        settings = DataBrokerProtectionSettings(defaults: defaults)
        remoteBrokerJSONService = RemoteBrokerJSONService(featureFlagger: MockFeatureFlagger(),
                                                          settings: settings,
                                                          vault: vault,
                                                          fileManager: fileManager,
                                                          urlSession: urlSession,
                                                          authenticationManager: authenticationManager,
                                                          pixelHandler: pixelHandler,
                                                          localBrokerProvider: localBrokerJSONService)
    }

    override func tearDown() {
        MockURLProtocol.requestHandlerQueue.removeAll()
        repository.reset()
        resources.reset()
        vault.reset()
        pixelHandler.clear()
    }

    func testCheckForUpdatesFollowsRateLimit() async {
        /// First attempt
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.notModified, nil) }

        XCTAssertEqual(settings.lastBrokerJSONUpdateCheckTimestamp, 0)
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            /// Successful attempt, lastBrokerJSONUpdateCheckTimestamp should've been updated
            XCTAssert(settings.lastBrokerJSONUpdateCheckTimestamp > 0)
        } catch {
            XCTFail("Unexpected error")
        }

        /// Second attempt
        var lastCheckTimestamp = settings.lastBrokerJSONUpdateCheckTimestamp
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            /// Failed attempt (rate limited), lastBrokerJSONUpdateCheckTimestamp should've remained unchanged
            XCTAssertEqual(lastCheckTimestamp, settings.lastBrokerJSONUpdateCheckTimestamp)
        } catch {
            XCTFail("Unexpected error")
        }

        /// Third attempt
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.notModified, nil) }

        settings.updateLastSuccessfulBrokerJSONUpdateCheckTimestamp(Date.daysAgo(1).timeIntervalSince1970)
        lastCheckTimestamp = settings.lastBrokerJSONUpdateCheckTimestamp
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            /// Successful attempt, lastBrokerJSONUpdateCheckTimestamp should've been updated
            XCTAssert(settings.lastBrokerJSONUpdateCheckTimestamp > lastCheckTimestamp)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesReturnsEarlyWhen304() async {
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.notModified, nil) }
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.noAuth, nil) }
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            /// checkForUpdates() returns early so 2nd request is never invoked
            XCTAssertFalse(MockURLProtocol.requestHandlerQueue.isEmpty)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesThrowsServerErrorWhenResponseCodeIsNotExpected() async {
        let expectation = XCTestExpectation(description: "Server error")

        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.noAuth, nil) }
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            XCTFail("Unexpected error")
        } catch RemoteBrokerJSONService.Error.serverError {
            expectation.fulfill()
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesThrowsServerErrorWhenResponseContainsNoETag() async {
        let expectation = XCTestExpectation(description: "Server error")

        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.ok, nil) }
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            XCTFail("Unexpected error")
        } catch RemoteBrokerJSONService.Error.serverError {
            expectation.fulfill()
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesThrowsJSONDecodingErrorWhenResponseIsInvalid() async {
        let expectation = XCTestExpectation(description: "JSON decoding error")

        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.okWithETag, Data()) }
        do {
            try await remoteBrokerJSONService.checkForUpdates()
            XCTFail("Unexpected error")
        } catch DecodingError.dataCorrupted {
            expectation.fulfill()
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesDetectsNoChangesInRemoteJSONs() async {
        let mainConfig = MainConfig(mainConfigETag: "",
                                    activeDataBrokers: [],
                                    jsonETags: .init(current: [:]),
                                    testDataBrokers: [])
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.okWithETag, try! JSONEncoder().encode(mainConfig)) }
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.noAuth, nil) }

        do {
            try await remoteBrokerJSONService.checkForUpdates()
            /// checkForUpdates() returns early so 2nd request is never invoked
            XCTAssertFalse(MockURLProtocol.requestHandlerQueue.isEmpty)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesThrowsServerErrorWhenFailingToDownloadRemoteJSONs() async {
        let expectation = XCTestExpectation(description: "Server error")

        let mainConfig = MainConfig(mainConfigETag: "",
                                    activeDataBrokers: [],
                                    jsonETags: .init(current: ["fakebroker.com": "something"]),
                                    testDataBrokers: [])
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.okWithETag, try! JSONEncoder().encode(mainConfig)) }
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.noAuth, nil) }

        do {
            try await remoteBrokerJSONService.checkForUpdates()
        } catch RemoteBrokerJSONService.Error.serverError {
            expectation.fulfill()
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testCheckForUpdatesProceedsToTheEnd() async {
        let mainConfig = MainConfig(mainConfigETag: "",
                                    activeDataBrokers: [],
                                    jsonETags: .init(current: ["fakebroker.com": "something", "fakebroker2.com": "something", "fakebroker3.com": "something"]),
                                    testDataBrokers: [])
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.okWithETag, try! JSONEncoder().encode(mainConfig)) }
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.ok, nil) }

        do {
            try await remoteBrokerJSONService.checkForUpdates()
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testWhenProcessBrokerJSONsSucceeds_thenSuccessPixelIsFired() throws {
        let testBrokerContent = """
        {
            "name": "Test Broker",
            "url": "broker.com",
            "steps": [],
            "version": "1.0.0",
            "schedulingConfig": {
                "retryError": 48,
                "confirmOptOutScan": 72,
                "maintenanceScan": 120,
                "maxAttempts": -1
            },
            "optOutUrl": "https://broker.com/optout"
        }
        """

        let realFileManager = FileManager.default
        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: realFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        let tempDir = realFileManager.temporaryDirectory.appendingPathComponent("test-etag")
        let jsonDir = tempDir.appendingPathComponent("json")
        try realFileManager.createDirectory(at: jsonDir, withIntermediateDirectories: true)

        let testFile = jsonDir.appendingPathComponent("broker.com.json")
        try testBrokerContent.write(to: testFile, atomically: true, encoding: .utf8)

        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag",
            fileNames: ["broker.com.json"],
            eTagMapping: ["broker.com.json": "etag123"],
            activeBrokers: ["broker.com.json"],
            testBrokers: []
        )

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let successPixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersSuccess(let dataBrokerFileName, let removedAt):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(successPixels.isEmpty, "updateDataBrokersSuccess pixel should be fired")
        let (dataBroker, removedAt) = successPixels.first!
        XCTAssertEqual(dataBroker, "broker.com.json")
        XCTAssertNil(removedAt, "removedAt should be nil for broker without removal date")

        // Clean up
        try? realFileManager.removeItem(at: tempDir)
    }

    func testWhenProcessBrokerJSONsWithRemovedAt_thenSuccessPixelIsFiredWithTimestamp() throws {
        let removedTimestamp: Int64 = 1693526400000
        let testBrokerContent = """
        {
            "name": "Removed Broker",
            "url": "removedbroker.com",
            "steps": [],
            "version": "1.0.0",
            "schedulingConfig": {
                "retryError": 48,
                "confirmOptOutScan": 72,
                "maintenanceScan": 120,
                "maxAttempts": -1
            },
            "optOutUrl": "https://removedbroker.com/optout",
            "removedAt": \(removedTimestamp)
        }
        """

        let realFileManager = FileManager.default
        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: realFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        let tempDir = realFileManager.temporaryDirectory.appendingPathComponent("test-etag-removed")
        let jsonDir = tempDir.appendingPathComponent("json")
        try realFileManager.createDirectory(at: jsonDir, withIntermediateDirectories: true)

        let testFile = jsonDir.appendingPathComponent("removedbroker.com.json")
        try testBrokerContent.write(to: testFile, atomically: true, encoding: .utf8)

        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-removed",
            fileNames: ["removedbroker.com.json"],
            eTagMapping: ["removedbroker.com.json": "etag456"],
            activeBrokers: ["removedbroker.com.json"],
            testBrokers: []
        )

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let successPixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersSuccess(let dataBrokerFileName, let removedAt):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(successPixels.isEmpty, "updateDataBrokersSuccess pixel should be fired")
        let (dataBroker, removedAt) = successPixels.first!
        XCTAssertEqual(dataBroker, "removedbroker.com.json")
        XCTAssertEqual(removedAt, removedTimestamp, "removedAt should match the timestamp from JSON")

        // Clean up
        try? realFileManager.removeItem(at: tempDir)
    }

    func testWhenProcessBrokerJSONsUpdatesExistingBroker_thenVaultUpdateUsesRawFilePayload() throws {
        // Given: broker JSON contains fields not modeled by native action structs.
        let testBrokerContent = """
        {
            "name": "Broker",
            "url": "example.com",
            "steps": [
                {
                    "stepType": "scan",
                    "actions": [
                        {
                            "actionType": "navigate",
                            "id": "navigate-1",
                            "url": "https://example.com",
                            "newField": "hello-world",
                            "anotherNewField": {
                                "flag": true
                            }
                        }
                    ]
                }
            ],
            "version": "1.0.1",
            "schedulingConfig": {
                "retryError": 48,
                "confirmOptOutScan": 72,
                "maintenanceScan": 120,
                "maxAttempts": -1
            },
            "optOutUrl": "https://example.com"
        }
        """

        vault.shouldReturnOldVersionBroker = true

        let realFileManager = FileManager.default
        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: realFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        let tempDir = realFileManager.temporaryDirectory.appendingPathComponent("test-etag-raw-payload")
        let jsonDir = tempDir.appendingPathComponent("json")
        try realFileManager.createDirectory(at: jsonDir, withIntermediateDirectories: true)

        let testFile = jsonDir.appendingPathComponent("example.com.json")
        try testBrokerContent.write(to: testFile, atomically: true, encoding: .utf8)

        // When: processing JSONs for an existing broker (update path, not insert path).
        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-raw-payload",
            fileNames: ["example.com.json"],
            eTagMapping: ["example.com.json": "etag-raw"],
            activeBrokers: ["example.com.json"],
            testBrokers: []
        )

        // Then: vault update is used and raw bytes are forwarded as-is.
        XCTAssertTrue(vault.wasBrokerUpdateCalled)
        XCTAssertFalse(vault.wasBrokerSavedCalled)

        let updatedBrokerResource = try XCTUnwrap(vault.lastUpdatedBrokerResource)
        XCTAssertEqual(updatedBrokerResource.rawJSON, Data(testBrokerContent.utf8))
        XCTAssertEqual(updatedBrokerResource.broker.eTag, "etag-raw")

        // And: decoded raw JSON still contains full broker shape.
        let decodedRawBrokerJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: updatedBrokerResource.rawJSON) as? [String: Any]
        )
        XCTAssertEqual(decodedRawBrokerJSON["name"] as? String, "Broker")
        XCTAssertEqual(decodedRawBrokerJSON["url"] as? String, "example.com")
        XCTAssertEqual(decodedRawBrokerJSON["version"] as? String, "1.0.1")
        XCTAssertEqual(decodedRawBrokerJSON["optOutUrl"] as? String, "https://example.com")

        let schedulingConfig = try XCTUnwrap(decodedRawBrokerJSON["schedulingConfig"] as? [String: Any])
        XCTAssertEqual(schedulingConfig["retryError"] as? Int, 48)
        XCTAssertEqual(schedulingConfig["confirmOptOutScan"] as? Int, 72)
        XCTAssertEqual(schedulingConfig["maintenanceScan"] as? Int, 120)
        XCTAssertEqual(schedulingConfig["maxAttempts"] as? Int, -1)

        let steps = try XCTUnwrap(decodedRawBrokerJSON["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 1)
        let step = try XCTUnwrap(steps.first)
        XCTAssertEqual(step["stepType"] as? String, "scan")

        let actions = try XCTUnwrap(step["actions"] as? [[String: Any]])
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action["actionType"] as? String, "navigate")
        XCTAssertEqual(action["id"] as? String, "navigate-1")
        XCTAssertEqual(action["url"] as? String, "https://example.com")

        // Critical assertion: unknown broker-owned fields are preserved.
        XCTAssertEqual(action["newField"] as? String, "hello-world")

        let anotherNewField = try XCTUnwrap(action["anotherNewField"] as? [String: Any])
        XCTAssertEqual(anotherNewField["flag"] as? Bool, true)

        // Clean up
        try? realFileManager.removeItem(at: tempDir)
    }

    func testWhenProcessBrokerJSONsWithInvalidJSON_thenFailurePixelIsFired() throws {
        let invalidBrokerContent = "{ invalid json content"

        let realFileManager = FileManager.default
        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: realFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        let tempDir = realFileManager.temporaryDirectory.appendingPathComponent("test-etag-invalid")
        let jsonDir = tempDir.appendingPathComponent("json")
        try realFileManager.createDirectory(at: jsonDir, withIntermediateDirectories: true)

        let testFile = jsonDir.appendingPathComponent("invalidbroker.com.json")
        try invalidBrokerContent.write(to: testFile, atomically: true, encoding: .utf8)

        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-invalid",
            fileNames: ["invalidbroker.com.json"],
            eTagMapping: ["invalidbroker.com.json": "etag789"],
            activeBrokers: ["invalidbroker.com.json"],
            testBrokers: []
        )

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let failurePixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersFailure(let dataBrokerFileName, let removedAt, _):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(failurePixels.isEmpty, "updateDataBrokersFailure pixel should be fired for invalid JSON")
        let (dataBroker, removedAt) = failurePixels.first!
        XCTAssertEqual(dataBroker, "invalidbroker.com.json")
        XCTAssertNil(removedAt, "removedAt should be nil when JSON decoding fails")

        // Clean up
        try? realFileManager.removeItem(at: tempDir)
    }

    func testWhenProcessBrokerJSONsWithUpsertFailure_thenFailurePixelIsFired() throws {
        let testBrokerContent = """
        {
            "name": "Test Broker",
            "url": "broker.com",
            "steps": [],
            "version": "1.0.1",
            "schedulingConfig": {
                "retryError": 48,
                "confirmOptOutScan": 72,
                "maintenanceScan": 120,
                "maxAttempts": -1
            },
            "optOutUrl": "https://broker.com/optout"
        }
        """

        // Configure vault to throw on update
        vault.shouldReturnOldVersionBroker = true // Ensure broker exists so update path is taken
        vault.shouldThrowOnUpdate = true

        let realFileManager = FileManager.default
        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: realFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        let tempDir = realFileManager.temporaryDirectory.appendingPathComponent("test-etag-upsert-fail")
        let jsonDir = tempDir.appendingPathComponent("json")
        try realFileManager.createDirectory(at: jsonDir, withIntermediateDirectories: true)

        let testFile = jsonDir.appendingPathComponent("broker.com.json")
        try testBrokerContent.write(to: testFile, atomically: true, encoding: .utf8)

        // This should throw due to upsert failure, but should fire a failure pixel
        XCTAssertThrowsError(try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-upsert-fail",
            fileNames: ["broker.com.json"],
            eTagMapping: ["broker.com.json": "etag999"],
            activeBrokers: ["broker.com.json"],
            testBrokers: []))

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let failurePixels = firedPixels.compactMap { pixel in
            switch pixel {
            case .updateDataBrokersFailure(let dataBrokerFileName, let removedAt, _):
                return (dataBrokerFileName, removedAt)
            default:
                return nil
            }
        }

        XCTAssertFalse(failurePixels.isEmpty, "updateDataBrokersFailure pixel should be fired for upsert failure")
        let (dataBroker, removedAt) = failurePixels.first!
        XCTAssertEqual(dataBroker, "broker.com.json")
        XCTAssertNil(removedAt, "removedAt should be nil when upsert fails")

        // Clean up
        try? realFileManager.removeItem(at: tempDir)
        vault.shouldReturnOldVersionBroker = false
        vault.shouldThrowOnUpdate = false
    }

}

extension HTTPURLResponse {
    static let okWithETag = HTTPURLResponse(url: URL(string: "http://www.example.com")!,
                                            statusCode: 200,
                                            httpVersion: nil,
                                            headerFields: ["ETag": "something"])!
}

private class MockFeatureFlagger: RemoteBrokerDeliveryFeatureFlagging {
    var isRemoteBrokerDeliveryFeatureOn: Bool { true }
}
