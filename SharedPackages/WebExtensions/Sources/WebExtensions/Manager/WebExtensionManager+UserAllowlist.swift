//
//  WebExtensionManager+UserAllowlist.swift
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
import ConcurrencyExtensions
import Foundation
import os.log
import PrivacyConfig

/// Names shared with the embedded extension's `UserAllowlistSync` component.
public enum UserAllowlistSync {
    /// The native messaging feature the extension pulls the allowlist from.
    public static let featureName = "userAllowlist"
    /// The subscription event native sends, with `version` and `domains`, when the allowlist changes.
    public static let changedSubscriptionName = "onAllowlistChanged"
}

/// Tells the embedded extension when the user's allowlist changes, by passing the current list to `notify` on the
/// main thread each time `changes` fires.
@MainActor
public final class UserAllowlistChangeNotifier {

    private var cancellable: AnyCancellable?

    public init(changes: AnyPublisher<Void, Never>,
                allowlist: @escaping () -> [String],
                notify: @escaping @MainActor (UserAllowlistSnapshot) -> Void) {
        cancellable = changes.sink {
            DispatchQueue.main.asyncOrNow {
                notify(UserAllowlistSnapshot(domains: allowlist()))
            }
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Starts sending allowlist changes to the embedded extension as `UserAllowlistSync.changedSubscriptionName`
    /// subscription events.
    ///
    /// The extension hears about a change as soon as the privacy configuration stores it, without waiting for
    /// content blocking rules to be rebuilt.
    ///
    /// - Parameter privacyConfigurationManager: Stores the domains the user has turned protections off for, and
    ///   publishes when they change.
    @MainActor
    public func installUserAllowlistNotifier(privacyConfigurationManager: PrivacyConfigurationManaging) {
        guard userAllowlistNotifier == nil else { return }
        userAllowlistNotifier = UserAllowlistChangeNotifier(
            changes: privacyConfigurationManager.userUnprotectedDomainsPublisher,
            allowlist: { [privacyConfigurationManager] in privacyConfigurationManager.privacyConfig.userUnprotectedDomains }
        ) { [weak self] snapshot in
            Logger.webExtensions.debug("🛡️ Allowlist changed (\(snapshot.domains.count, privacy: .public) domains)")
            self?.sendSubscriptionEvent(WebExtensionSubscriptionEvent(
                featureName: UserAllowlistSync.featureName,
                subscriptionName: UserAllowlistSync.changedSubscriptionName,
                params: ["version": snapshot.version, "domains": snapshot.domains]
            ))
        }
    }
}
