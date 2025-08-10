//
//  ConfigurationFetcherTests.swift
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
@testable import Configuration
@testable import Networking
import NetworkingTestingUtils

final class ConfigurationFetcherTests: XCTestCase {

    enum MockError: Error {
        case someError
    }

    var configurationURLProvider: MockConfigurationURLProvider!

    override func setUp() {
        configurationURLProvider = MockConfigurationURLProvider()
        APIRequest.Headers.setUserAgent("")
    }

    override func tearDown() {
        configurationURLProvider = nil
        MockURLProtocol.lastRequest = nil
    }

    func makeConfigurationFetcher(store: ConfigurationStoring = MockStore(),
                                  validator: ConfigurationValidating = MockValidator()) -> ConfigurationFetcher {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return ConfigurationFetcher(store: store,
                                    validator: validator,
                                    sessionProvider: { URLSession(configuration: testConfiguration) },
                                    configurationURLProvider: configurationURLProvider)
    }

    let privacyConfigurationData = Data("Privacy Config".utf8)

    // MARK: - Tests for fetch(_:)

    func testFetchConfigurationWhenEtagAndDataAreStoredThenResponseIsStored() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, self.privacyConfigurationData) }
        let oldEtag = UUID().uuidString
        let oldData = Data()
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (oldEtag, oldData)

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertEqual(store.loadData(for: .privacyConfiguration), self.privacyConfigurationData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfiguration), HTTPURLResponse.testEtag)
    }

    func testFetchConfigurationWhenNoEtagIsStoredThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)
        try await fetcher.fetch(.privacyConfiguration)
        XCTAssertEqual(store.loadData(for: .privacyConfiguration), self.privacyConfigurationData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfiguration), HTTPURLResponse.testEtag)
    }

    func testFetchConfigurationWhenEtagIsStoredButStoreHasNoDataThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (HTTPURLResponse.testEtag, nil)

        let fetcher = makeConfigurationFetcher(store: store)
        try await fetcher.fetch(.privacyConfiguration)

        XCTAssertNotNil(store.loadData(for: .privacyConfiguration))
    }

    func testFetchConfigurationWhenStoringDataFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.defaultSaveData = { _, _ in throw MockError.someError }

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertNil(store.loadData(for: .privacyConfiguration))
        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
    }

    func testFetchConfigurationWhenStoringEtagFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.defaultSaveEtag = { _, _ in throw MockError.someError }

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
    }

    func testFetchConfigurationWhenResponseIsNotModifiedThenNoDataStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, nil) }
        let store = MockStore()

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
        XCTAssertNil(store.loadData(for: .privacyConfiguration))
    }

    func testFetchConfigurationWhenEtagAndDataStoredThenEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch), etag)
    }

    func testFetchConfigurationWhenNoEtagStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (nil, Data())

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch))
    }

    func testFetchConfigurationWhenNoDataStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, nil)

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch))
    }

    func testFetchConfigurationWhenEtagProvidedThenItIsAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch), etag)
    }

    func testFetchConfigurationWhenEmbeddedEtagAndExternalEtagProvidedThenExternalAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let embeddedEtag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())
        store.configToEmbeddedEtag[.privacyConfiguration] = embeddedEtag

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(.privacyConfiguration)

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch), etag)
    }

    // MARK: - Tests for fetch(all:)

    func testFetchAllWhenOneAssetFailsToFetchThenOtherIsNotStoredAndErrorIsThrown() async {
        let bloomUrl = URL(string: "https://example.com")!
        configurationURLProvider.url = bloomUrl
        MockURLProtocol.requestHandler = { request in
            if let url = request.url, url == bloomUrl {
                return (HTTPURLResponse.internalServerError, nil)
            } else {
                return (HTTPURLResponse.ok, Data("Bloom Filter Spec".utf8))
            }
        }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)
        do {
            try await fetcher.fetch(all: [.bloomFilterBinary, .bloomFilterSpec])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let apiRequestError = error as? APIRequest.Error,
                  case .invalidStatusCode(500) = apiRequestError else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
        XCTAssertNil(store.loadData(for: .bloomFilterBinary))
        XCTAssertNil(store.loadData(for: .bloomFilterSpec))
    }

    func testFetchAllWhenOneAssetFailsToValidateThenOtherIsNotStoredAndErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let validatorMock = MockValidator()
        validatorMock.shouldThrowErrorPerConfiguration[.privacyConfiguration] = true
        validatorMock.shouldThrowErrorPerConfiguration[.trackerDataSet] = false

        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store, validator: validatorMock)
        do {
            try await fetcher.fetch(all: [.privacyConfiguration, .trackerDataSet])
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let fetcherError = error as? ConfigurationFetcher.Error,
                  case .invalidPayload = fetcherError
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
        XCTAssertNil(store.loadData(for: .privacyConfiguration))
        XCTAssertNil(store.loadData(for: .trackerDataSet))
    }

    func testFetchAllWhenEtagAndDataAreStoredThenResponseIsStored() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, self.privacyConfigurationData) }
        let oldEtag = UUID().uuidString
        let oldData = Data()
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (oldEtag, oldData)

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertEqual(store.loadData(for: .privacyConfiguration), self.privacyConfigurationData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfiguration), HTTPURLResponse.testEtag)
    }

    func testFetchAllWhenNoEtagIsStoredThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)
        try await fetcher.fetch(all: [.privacyConfiguration])
        XCTAssertEqual(store.loadData(for: .privacyConfiguration), self.privacyConfigurationData)
        XCTAssertEqual(store.loadEtag(for: .privacyConfiguration), HTTPURLResponse.testEtag)
    }

    func testFetchAllWhenEtagIsStoredButStoreHasNoDataThenResponseIsStored() async throws {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (HTTPURLResponse.testEtag, nil)

        let fetcher = makeConfigurationFetcher(store: store)
        try await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertNotNil(store.loadData(for: .privacyConfiguration))
    }

    func testFetchAllWhenStoringDataFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.defaultSaveData = { _, _ in throw MockError.someError }

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertNil(store.loadData(for: .privacyConfiguration))
        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
    }

    func testFetchAllWhenStoringEtagFailsThenEtagIsNotStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, self.privacyConfigurationData) }
        let store = MockStore()
        store.defaultSaveEtag = { _, _ in throw MockError.someError }

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
    }

    func testFetchAllWhenResponseIsNotModifiedThenNoDataStored() async {
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, nil) }
        let store = MockStore()

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertNil(store.loadEtag(for: .privacyConfiguration))
        XCTAssertNil(store.loadData(for: .privacyConfiguration))
    }

    func testFetchAllWhenEtagAndDataStoredThenEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch), etag)
    }

    func testFetchAllWhenNoEtagStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (nil, Data())

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch))
    }

    func testFetchAllWhenNoDataStoredThenNoEtagAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, nil)

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch))
    }

    func testFetchAllWhenEtagProvidedThenItIsAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch), etag)
    }

    func testFetchAllWhenEmbeddedEtagAndExternalEtagProvidedThenExternalAddedToRequest() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let etag = UUID().uuidString
        let embeddedEtag = UUID().uuidString
        let store = MockStore()
        store.configToStoredEtagAndData[.privacyConfiguration] = (etag, Data())
        store.configToEmbeddedEtag[.privacyConfiguration] = embeddedEtag

        let fetcher = makeConfigurationFetcher(store: store)
        try? await fetcher.fetch(all: [.privacyConfiguration])

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: HTTPHeaderKey.ifNoneMatch), etag)
    }

    func testFetchConfigurationCallsURLProviderWithCorrectConfiguration() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, self.privacyConfigurationData) }

        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)

        try? await fetcher.fetch(.trackerDataSet)

        XCTAssertEqual(configurationURLProvider.capturedConfiguration, .trackerDataSet)
    }

    func testFetchConfigurationUsesURLFromProvider() async throws {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, self.privacyConfigurationData) }
        let expectedURL = URL(string: "https://test.example.com")!
        configurationURLProvider.url = expectedURL

        let store = MockStore()
        let fetcher = makeConfigurationFetcher(store: store)

        try await fetcher.fetch(.privacyConfiguration)

        XCTAssertEqual(MockURLProtocol.lastRequest?.url, expectedURL)
    }

}
