//
//  CustomConfigurationURLStorage.swift
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

public protocol CustomConfigurationURLStoring {
    var customBloomFilterSpecURL: URL? { get set }
    var customBloomFilterBinaryURL: URL? { get set }
    var customBloomFilterExcludedDomainsURL: URL? { get set }
    var customPrivacyConfigurationURL: URL? { get set }
    var customTrackerDataSetURL: URL? { get set }
    var customSurrogatesURL: URL? { get set }
    var customRemoteMessagingConfigURL: URL? { get set }
}

public final class CustomConfigurationURLStorage: CustomConfigurationURLStoring {

    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults,
                keyPrefix: String = "CustomConfigurationURL") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private func key(_ name: String) -> String {
        return "\(keyPrefix).\(name)"
    }

    public var customBloomFilterSpecURL: URL? {
        get { defaults.url(forKey: key("bloomFilterSpec")) }
        set { defaults.set(newValue, forKey: key("bloomFilterSpec")) }
    }

    public var customBloomFilterBinaryURL: URL? {
        get { defaults.url(forKey: key("bloomFilterBinary")) }
        set { defaults.set(newValue, forKey: key("bloomFilterBinary")) }
    }

    public var customBloomFilterExcludedDomainsURL: URL? {
        get { defaults.url(forKey: key("bloomFilterExcludedDomains")) }
        set { defaults.set(newValue, forKey: key("bloomFilterExcludedDomains")) }
    }

    public var customPrivacyConfigurationURL: URL? {
        get { defaults.url(forKey: key("privacyConfiguration")) }
        set { defaults.set(newValue, forKey: key("privacyConfiguration")) }
    }

    public var customTrackerDataSetURL: URL? {
        get { defaults.url(forKey: key("trackerDataSet")) }
        set { defaults.set(newValue, forKey: key("trackerDataSet")) }
    }

    public var customSurrogatesURL: URL? {
        get { defaults.url(forKey: key("surrogates")) }
        set { defaults.set(newValue, forKey: key("surrogates")) }
    }

    public var customRemoteMessagingConfigURL: URL? {
        get { defaults.url(forKey: key("remoteMessagingConfig")) }
        set { defaults.set(newValue, forKey: key("remoteMessagingConfig")) }
    }
}
