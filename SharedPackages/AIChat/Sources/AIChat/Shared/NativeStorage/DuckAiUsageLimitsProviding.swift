//
//  DuckAiUsageLimitsProviding.swift
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

/// Reads the Duck.ai usage-limit snapshot the web app writes into native storage.
public protocol DuckAiUsageLimitsProviding {
    /// Returns the last snapshot the Duck.ai web app wrote, with already-reset windows dropped.
    ///
    /// Returns `.noData` — never an error — when the key is absent, the value doesn't parse, or every window has
    /// expired. Reads are cheap and intended to be made on demand; there is no subscription or polling to set up.
    func currentUsageLimits() -> DuckAiUsageLimits
}

public struct DuckAiUsageLimitsProvider: DuckAiUsageLimitsProviding {

    private let storage: DuckAiNativeStorageHandling
    private let pixelFiring: DuckAiNativeStoragePixelFiring
    private let dateProvider: () -> Date

    public init(
        storage: DuckAiNativeStorageHandling,
        pixelFiring: DuckAiNativeStoragePixelFiring = NullDuckAiNativeStoragePixelFiring(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.pixelFiring = pixelFiring
        self.dateProvider = dateProvider
    }

    public func currentUsageLimits() -> DuckAiUsageLimits {
        let value: Any?
        do {
            value = try storage.getEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue)
        } catch {
            pixelFiring.fire(.settingsGetError(error))
            return .noData
        }
        // A value that fails to decode is not reported: per the storage contract it's an ordinary
        // "nothing to show" state, indistinguishable to the user from an absent key.
        return DuckAiUsageLimits.make(entryValue: value, now: dateProvider())
    }
}
