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
import PrivacyConfig

public protocol ConfigurationURLProviding {
    func url(for configuration: Configuration) -> URL
}

public protocol CustomConfigurationURLSetting {
    func setCustomURL(_ url: URL?, for configuration: Configuration) throws
    /// Overrides the URL for this launch only. Nothing is persisted.
    func setSessionURL(_ url: URL, for configuration: Configuration)
    var isCustomURLEnabled: Bool { get }
    func isURLOverridden(for configuration: Configuration) -> Bool
    func state(for configuration: Configuration) -> ConfigurationURLState
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

/// Separates saved and session overrides from the URL actually used by configuration fetches.
public struct ConfigurationURLState: Sendable {
    public let defaultURL: URL
    public let savedOverrideURL: URL?
    public let sessionOverrideURL: URL?
    public let resolvedURL: URL
    public let overridesEnabled: Bool

    public init(defaultURL: URL, savedOverrideURL: URL?, sessionOverrideURL: URL?, resolvedURL: URL, overridesEnabled: Bool) {
        self.defaultURL = defaultURL
        self.savedOverrideURL = savedOverrideURL
        self.sessionOverrideURL = sessionOverrideURL
        self.resolvedURL = resolvedURL
        self.overridesEnabled = overridesEnabled
    }
}

public class ConfigurationURLProvider: CustomConfigurationURLProviding {

    private let defaultProvider: ConfigurationURLProviding
    private let internalUserDecider: InternalUserDecider
    private var store: CustomConfigurationURLStoring
    private var sessionURLs = [Configuration: URL]()

    public var isCustomURLEnabled: Bool {
        internalUserDecider.isInternalUser
    }

    public init(defaultProvider: ConfigurationURLProviding, internalUserDecider: InternalUserDecider, store: CustomConfigurationURLStoring) {
        self.defaultProvider = defaultProvider
        self.internalUserDecider = internalUserDecider
        self.store = store
    }

    public func url(for configuration: Configuration) -> URL {
        state(for: configuration).resolvedURL
    }

    public func state(for configuration: Configuration) -> ConfigurationURLState {
        let defaultURL = defaultProvider.url(for: configuration)
        let savedURL = savedOverrideURL(for: configuration)
        let sessionURL = sessionURLs[configuration]
        let resolvedURL = isCustomURLEnabled ? (sessionURL ?? savedURL ?? defaultURL) : defaultURL
        return ConfigurationURLState(defaultURL: defaultURL, savedOverrideURL: savedURL, sessionOverrideURL: sessionURL,
                                     resolvedURL: resolvedURL, overridesEnabled: isCustomURLEnabled)
    }

    private func savedOverrideURL(for configuration: Configuration) -> URL? {
        switch configuration {
        case .bloomFilterSpec: return store.customBloomFilterSpecURL
        case .bloomFilterBinary: return store.customBloomFilterBinaryURL
        case .bloomFilterExcludedDomains: return store.customBloomFilterExcludedDomainsURL
        case .privacyConfiguration: return store.customPrivacyConfigurationURL
        case .trackerDataSet: return store.customTrackerDataSetURL
        case .surrogates: return store.customSurrogatesURL
        case .remoteMessagingConfig: return store.customRemoteMessagingConfigURL
        }
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

    public func setSessionURL(_ url: URL, for configuration: Configuration) {
        sessionURLs[configuration] = url
    }

    public func isURLOverridden(for configuration: Configuration) -> Bool {
        sessionURLs[configuration] != nil || savedOverrideURL(for: configuration) != nil
    }
}
