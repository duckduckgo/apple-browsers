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

import Foundation
import Persistence
import PixelKit

final class DefaultBrowserConfirmationStore: DefaultBrowserConfirmationStoring {

    private let source: DefaultBrowserConfirmationSource
    private let pendingConfirmationKey: String
    private let keyValueStore: ThrowingKeyValueStoring
    private let pixelFiring: PixelFiring?

    init(source: DefaultBrowserConfirmationSource, keyValueStore: ThrowingKeyValueStoring, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.source = source
        self.pendingConfirmationKey = "\(source.rawValue).pending-confirmation"
        self.keyValueStore = keyValueStore
        self.pixelFiring = pixelFiring
    }

    var pendingConfirmation: DefaultBrowserPendingConfirmation? {
        get {
            do {
                guard let stored = try keyValueStore.object(forKey: pendingConfirmationKey) else { return nil }
                guard let data = stored as? Data else { throw CocoaError(.coderReadCorrupt) }
                return try JSONDecoder().decode(DefaultBrowserPendingConfirmation.self, from: data)
            } catch {
                pixelFiring?.fire(DefaultBrowserConfirmationDebugPixel.pendingConfirmationReadFailed(source: source, error: error),
                                  frequency: .dailyAndCount)
                try? keyValueStore.removeObject(forKey: pendingConfirmationKey)
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
                pixelFiring?.fire(DefaultBrowserConfirmationDebugPixel.pendingConfirmationWriteFailed(source: source, error: error),
                                  frequency: .dailyAndCount)
            }
        }
    }
}
