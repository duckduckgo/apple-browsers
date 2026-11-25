//
//  ConfigurationManagerTests.swift
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

import Common
import XCTest
@_spi(Testing) import Persistence
@testable import Configuration
@_spi(Testing) @testable import Networking

final class MockConfigurationManager: DefaultConfigurationManager {

    @Locked private(set) var dependencyProvider = MockDependencyProvider()
    var name: String?

    override func refreshNow(isDebug: Bool = false) async {
        let configFetched = await fetchConfigDependencies(isDebug: isDebug)
        if configFetched {
            updateConfigDependencies()
        }
    }

    func fetchConfigDependencies(isDebug: Bool) async -> Bool {
        do {
            let fetchResult = try await fetcher.fetch(.privacyConfiguration, isDebug: isDebug)
            return fetchResult == .updated
        } catch {
            return false
        }
    }

    @Locked var onDependenciesUpdated: (@Sendable () -> Void)?
    func updateConfigDependencies() {
        dependencyProvider = MockDependencyProvider(privacyConfigEtag: store.loadEtag(for: .privacyConfiguration),
                                                    privacyConfigData: store.loadData(for: .privacyConfiguration))
        onDependenciesUpdated?()
    }

    override var presentedItemURL: URL? {
        return store.fileUrl(for: .privacyConfiguration).deletingLastPathComponent()
    }

    override func presentedSubitemDidAppear(at url: URL) {
        guard url == store.fileUrl(for: .privacyConfiguration) else { return }
        updateConfigDependencies()
    }

    override func presentedSubitemDidChange(at url: URL) {
        guard url == store.fileUrl(for: .privacyConfiguration) else { return }
        updateConfigDependencies()
    }
}

struct MockDependencyProvider {
    var privacyConfigEtag: String?
    var privacyConfigData: Data?
}

final class ConfigurationManagerTests: XCTestCase {

    // Shared "UserDefaults" to mock app group defaults
    private let defaultsSuite = UUID().uuidString
    private var sharedDefaults: UserDefaults!
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
    private var configurationManagers: [DefaultConfigurationManager] = []

    override func setUpWithError() throws {
        sharedDefaults = UserDefaults(suiteName: defaultsSuite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        APIRequest.Headers.setUserAgent("")
    }

    override func tearDownWithError() throws {
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.requestHandler = nil
        configurationManagers.forEach { $0.tearDown() }
        configurationManagers = []
        sharedDefaults.removePersistentDomain(forName: defaultsSuite)
        try FileManager.default.removeItem(at: directory)
    }

    func testWhenTryAgainSoonIsCalledThenRefreshIsDeferredRatherThanTriggeredImmediately() {
        let manager = makeConfigurationManager()

        manager.tryAgainSoon()

        XCTAssertFalse(manager.isReadyToRefresh,
                       "tryAgainSoon() must delay the next refresh; dating lastUpdateTime in the past makes every subsequent check refresh immediately")
        XCTAssertGreaterThan(manager.lastUpdateTime, Date(),
                             "The retry is scheduled by pushing lastUpdateTime forward, not back")
    }

    func makeConfigurationFetcher(store: ConfigurationStoring,
                                  validator: ConfigurationValidating = MockValidator()) -> ConfigurationFetcher {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return ConfigurationFetcher(store: store,
                                    validator: validator,
                                    sessionProvider: { URLSession(configuration: testConfiguration) },
                                    configurationURLProvider: MockConfigurationURLProvider())
    }

    func makeConfigurationManager(name: String? = nil) -> MockConfigurationManager {
        let configStore = MockStoreWithStorage(directory: directory, etagStorage: sharedDefaults)
        let manager = MockConfigurationManager(fetcher: makeConfigurationFetcher(store: configStore),
                                               store: configStore,
                                               defaults: sharedDefaults)
        manager.name = name

        configurationManagers.append(manager)
        return manager
    }

    func testWhenConfigIsFetchedAndStoredDependencyIsUpdated() async {
        let configurationManager = makeConfigurationManager()

        let configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await configurationManager.refreshNow()

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(configurationManager.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(configurationManager.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

    func testWhenConfigIsNotModifiedThenDependencyIsNotUpdated() async {
        let configurationManager = makeConfigurationManager()
        let didUpdateDependencies = Locked(wrappedValue: false)
        configurationManager.onDependenciesUpdated = {
            didUpdateDependencies.wrappedValue = true
        }

        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.notModified, nil) }
        await configurationManager.refreshNow()

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertFalse(didUpdateDependencies.wrappedValue)
        XCTAssertNil(configurationManager.dependencyProvider.privacyConfigData)
        XCTAssertNil(configurationManager.dependencyProvider.privacyConfigEtag)
    }

    func testWhenManagerAIsUpdatedManagerBIsAlsoUpdated() async throws {
        let managerA = makeConfigurationManager(name: "A")
        let managerB = makeConfigurationManager(name: "B")

        let e = XCTestExpectation(description: "ConfigManager B updated")
        managerB.onDependenciesUpdated = {
            e.fulfill()
        }

        let configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerA.refreshNow()
        await fulfillment(of: [e], timeout: 10)

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

    func testWhenManagerBReceivesNewDataManagerAHasDataAfter304Response() async throws {
        let managerA = makeConfigurationManager()
        let managerB = makeConfigurationManager()

        let managerBUpdated = XCTestExpectation(description: "ConfigManager B updated")
        managerB.onDependenciesUpdated = {
            managerBUpdated.fulfill()
        }

        let firstData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, firstData) }
        await managerA.refreshNow()
        await fulfillment(of: [managerBUpdated], timeout: 10)

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, firstData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)

        MockURLProtocol.lastRequest = nil
        let managerAUpdated = XCTestExpectation(description: "ConfigManager A updated")
        managerB.onDependenciesUpdated = nil
        managerA.onDependenciesUpdated = {
            managerAUpdated.fulfill()
        }

        let configData = Data("Privacy Config 2".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerB.refreshNow()
        await fulfillment(of: [managerAUpdated], timeout: 10)

        XCTAssertNotNil(MockURLProtocol.lastRequest)

        let configDataExpectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            return managerA.dependencyProvider.privacyConfigData == configData
        }, object: .none)

        let configEtagExpectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            return managerA.dependencyProvider.privacyConfigEtag == HTTPURLResponse.testEtag
        }, object: .none)

        await fulfillment(of: [configDataExpectation, configEtagExpectation], timeout: 5)

        MockURLProtocol.lastRequest = nil
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.notModified, nil) }
        await managerA.refreshNow()

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(managerA.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerA.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

    func testWhenManagerBReceivesAnErrorItKeepsDataFromManagerA() async throws {
        let managerA = makeConfigurationManager()
        let managerB = makeConfigurationManager()

        let e = XCTestExpectation(description: "ConfigManager B updated")
        managerB.onDependenciesUpdated = {
            e.fulfill()
        }

        let configData = Data("Privacy Config".utf8)
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, configData) }
        await managerA.refreshNow()
        await fulfillment(of: [e], timeout: 10)

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)

        MockURLProtocol.lastRequest = nil
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        await managerB.refreshNow()

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigData, configData)
        XCTAssertEqual(managerB.dependencyProvider.privacyConfigEtag, HTTPURLResponse.testEtag)
    }

}
