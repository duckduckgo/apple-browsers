//
//  CustomConfigurationURLProvider.swift
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

import Foundation
import BrowserServicesKit

public protocol ConfigurationURLProviding {
    func url(for configuration: Configuration) -> URL
}

public protocol CustomConfigurationURLSetting {
    func setCustomURL(_ url: URL?, for configuration: Configuration) throws
    var isCustomURLEnabled: Bool { get }
    func isURLOverridden(for configuration: Configuration) -> Bool
}

public enum URLSettingError: LocalizedError {
    case notInternalUser

    public var errorDescription: String? {
        switch self {
        case .notInternalUser:
            return "Not an internal user"
        }
    }
}

public typealias CustomConfigurationURLProviding = ConfigurationURLProviding & CustomConfigurationURLSetting

public class ConfigurationURLProvider: CustomConfigurationURLProviding {

    private let defaultProvider: ConfigurationURLProviding
    private let internalUserDecider: InternalUserDecider
    private var store: CustomConfigurationURLStoring

    public var isCustomURLEnabled: Bool {
        internalUserDecider.isInternalUser
    }

    public init(defaultProvider: ConfigurationURLProviding, internalUserDecider: InternalUserDecider, store: CustomConfigurationURLStoring) {
        self.defaultProvider = defaultProvider
        self.internalUserDecider = internalUserDecider
        self.store = store
    }

    public func url(for configuration: Configuration) -> URL {
        let defaultURL = defaultProvider.url(for: configuration)
        guard isCustomURLEnabled else { return defaultURL }

        let customURL: URL?
        switch configuration {
        case .bloomFilterSpec: customURL = store.customBloomFilterSpecURL
        case .bloomFilterBinary: customURL = store.customBloomFilterBinaryURL
        case .bloomFilterExcludedDomains: customURL = store.customBloomFilterExcludedDomainsURL
        case .privacyConfiguration: customURL = store.customPrivacyConfigurationURL
        case .trackerDataSet: customURL = store.customTrackerDataSetURL
        case .surrogates: customURL = store.customSurrogatesURL
        case .remoteMessagingConfig: customURL = store.customRemoteMessagingConfigURL
        }
        return customURL ?? defaultURL
    }

    public func setCustomURL(_ url: URL?, for configuration: Configuration) throws {
        guard isCustomURLEnabled else { throw  URLSettingError.notInternalUser }
        switch configuration {
        case .bloomFilterSpec:
            store.customBloomFilterSpecURL = url
        case .bloomFilterBinary:
            store.customBloomFilterBinaryURL = url
        case .bloomFilterExcludedDomains:
            store.customBloomFilterExcludedDomainsURL = url
        case .privacyConfiguration:
            store.customPrivacyConfigurationURL = url
        case .surrogates:
            store.customSurrogatesURL = url
        case .trackerDataSet:
            store.customTrackerDataSetURL = url
        case .remoteMessagingConfig:
            store.customRemoteMessagingConfigURL = url
        }
    }

    public func isURLOverridden(for configuration: Configuration) -> Bool {
        switch configuration {
        case .bloomFilterSpec:
            return store.customBloomFilterSpecURL != nil
        case .bloomFilterBinary:
            return store.customBloomFilterBinaryURL != nil
        case .bloomFilterExcludedDomains:
            return store.customBloomFilterExcludedDomainsURL != nil
        case .privacyConfiguration:
            return store.customPrivacyConfigurationURL != nil
        case .surrogates:
            return store.customSurrogatesURL != nil
        case .trackerDataSet:
            return store.customTrackerDataSetURL != nil
        case .remoteMessagingConfig:
            return store.customRemoteMessagingConfigURL != nil
        }
    }
}
