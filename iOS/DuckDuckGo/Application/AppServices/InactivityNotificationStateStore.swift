//
//  InactivityNotificationStateStore.swift
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

import Foundation
import Persistence
import Core

protocol InactivityNotificationStateStoring: AnyObject {
    var interactionCount: Int { get }
    func recordInteraction()
    func reset()
}

final class InactivityNotificationStateStore: InactivityNotificationStateStoring {
    enum StorageKey {
        static let interactionCount = "inactivity-notification.interaction-count"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var interactionCount: Int {
        (try? readInteractionCount()) ?? 0
    }

    func recordInteraction() {
        do {
            let next = try readInteractionCount() + 1
            try keyValueStore.set(next, forKey: StorageKey.interactionCount)
        } catch {
            Logger.pushNotification.error("Inactivity notification recordInteraction failed with \(error.localizedDescription, privacy: .public)")
        }
    }

    func reset() {
        do {
            try keyValueStore.set(nil, forKey: StorageKey.interactionCount)
        } catch {
            Logger.pushNotification.error("Inactivity notification reset failed with \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readInteractionCount() throws -> Int {
        try keyValueStore.object(forKey: StorageKey.interactionCount) as? Int ?? 0
    }
}
