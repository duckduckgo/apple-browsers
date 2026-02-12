//
//  DarkReaderDomainManager.swift
//  DuckDuckGo
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

import Combine
import Foundation
import PrivacyConfig

/// Manages the set of domains where DarkReader (force dark mode) should be blocked.
///
/// Merges two sources:
/// 1. A hardcoded blocklist (e.g. `duckduckgo.com`)
/// 2. Server-controlled exceptions from the `forceWebsiteDarkMode` privacy config feature
final class DarkReaderDomainManager {

    private static let hardcodedBlockedDomains: Set<String> = ["duckduckgo.com"]

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    /// All domains where dark mode should be blocked (hardcoded + server exceptions).
    var blockedDomains: Set<String> {
        let serverExceptions = Set(
            privacyConfigurationManager.privacyConfig
                .exceptionsList(forFeature: .forceWebsiteDarkMode)
        )
        return Self.hardcodedBlockedDomains.union(serverExceptions)
    }

    /// Publisher that fires whenever the privacy config updates (and thus the blocked domains may have changed).
    var blockedDomainsPublisher: AnyPublisher<Set<String>, Never> {
        privacyConfigurationManager.updatesPublisher
            .map { [weak self] in
                self?.blockedDomains ?? Self.hardcodedBlockedDomains
            }
            .eraseToAnyPublisher()
    }
}
