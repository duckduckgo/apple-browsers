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
import WebKit

/// Names shared with the embedded extension's `UserAllowlistSync` component.
public enum UserAllowlistSync {
    /// The native messaging feature the extension pulls the allowlist from.
    public static let featureName = "userAllowlist"
    /// A manifest command with no shortcut. Performing it tells the extension the allowlist changed.
    /// WebKit wakes a sleeping background to deliver it, so this one signal covers an asleep and an awake extension.
    public static let changedCommandIdentifier = "ddg-allowlist-changed"
}

/// Tells the embedded extension when the user's allowlist changes.
///
/// `changes` may fire for unrelated reasons, such as content blocking rules recompiling after a config update, so
/// the notifier compares allowlist versions and signals the extension only when the list itself changed.
@MainActor
public final class UserAllowlistChangeNotifier {

    private let allowlist: () -> [String]
    private let notify: @MainActor () -> Void
    private var lastVersion: String
    private var cancellable: AnyCancellable?

    public init(changes: AnyPublisher<Void, Never>,
                allowlist: @escaping () -> [String],
                notify: @escaping @MainActor () -> Void) {
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
        let version = UserAllowlistSnapshot(domains: allowlist()).version
        guard version != lastVersion else { return }
        lastVersion = version
        notify()
    }
}

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Starts telling the embedded extension about allowlist changes.
    ///
    /// - Parameters:
    ///   - changes: Fires after the allowlist may have changed. Content blocking rules recompile after every
    ///     allowlist toggle, so their updates publisher is a suitable source.
    ///   - allowlist: The domains the user has turned protections off for.
    @MainActor
    public func installUserAllowlistNotifier(changes: AnyPublisher<Void, Never>, allowlist: @escaping () -> [String]) {
        guard userAllowlistNotifier == nil else { return }
        userAllowlistNotifier = UserAllowlistChangeNotifier(changes: changes, allowlist: allowlist) { [weak self] in
            self?.notifyEmbeddedExtensionUserAllowlistChanged()
        }
    }

    /// Performs the allowlist-changed command in the embedded extension, which then pulls the new list.
    ///
    /// The extension also pulls the list whenever its background starts, so a signal that cannot be delivered now
    /// (the extension is not loaded yet) is not lost.
    @MainActor
    public func notifyEmbeddedExtensionUserAllowlistChanged() {
        guard let context = embeddedBackgroundContextForNavigation, context.isLoaded else {
            Logger.webExtensions.debug("🛡️ Allowlist changed, but the embedded extension is not loaded")
            return
        }
        guard let command = context.commands.first(where: { $0.id == UserAllowlistSync.changedCommandIdentifier }) else {
            Logger.webExtensions.debug("🛡️ Allowlist changed, but the embedded extension has no allowlist command")
            return
        }
        Logger.webExtensions.debug("🛡️ Allowlist changed, so the embedded extension is told to sync")
        context.performCommand(command)
    }
}
