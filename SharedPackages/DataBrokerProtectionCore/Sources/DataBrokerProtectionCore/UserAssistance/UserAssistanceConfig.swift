//
//  UserAssistanceConfig.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// Which brokers' opt-outs wait for the user to start them, from the `dbp.userAssistance` subfeature or a local debug override.
public struct UserAssistanceConfig: Equatable, Sendable {
    public let enabledBrokers: Set<String>

    public init(enabledBrokers: Set<String>) {
        self.enabledBrokers = enabledBrokers
    }

    public static let disabled = UserAssistanceConfig(enabledBrokers: [])

    public var isEnabled: Bool { !enabledBrokers.isEmpty }

    public func isEnabled(forBrokerURL url: String) -> Bool {
        enabledBrokers.contains(url)
    }

    public static func current(privacyConfig: PrivacyConfiguration, settings: DataBrokerProtectionSettings) -> UserAssistanceConfig {
        if let override = settings.userAssistanceEnabledBrokersOverride {
            return UserAssistanceConfig(enabledBrokers: Set(override))
        }
        guard privacyConfig.isSubfeatureEnabled(DBPSubfeature.userAssistance) else { return .disabled }
        return UserAssistanceConfig(enabledBrokers: Set(enabledBrokers(fromSettings: privacyConfig.settings(for: DBPSubfeature.userAssistance))))
    }

    static func enabledBrokers(fromSettings settings: String?) -> [String] {
        struct Settings: Decodable {
            let enabledBrokers: [String]?
        }
        guard let data = settings?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else { return [] }
        return decoded.enabledBrokers ?? []
    }
}

public extension BrokerProfileJobDependencyProviding {
    var userAssistanceConfig: UserAssistanceConfig {
        .current(privacyConfig: privacyConfig.privacyConfig, settings: dataBrokerProtectionSettings)
    }
}

public extension DataBrokerProtectionSettings {
    static let userAssistanceTestBrokers = ["beenverified.com", "fakeassistedbroker.com"]

    /// Set from the PIR debug menu; nil follows remote config.
    var userAssistanceEnabledBrokersOverride: [String]? {
        get { defaults.stringArray(forKey: Keys.userAssistanceEnabledBrokersOverride) }
        set { defaults.set(newValue, forKey: Keys.userAssistanceEnabledBrokersOverride) }
    }
}
