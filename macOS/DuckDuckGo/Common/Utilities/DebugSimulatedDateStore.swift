//
//  DebugSimulatedDateStore.swift
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

/// Shared debug store for simulated "today's date" used by PromoService and DefaultBrowserAndDockPromptService.
/// Both debug menus write to this store; advancing or resetting the date in either menu affects both systems.
final class DebugSimulatedDateStore {

    enum Key: String {
        case simulatedDate = "debug.shared.simulated-date"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var simulatedDate: Date? {
        get {
            guard let timestamp = try? keyValueStore.object(forKey: Key.simulatedDate.rawValue) as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let newValue {
                try? keyValueStore.set(newValue.timeIntervalSince1970, forKey: Key.simulatedDate.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.simulatedDate.rawValue)
            }
        }
    }

    func advance(by interval: TimeInterval) {
        simulatedDate = (simulatedDate ?? Date()).addingTimeInterval(interval)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Key.simulatedDate.rawValue)
    }
}
