//
//  ExperimentEventTracker.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public typealias ThresholdCheckResult = Bool
public typealias ExprimentPixelNameAndParameters = String
public typealias NumberOfActions = Int

public protocol ExperimentActionPixelStore {
     func removeObject(forKey defaultName: String)
     func integer(forKey defaultName: String) -> Int
     func set(_ value: Int, forKey defaultName: String)
 }

public protocol ExperimentEventTracking {
    /// Increments the count for a given event key and checks if the threshold has been exceeded.
    ///
    /// This method performs the following actions:
    /// 1. If the `isInWindow` parameter is `false`, it removes the stored count for the key and returns `false`.
    /// 2. If `isInWindow` is `true`, it increments the count for the key.
    /// 3. If the updated count meets or exceeds the specified `threshold`, the stored count is removed, and the method returns `true`.
    /// 4. If the updated count does not meet the threshold, it updates the count and returns `false`.
    ///
    /// - Parameters:
    ///   - key: The key used to store and retrieve the count.
    ///   - threshold: The count threshold that triggers a return of `true`.
    ///   - isInWindow: A flag indicating if the count should be considered (e.g., within a time window).
    /// - Returns: `true` if the threshold is exceeded and the count is reset, otherwise `false`.
    func incrementAndCheckThreshold(forKey key: ExprimentPixelNameAndParameters, threshold: NumberOfActions, isInWindow: Bool) -> ThresholdCheckResult
}

public struct ExperimentEventTracker: ExperimentEventTracking {
    private let store: ExperimentActionPixelStore
    private let syncQueue = DispatchQueue(label: "com.pixelkit.experimentActionSyncQueue")

    public init(store: ExperimentActionPixelStore = UserDefaults.standard) {
        self.store = store
    }

    public func incrementAndCheckThreshold(forKey key: ExprimentPixelNameAndParameters, threshold: NumberOfActions, isInWindow: Bool) -> ThresholdCheckResult {
        syncQueue.sync {
            // Remove the key if is not in window
            guard isInWindow else {
                store.removeObject(forKey: key)
                return false
            }

            // Increment the current count
            let currentCount = store.integer(forKey: key)
            let newCount = currentCount + 1
            store.set(newCount, forKey: key)

            // Check if the threshold is exceeded
            if newCount >= threshold {
                store.removeObject(forKey: key)
                return true
            }
            return false
        }
    }

}

extension UserDefaults: ExperimentActionPixelStore {}
