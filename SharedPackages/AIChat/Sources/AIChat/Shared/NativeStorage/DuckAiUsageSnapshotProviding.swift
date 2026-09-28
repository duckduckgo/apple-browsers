//
//  DuckAiUsageSnapshotProviding.swift
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

public protocol DuckAiUsageSnapshotProviding {
    /// `.noData` rather than an error when the key is absent, unparseable, or expired.
    func currentSnapshot() -> DuckAiUsageSnapshot
}

public struct DuckAiUsageSnapshotProvider: DuckAiUsageSnapshotProviding {

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

    public func currentSnapshot() -> DuckAiUsageSnapshot {
        let value: Any?
        do {
            value = try storage.getEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue)
        } catch {
            pixelFiring.fire(.settingsGetError(error))
            return .noData
        }
        // A value that fails to decode is an ordinary "nothing to show" state, not an error.
        return DuckAiUsageSnapshot.make(entryValue: value, now: dateProvider())
    }
}
