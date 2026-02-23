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
import WebExtensions
import WebKit

/// Manages the set of domains where DarkReader (force dark mode) should be blocked,
/// and translates domain changes into web extension permission updates.
///
/// Blocked domains are sourced from the `forceDarkModeOnWebsites` privacy configuration exceptions list.
final class DarkReaderDomainManager {

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    /// Domains that have been applied as permissions to the extension context.
    private var appliedBlockedDomains: Set<String> = []

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    /// All domains where dark mode should be blocked (from privacy configuration exceptions list).
    var blockedDomains: Set<String> {
        Set(
            privacyConfigurationManager.privacyConfig
                .exceptionsList(forFeature: .forceDarkModeOnWebsites)
        )
    }

    /// Publisher that fires whenever the privacy config updates (and thus the blocked domains may have changed).
    var blockedDomainsPublisher: AnyPublisher<Set<String>, Never> {
        privacyConfigurationManager.updatesPublisher
            .map { [weak self] in
                self?.blockedDomains ?? []
            }
            .eraseToAnyPublisher()
    }

    /// Records domains that have already been applied (e.g. during initial install).
    func recordAppliedDomains(_ domains: Set<String>) {
        appliedBlockedDomains = domains
    }

    /// Computes match pattern permission changes needed to transition from the previously applied
    /// state to the current blocked domains, and records the new state.
    @available(iOS 18.4, *)
    func makePermissionUpdates() -> [WebExtensionMatchPatternPermission] {
        let currentDomains = blockedDomains
        let domainsToRemove = appliedBlockedDomains.subtracting(currentDomains)
        let domainsToAdd = currentDomains.subtracting(appliedBlockedDomains)

        guard !domainsToRemove.isEmpty || !domainsToAdd.isEmpty else { return [] }

        var permissions: [WebExtensionMatchPatternPermission] = []
        for domain in domainsToRemove {
            permissions.append(contentsOf: Self.matchPatternPermissions(for: domain, status: .grantedExplicitly))
        }
        for domain in domainsToAdd {
            permissions.append(contentsOf: Self.matchPatternPermissions(for: domain, status: .deniedExplicitly))
        }

        appliedBlockedDomains = currentDomains
        return permissions
    }

    @available(iOS 18.4, *)
    private static func matchPatternPermissions(for domain: String,
                                                status: WKWebExtensionContext.PermissionStatus) -> [WebExtensionMatchPatternPermission] {
        var permissions: [WebExtensionMatchPatternPermission] = []

        if let exact = try? WKWebExtension.MatchPattern(string: "*://\(domain)/*") {
            permissions.append(WebExtensionMatchPatternPermission(matchPattern: exact, status: status))
        }
        if !domain.hasPrefix("*."), let wildcard = try? WKWebExtension.MatchPattern(string: "*://*.\(domain)/*") {
            permissions.append(WebExtensionMatchPatternPermission(matchPattern: wildcard, status: status))
        }

        return permissions
    }
}
