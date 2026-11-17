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

/// Names shared with the embedded extension's `UserAllowlistSync` component.
public enum UserAllowlistSync {
    /// The native messaging feature the extension pulls the allowlist from.
    public static let featureName = "userAllowlist"
    /// The subscription event native sends, with `version` and `domains`, when the allowlist changes.
    public static let changedSubscriptionName = "onAllowlistChanged"
}

/// Tells the embedded extension when the user's allowlist changes.
///
/// `changes` may fire for unrelated reasons, such as content blocking rules recompiling after a config update, so
/// the notifier compares allowlist versions and signals the extension only when the list itself changed.
@MainActor
public final class UserAllowlistChangeNotifier {

    private let allowlist: () -> [String]
    private let notify: @MainActor (UserAllowlistSnapshot) -> Void
    private var lastVersion: String
    private var cancellable: AnyCancellable?

    public init(changes: AnyPublisher<Void, Never>,
                allowlist: @escaping () -> [String],
                notify: @escaping @MainActor (UserAllowlistSnapshot) -> Void) {
        self.allowlist = allowlist
        self.notify = notify
        self.lastVersion = UserAllowlistSnapshot(domains: allowlist()).version
        cancellable = changes.sink { [weak self] in
            DispatchQueue.main.asyncOrNow {
                self?.checkForChange()
            }
        }
    }

    func checkForChange() {
        let snapshot = UserAllowlistSnapshot(domains: allowlist())
        guard snapshot.version != lastVersion else { return }
        lastVersion = snapshot.version
        notify(snapshot)
    }
}

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Starts sending allowlist changes to the embedded extension as `UserAllowlistSync.changedSubscriptionName`
    /// subscription events.
    ///
    /// - Parameters:
    ///   - changes: Fires after the allowlist may have changed. Content blocking rules recompile after every
    ///     allowlist toggle, so their updates publisher is a suitable source.
    ///   - allowlist: The domains the user has turned protections off for.
    @MainActor
    public func installUserAllowlistNotifier(changes: AnyPublisher<Void, Never>, allowlist: @escaping () -> [String]) {
        guard userAllowlistNotifier == nil else { return }
        userAllowlistNotifier = UserAllowlistChangeNotifier(changes: changes, allowlist: allowlist) { [weak self] snapshot in
            Logger.webExtensions.debug("🛡️ Allowlist changed (\(snapshot.domains.count, privacy: .public) domains)")
            self?.sendSubscriptionEvent(WebExtensionSubscriptionEvent(
                featureName: UserAllowlistSync.featureName,
                subscriptionName: UserAllowlistSync.changedSubscriptionName,
                params: ["version": snapshot.version, "domains": snapshot.domains]
            ))
        }
    }
}
