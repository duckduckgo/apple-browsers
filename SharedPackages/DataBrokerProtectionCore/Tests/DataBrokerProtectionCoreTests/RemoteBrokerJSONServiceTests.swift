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
                                                        pixelHandler: pixelHandler)

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
