//
//  NativeMessagingNoticeStore.swift
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

/// Remembers which installed extensions tried to reach a native messaging host the app can't start,
/// and whether the user has been told about it.
@MainActor
public protocol NativeMessagingNoticeStoring: AnyObject {

    /// Records that the extension with `identifier` tried to reach its native messaging host.
    /// Returns `true` the first time, so the caller can count each extension once.
    @discardableResult
    func recordAttempt(for identifier: String) -> Bool

    /// Whether the extension tried to reach its host and the user hasn't seen the notice about it yet.
    func needsNotice(for identifier: String) -> Bool

    /// Records that the user has seen the notice about the extension.
    func markNoticeShown(for identifier: String)

    /// Forgets the extension, for example after it is uninstalled.
    func forget(_ identifier: String)
}

/// Keeps the state in the key-value store, keyed by the extension's installation identifier, so an
/// extension that is removed and added again shows the notice again.
@MainActor
public final class NativeMessagingNoticeStore: NativeMessagingNoticeStoring {
    private enum State: String, Codable {
        case attempted, noticeShown
    }

    private let key = "web-extension-native-messaging-notices"
    private let keyValueStore: any ThrowingKeyValueStoring

    public init(keyValueStore: any ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    @discardableResult
    public func recordAttempt(for identifier: String) -> Bool {
        var states = load()
        guard states[identifier] == nil else { return false }
        states[identifier] = .attempted
        save(states)
        return true
    }

    public func needsNotice(for identifier: String) -> Bool {
        load()[identifier] == .attempted
    }

    public func markNoticeShown(for identifier: String) {
        var states = load()
        guard states[identifier] != nil else { return }
        states[identifier] = .noticeShown
        save(states)
    }

    public func forget(_ identifier: String) {
        var states = load()
        guard states.removeValue(forKey: identifier) != nil else { return }
        save(states)
    }

    private func load() -> [String: State] {
        do {
            guard let data = try keyValueStore.object(forKey: key) as? Data else { return [:] }
            return try JSONDecoder().decode([String: State].self, from: data)
        } catch {
            Logger.webExtensions.error("Could not read native messaging notices: \(error.localizedDescription)")
            return [:]
        }
    }

    private func save(_ states: [String: State]) {
        do {
            try keyValueStore.set(JSONEncoder().encode(states), forKey: key)
        } catch {
            Logger.webExtensions.error("Could not save native messaging notices: \(error.localizedDescription)")
        }
    }
}
