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
        do {
            return try keyValueStore.object(forKey: StorageKey.interactionCount) as? Int ?? 0
        } catch {
            Logger.pushNotification.error("Inactivity notification interactionCount read failed with \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    func recordInteraction() {
        let next = interactionCount + 1
        do {
            try keyValueStore.set(next, forKey: StorageKey.interactionCount)
        } catch {
            Logger.pushNotification.error("Inactivity notification recordInteraction write failed with \(error.localizedDescription, privacy: .public)")
        }
    }
}
