//
//  DefaultBrowserConfirmationStore.swift
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

import Common
import Foundation
import os.log
import Persistence

final class DefaultBrowserConfirmationStore: DefaultBrowserConfirmationStoring {

    private let pendingConfirmationKey: String
    private let keyValueStore: ThrowingKeyValueStoring

    init(source: DefaultBrowserConfirmationSource, keyValueStore: ThrowingKeyValueStoring) {
        self.pendingConfirmationKey = "\(source.rawValue).pending-confirmation"
        self.keyValueStore = keyValueStore
    }

    var pendingConfirmation: DefaultBrowserPendingConfirmation? {
        get {
            do {
                guard let stored = try keyValueStore.object(forKey: pendingConfirmationKey) else { return nil }
                guard let data = stored as? Data else { throw CocoaError(.coderReadCorrupt) }
                return try JSONDecoder().decode(DefaultBrowserPendingConfirmation.self, from: data)
            } catch {
                Logger.general.error("Failed to read \(self.pendingConfirmationKey): \(error)")
                return nil
            }
        }
        set {
            do {
                if let newValue {
                    try keyValueStore.set(try JSONEncoder().encode(newValue), forKey: pendingConfirmationKey)
                } else {
                    try keyValueStore.removeObject(forKey: pendingConfirmationKey)
                }
            } catch {
                Logger.general.error("Failed to write \(self.pendingConfirmationKey): \(error)")
            }
        }
    }
}
