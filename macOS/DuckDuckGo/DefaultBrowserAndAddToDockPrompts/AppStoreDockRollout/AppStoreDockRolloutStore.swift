//
//  AppStoreDockRolloutStore.swift
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
import PixelKit

struct AppStoreDockRolloutPendingCheck: Codable, Equatable {
    let arm: AppStoreDockRolloutPixel.Arm
    /// When the prompt that started the check was shown.
    let shownDate: Date
}

protocol AppStoreDockRolloutStoring: AnyObject {
    /// The Dock check to run after a prompt was shown, or `nil` when no check is pending.
    var pendingCheck: AppStoreDockRolloutPendingCheck? { get set }
    /// The arm and ID of the last prompt counted as shown, so a prompt shown again counts once.
    var lastShownPromptID: String? { get set }
}

final class AppStoreDockRolloutStore: AppStoreDockRolloutStoring {

    enum Key {
        static let pendingCheck = "app-store-dock-rollout.pending-check"
        static let lastShownPromptID = "app-store-dock-rollout.last-shown-prompt-id"
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let pixelFiring: PixelFiring?

    init(keyValueStore: ThrowingKeyValueStoring, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.keyValueStore = keyValueStore
        self.pixelFiring = pixelFiring
    }

    var pendingCheck: AppStoreDockRolloutPendingCheck? {
        get {
            read(Key.pendingCheck) { (data: Data) in
                try JSONDecoder().decode(AppStoreDockRolloutPendingCheck.self, from: data)
            }
        }
        set {
            write(Key.pendingCheck) {
                try newValue.map { try JSONEncoder().encode($0) }
            }
        }
    }

    var lastShownPromptID: String? {
        get { read(Key.lastShownPromptID) { (promptID: String) in promptID } }
        set { write(Key.lastShownPromptID) { newValue } }
    }

    private func read<Stored, Value>(_ key: String, decode: (Stored) throws -> Value) -> Value? {
        do {
            guard let stored = try keyValueStore.object(forKey: key) else { return nil }
            guard let value = stored as? Stored else { throw CocoaError(.coderReadCorrupt) }
            return try decode(value)
        } catch {
            pixelFiring?.fire(AppStoreDockRolloutDebugPixel.storeReadFailed(error: error), frequency: .dailyAndCount)
            try? keyValueStore.removeObject(forKey: key)
            return nil
        }
    }

    private func write(_ key: String, encode: () throws -> Any?) {
        do {
            if let value = try encode() {
                try keyValueStore.set(value, forKey: key)
            } else {
                try keyValueStore.removeObject(forKey: key)
            }
        } catch {
            pixelFiring?.fire(AppStoreDockRolloutDebugPixel.storeWriteFailed(error: error), frequency: .dailyAndCount)
        }
    }
}
