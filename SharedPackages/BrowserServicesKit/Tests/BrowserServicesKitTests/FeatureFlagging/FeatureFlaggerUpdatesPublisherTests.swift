//
//  FeatureFlaggerUpdatesPublisherTests.swift
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
import Combine
import PersistenceTestingUtils
@testable import BrowserServicesKit

final class FeatureFlaggerUpdatesPublisherTests: XCTestCase {

    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)
    }

    override func tearDown() {
        cancellables = nil
        unsetenv("TESTS_FEATUREFLAGGER_MODE")
        super.tearDown()
    }

    func testUpdatesPublisherFiresWhenPrivacyConfigUpdates() {
        // Given
        let mockEmbeddedData = MockEmbeddedDataProvider(data: "{}".data(using: .utf8)!, etag: "test")
        let privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let featureFlagger = DefaultFeatureFlagger(
            internalUserDecider: DefaultInternalUserDecider(store: MockInternalUserStoring()),
            privacyConfigManager: privacyConfigManager,
            experimentManager: nil
        )

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Publisher fires on privacy config update")

        featureFlagger.updatesPublisher
            .sink {
                updateCount += 1
                if updateCount == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        privacyConfigManager.reload(etag: "new-etag", data: "{}".data(using: .utf8)!)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(updateCount, 1)
    }

    func testUpdatesPublisherFiresWhenLocalOverrideChanges() {
        // Given
        let mockEmbeddedData = MockEmbeddedDataProvider(data: "{}".data(using: .utf8)!, etag: "test")
        let privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let internalUserStore = MockInternalUserStoring()
        internalUserStore.isInternalUser = true
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserStore)

        let actionHandler = FeatureFlagOverridesPublishingHandler<TestFeatureFlag>()
        let overrides = FeatureFlagLocalOverrides(
            persistor: FeatureFlagLocalOverridesUserDefaultsPersistor(keyValueStore: MockKeyValueStore()),
            actionHandler: actionHandler
        )

        let featureFlagger = DefaultFeatureFlagger(
            internalUserDecider: internalUserDecider,
            privacyConfigManager: privacyConfigManager,
            localOverrides: overrides,
            experimentManager: nil,
            for: TestFeatureFlag.self
        )

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Publisher fires on override change")

        featureFlagger.updatesPublisher
            .sink {
                updateCount += 1
                if updateCount == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(updateCount, 1)
    }

    func testMockFeatureFlaggerUpdatesPublisher() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        var updateCount = 0
        let expectation = XCTestExpectation(description: "Mock publisher fires when triggered")

        mockFeatureFlagger.updatesPublisher
            .sink {
                updateCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockFeatureFlagger.triggerUpdate()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(updateCount, 1)
    }
}
