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

public struct UserAssistanceConfig: Decodable, Equatable, Sendable {
    public let enabledBrokers: Set<String>

    private enum CodingKeys: String, CodingKey {
        case enabledBrokers
    }

    public init() {
        enabledBrokers = []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let brokers = try container.decodeIfPresent([String].self, forKey: .enabledBrokers) ?? []
        // Brokers must be named one by one, so a "*" entry never turns this on for every broker.
        enabledBrokers = Set(brokers.filter { $0 != "*" })
    }

    public init(privacyConfig: PrivacyConfiguration) {
        guard let settings = privacyConfig.settings(for: DBPSubfeature.userAssistance),
              let data = settings.data(using: .utf8),
              let config = try? JSONDecoder().decode(Self.self, from: data) else {
            self.init()
            return
        }
        self = config
    }

    public var isEnabled: Bool { !enabledBrokers.isEmpty }

    public func isEnabled(forBrokerURL url: String) -> Bool {
        enabledBrokers.contains(url)
    }
}

public extension DataBroker {
    var requiresUserAssistance: Bool {
        optOutStep()?.actions.contains(where: \.requiresUserAssistance) ?? false
    }
}

public extension BrokerProfileJobDependencyProviding {
    var userAssistanceConfig: UserAssistanceConfig {
        guard featureFlagger.isUserAssistanceOn else { return UserAssistanceConfig() }
        return UserAssistanceConfig(privacyConfig: privacyConfig.privacyConfig)
    }
}
