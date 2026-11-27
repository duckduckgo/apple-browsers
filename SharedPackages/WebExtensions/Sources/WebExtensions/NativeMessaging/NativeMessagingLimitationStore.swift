//
//  NativeMessagingLimitationStore.swift
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
import os.log
import Persistence

/// Remembers, across launches, which extensions tried to talk to an app on the Mac in a build that can't allow it,
/// such as the App Store build, and which of them the user asked not to be warned about again.
/// Keyed by store ID where there is one, so the state survives extension updates.
@MainActor
public protocol NativeMessagingLimitationStoreProtocol: AnyObject {
    func hasHitLimitation(extensionKey: String) -> Bool
    func recordLimitation(extensionKey: String)
    func isAlertSuppressed(extensionKey: String) -> Bool
    func suppressAlert(extensionKey: String)
    func forget(extensionKey: String)
}

@MainActor
public final class NativeMessagingLimitationStore: NativeMessagingLimitationStoreProtocol {
    private enum Key: String {
        case limited = "web-extension-native-messaging-limitation"
        case alertSuppressed = "web-extension-native-messaging-alert-suppressed"
    }

    private let keyValueStore: any ThrowingKeyValueStoring

    nonisolated public init(keyValueStore: any ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public func hasHitLimitation(extensionKey: String) -> Bool {
        keys(for: .limited).contains(extensionKey)
    }

    public func recordLimitation(extensionKey: String) {
        save(keys(for: .limited).union([extensionKey]), for: .limited)
    }

    public func isAlertSuppressed(extensionKey: String) -> Bool {
        keys(for: .alertSuppressed).contains(extensionKey)
    }

    public func suppressAlert(extensionKey: String) {
        save(keys(for: .alertSuppressed).union([extensionKey]), for: .alertSuppressed)
    }

    public func forget(extensionKey: String) {
        save(keys(for: .limited).subtracting([extensionKey]), for: .limited)
        save(keys(for: .alertSuppressed).subtracting([extensionKey]), for: .alertSuppressed)
    }

    private func keys(for key: Key) -> Set<String> {
        do {
            return Set(try keyValueStore.object(forKey: key.rawValue) as? [String] ?? [])
        } catch {
            Logger.webExtensions.error("Could not read the native messaging limitation: \(error.localizedDescription)")
            return []
        }
    }

    private func save(_ extensionKeys: Set<String>, for key: Key) {
        do {
            try keyValueStore.set(extensionKeys.sorted(), forKey: key.rawValue)
        } catch {
            Logger.webExtensions.error("Could not save the native messaging limitation: \(error.localizedDescription)")
        }
    }
}
