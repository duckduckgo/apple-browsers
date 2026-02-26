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
    let fileManager = MockFileManager(fixtureBundle: .module)
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
        let fixtureFileName = "valid-broker"
        let mockFileManager = MockFileManager(fixtureBundle: .module, fixtureFileNames: [fixtureFileName])
        mockFileManager.hasUnzippedContent = true

        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: mockFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag",
            fileNames: ["\(fixtureFileName).json"],
            eTagMapping: ["\(fixtureFileName).json": "etag123"],
            activeBrokers: ["\(fixtureFileName).json"],
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
        XCTAssertEqual(dataBroker, "\(fixtureFileName).json")
        XCTAssertNil(removedAt, "removedAt should be nil for broker without removal date")
    }

    func testWhenProcessBrokerJSONsWithRemovedAt_thenSuccessPixelIsFiredWithTimestamp() throws {
        let removedTimestamp: Int64 = 1693526400000
        let fixtureFileName = "valid-broker-removed-1.0.1"
        let mockFileManager = MockFileManager(fixtureBundle: .module, fixtureFileNames: [fixtureFileName])
        mockFileManager.hasUnzippedContent = true

        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: mockFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-removed",
            fileNames: ["\(fixtureFileName).json"],
            eTagMapping: ["\(fixtureFileName).json": "etag456"],
            activeBrokers: ["\(fixtureFileName).json"],
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
        XCTAssertEqual(dataBroker, "\(fixtureFileName).json")
        XCTAssertEqual(removedAt, removedTimestamp, "removedAt should match the timestamp from JSON")
    }

    func testWhenProcessBrokerJSONsUpdatesExistingBroker_thenVaultUpdateUsesRawFilePayload() throws {
        // Given: broker fixture JSON contains fields not modeled by DataBroker, e.g. addedDatetime.
        let fixtureFileName = "valid-broker-1.0.1"
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: fixtureFileName,
            withExtension: "json",
            subdirectory: "BundleResources"
        ))
        let expectedRawJSON = try Data(contentsOf: fixtureURL)
        vault.shouldReturnOldVersionBroker = true

        let mockFileManager = MockFileManager(fixtureBundle: .module)
        mockFileManager.hasUnzippedContent = true

        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: mockFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        // When: processing JSONs for an existing broker (update path, not insert path).
        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-raw-payload",
            fileNames: ["\(fixtureFileName).json"],
            eTagMapping: ["\(fixtureFileName).json": "etag-raw"],
            activeBrokers: ["\(fixtureFileName).json"],
            testBrokers: []
        )

        // Then: vault update is used and raw bytes are forwarded as-is.
        XCTAssertTrue(vault.wasBrokerUpdateCalled)
        XCTAssertFalse(vault.wasBrokerSavedCalled)

        let updatedBrokerResource = try XCTUnwrap(vault.lastUpdatedBrokerResource)
        XCTAssertEqual(updatedBrokerResource.rawJSON, expectedRawJSON)
        XCTAssertEqual(updatedBrokerResource.broker.eTag, "etag-raw")

        // And: decoded raw JSON still contains full fixture shape.
        let decodedRawBrokerJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: updatedBrokerResource.rawJSON) as? [String: Any]
        )
        XCTAssertEqual(decodedRawBrokerJSON["name"] as? String, "DDG Fake Broker")
        XCTAssertEqual(decodedRawBrokerJSON["url"] as? String, "fakebroker.com")
        XCTAssertEqual(decodedRawBrokerJSON["version"] as? String, "1.0.1")
        XCTAssertEqual((decodedRawBrokerJSON["addedDatetime"] as? NSNumber)?.int64Value, 1725632531153)
        XCTAssertTrue(decodedRawBrokerJSON["removedAt"] is NSNull)

        let schedulingConfig = try XCTUnwrap(decodedRawBrokerJSON["schedulingConfig"] as? [String: Any])
        XCTAssertEqual(schedulingConfig["retryError"] as? Int, 48)
        XCTAssertEqual(schedulingConfig["confirmOptOutScan"] as? Int, 0)
        XCTAssertEqual(schedulingConfig["maintenanceScan"] as? Int, 120)
        XCTAssertEqual(schedulingConfig["maxAttempts"] as? Int, -1)

        let steps = try XCTUnwrap(decodedRawBrokerJSON["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 2)
        let step = try XCTUnwrap(steps.first(where: { $0["stepType"] as? String == "scan" }))

        let actions = try XCTUnwrap(step["actions"] as? [[String: Any]])
        XCTAssertEqual(actions.count, 3)
    }

    func testWhenProcessBrokerJSONsWithInvalidJSON_thenFailurePixelIsFired() throws {
        let fixtureFileName = "invalid-broker-with-unsupported-action"
        let mockFileManager = MockFileManager(fixtureBundle: .module, fixtureFileNames: [fixtureFileName])
        mockFileManager.hasUnzippedContent = true

        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: mockFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-invalid",
            fileNames: ["\(fixtureFileName).json"],
            eTagMapping: ["\(fixtureFileName).json": "etag789"],
            activeBrokers: ["\(fixtureFileName).json"],
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
        XCTAssertEqual(dataBroker, "\(fixtureFileName).json")
        XCTAssertNil(removedAt, "removedAt should be nil when JSON decoding fails")
    }

    func testWhenProcessBrokerJSONsWithUpsertFailure_thenFailurePixelIsFired() throws {
        // Configure vault to throw on update
        vault.shouldReturnOldVersionBroker = true // Ensure broker exists so update path is taken
        vault.shouldThrowOnUpdate = true

        let fixtureFileName = "valid-broker-1.0.1"
        let mockFileManager = MockFileManager(fixtureBundle: .module, fixtureFileNames: [fixtureFileName])
        mockFileManager.hasUnzippedContent = true

        let testRemoteService = RemoteBrokerJSONService(
            featureFlagger: MockFeatureFlagger(),
            settings: settings,
            vault: vault,
            fileManager: mockFileManager,
            urlSession: urlSession,
            authenticationManager: authenticationManager,
            pixelHandler: pixelHandler,
            localBrokerProvider: localBrokerJSONService
        )

        // This should throw due to upsert failure, but should fire a failure pixel
        XCTAssertThrowsError(try testRemoteService.processBrokerJSONs(
            eTag: "test-etag-upsert-fail",
            fileNames: ["\(fixtureFileName).json"],
            eTagMapping: ["\(fixtureFileName).json": "etag999"],
            activeBrokers: ["\(fixtureFileName).json"],
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
        XCTAssertEqual(dataBroker, "\(fixtureFileName).json")
        XCTAssertNil(removedAt, "removedAt should be nil when upsert fails")
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
