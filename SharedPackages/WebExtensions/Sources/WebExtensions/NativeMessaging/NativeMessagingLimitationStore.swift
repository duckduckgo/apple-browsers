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

/// Remembers which extensions tried to talk to an app on the Mac in a build that can't allow it,
/// such as the App Store build, so Settings can tell the user that some of their features won't work.
/// Keyed by store ID, so the note survives extension updates.
@MainActor
public protocol NativeMessagingLimitationStoreProtocol: AnyObject {
    func hasHitLimitation(storeIdentifier: String) -> Bool
    func recordLimitation(storeIdentifier: String)
    func forget(storeIdentifier: String)
}

@MainActor
public final class NativeMessagingLimitationStore: NativeMessagingLimitationStoreProtocol {
    private let key = "web-extension-native-messaging-limitation"
    private let keyValueStore: any ThrowingKeyValueStoring

    nonisolated public init(keyValueStore: any ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public func hasHitLimitation(storeIdentifier: String) -> Bool {
        storeIdentifiers.contains(storeIdentifier)
    }

    public func recordLimitation(storeIdentifier: String) {
        save(storeIdentifiers.union([storeIdentifier]))
    }

    public func forget(storeIdentifier: String) {
        save(storeIdentifiers.subtracting([storeIdentifier]))
    }

    private var storeIdentifiers: Set<String> {
        do {
            return Set(try keyValueStore.object(forKey: key) as? [String] ?? [])
        } catch {
            Logger.webExtensions.error("Could not read the native messaging limitation: \(error.localizedDescription)")
            return []
        }
    }

    private func save(_ identifiers: Set<String>) {
        do {
            try keyValueStore.set(identifiers.sorted(), forKey: key)
        } catch {
            Logger.webExtensions.error("Could not save the native messaging limitation: \(error.localizedDescription)")
        }
    }
}
