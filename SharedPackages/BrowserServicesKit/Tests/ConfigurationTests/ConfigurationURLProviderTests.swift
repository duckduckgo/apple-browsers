//
//  ConfigurationURLProviderTests.swift
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

import BrowserServicesKit
@testable import Configuration
import Combine
import Testing
import Foundation

final class ConfigurationURLProviderTests {

    var sut: ConfigurationURLProvider!
    var mockDefaultProvider: MockConfigurationURLProvider!
    var mockInternalUserDecider: MockInternalUserDecider!
    var mockStore: MockCustomConfigurationURLStore!

    init() {
        mockDefaultProvider = MockConfigurationURLProvider()
        mockInternalUserDecider = MockInternalUserDecider()
        mockStore = MockCustomConfigurationURLStore()

        sut = ConfigurationURLProvider(
            defaultProvider: mockDefaultProvider,
            internalUserDecider: mockInternalUserDecider,
            store: mockStore
        )
    }

    @Test("Check Default URL Is Returned When No Internal User", arguments: Configuration.allCases)
    func whenIsNotInternalUserThenReturnDefaultURL(config: Configuration) {
        // Given
        mockInternalUserDecider.isInternalUser = false
        let defaultURL = URL(string: "https://default.example.com")!
        mockDefaultProvider.url = defaultURL
        mockStore.customBloomFilterSpecURL = URL(string: "https://custom.example.com")
        mockStore.customBloomFilterBinaryURL = URL(string: "https://custom-binary.example.com")
        mockStore.customBloomFilterExcludedDomainsURL = URL(string: "https://custom-excluded.example.com")
        mockStore.customPrivacyConfigurationURL = URL(string: "https://custom-privacy.example.com")
        mockStore.customTrackerDataSetURL = URL(string: "https://custom-tracker.example.com")
        mockStore.customSurrogatesURL = URL(string: "https://custom-surrogates.example.com")
        mockStore.customRemoteMessagingConfigURL = URL(string: "https://custom-messaging.example.com")

        // When
        let result = sut.url(for: config)

        // Then
        #expect(result == defaultURL)
    }

    // Parameterized arguments for custom URL cases
    static let customURLCases: [(Configuration, (MockCustomConfigurationURLStore, URL?) -> Void, String)] = [
        (.bloomFilterSpec, { $0.customBloomFilterSpecURL = $1 }, "https://custom.example.com"),
        (.bloomFilterBinary, { $0.customBloomFilterBinaryURL = $1 }, "https://custom-binary.example.com"),
        (.bloomFilterExcludedDomains, { $0.customBloomFilterExcludedDomainsURL = $1 }, "https://custom-excluded.example.com"),
        (.privacyConfiguration, { $0.customPrivacyConfigurationURL = $1 }, "https://custom-privacy.example.com"),
        (.trackerDataSet, { $0.customTrackerDataSetURL = $1 }, "https://custom-tracker.example.com"),
        (.surrogates, { $0.customSurrogatesURL = $1 }, "https://custom-surrogates.example.com"),
        (.remoteMessagingConfig, { $0.customRemoteMessagingConfigURL = $1 }, "https://custom-messaging.example.com"),
    ]

    @Test("Custom URL is returned when set", arguments: customURLCases)
    func customURLIsReturnedWhenSet(config: Configuration, setCustomURL: (MockCustomConfigurationURLStore, URL?) -> Void, urlString: String) {
        // Given
        mockInternalUserDecider.isInternalUser = true
        let customURL = URL(string: urlString)!

        // When
        setCustomURL(mockStore, customURL)
        let result = sut.url(for: config)

        // Then
        #expect(result == customURL)
    }

    @Test("Custom URL is not set when not internal user", arguments: customURLCases)
    func setCustomURL_WhenCustomURLsDisabled_DoesNotUpdateStore(config: Configuration, setCustomURL: (MockCustomConfigurationURLStore, URL?) -> Void, urlString: String) {
        // Given
        mockInternalUserDecider.isInternalUser = false

        // When
        let customURL = URL(string: urlString)!
        try? sut.setCustomURL(customURL, for: config)

        // Then
        var value: URL?
        switch config {
        case .bloomFilterSpec: value = mockStore.customBloomFilterSpecURL
        case .bloomFilterBinary: value = mockStore.customBloomFilterBinaryURL
        case .bloomFilterExcludedDomains: value = mockStore.customBloomFilterExcludedDomainsURL
        case .privacyConfiguration: value = mockStore.customPrivacyConfigurationURL
        case .trackerDataSet: value = mockStore.customTrackerDataSetURL
        case .surrogates: value = mockStore.customSurrogatesURL
        case .remoteMessagingConfig: value = mockStore.customRemoteMessagingConfigURL
        }
        #expect(value == nil)
    }

    @Test("setCustomURL updates store when enabled", arguments: customURLCases)
    func setCustomURL_WhenCustomURLsEnabled_UpdatesStore(config: Configuration, setCustomURL: (MockCustomConfigurationURLStore, URL?) -> Void, urlString: String) {
        // Given
        mockInternalUserDecider.isInternalUser = true
        let customURL = URL(string: urlString)!

        // When
        try? sut.setCustomURL(customURL, for: config)

        // Then
        var value: URL?
        switch config {
        case .bloomFilterSpec: value = mockStore.customBloomFilterSpecURL
        case .bloomFilterBinary: value = mockStore.customBloomFilterBinaryURL
        case .bloomFilterExcludedDomains: value = mockStore.customBloomFilterExcludedDomainsURL
        case .privacyConfiguration: value = mockStore.customPrivacyConfigurationURL
        case .trackerDataSet: value = mockStore.customTrackerDataSetURL
        case .surrogates: value = mockStore.customSurrogatesURL
        case .remoteMessagingConfig: value = mockStore.customRemoteMessagingConfigURL
        }
        #expect(value == customURL)
    }

    @Test("setCustomURL to nil clears store when enabled", arguments: customURLCases)
    func setCustomURLToNil_WhenCustomURLsEnabled_ClearsStoreValue(config: Configuration, setCustomURL: (MockCustomConfigurationURLStore, URL?) -> Void, urlString: String) {
        // Given
        mockInternalUserDecider.isInternalUser = true
        let customURL = URL(string: urlString)!
        setCustomURL(mockStore, customURL)

        // When
        try? sut.setCustomURL(nil, for: config)

        // Then
        var value: URL?
        switch config {
        case .bloomFilterSpec: value = mockStore.customBloomFilterSpecURL
        case .bloomFilterBinary: value = mockStore.customBloomFilterBinaryURL
        case .bloomFilterExcludedDomains: value = mockStore.customBloomFilterExcludedDomainsURL
        case .privacyConfiguration: value = mockStore.customPrivacyConfigurationURL
        case .trackerDataSet: value = mockStore.customTrackerDataSetURL
        case .surrogates: value = mockStore.customSurrogatesURL
        case .remoteMessagingConfig: value = mockStore.customRemoteMessagingConfigURL
        }
        #expect(value == nil)
    }
}
