//
//  WebExtensionRetentionStore.swift
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

@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionRetentionSettings: StoringKeys {
    /// When each Chrome Web Store extension waiting for its retention check was installed, by store ID.
    let installDates = StorageKey<[String: Date]>(WebExtensionStorageKeys.retentionInstallDates)

    public init() {}
}

/// Remembers when store extensions were installed until their 14-day retention check.
///
/// An entry outlives the installation it records, so an extension removed before the check is still
/// judged, as churned. Installing again restarts its wait.
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionRetentionStore {

    /// How long after installation an extension is judged retained or churned.
    public static let retentionPeriod: TimeInterval = 14 * 24 * 60 * 60

    private let storage: any KeyedStoring<WebExtensionRetentionSettings>

    public init(storage: (any KeyedStoring<WebExtensionRetentionSettings>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
    }

    /// Starts, or restarts, the wait for the extension with the Chrome Web Store ID `storeID`.
    public func recordInstallation(of storeID: String, at date: Date) {
        var installDates = storage.installDates ?? [:]
        installDates[storeID] = date
        storage.installDates = installDates
    }

    /// Removes and returns the store IDs installed at least `retentionPeriod` before `date`,
    /// so each installation is judged once.
    public func takeDue(at date: Date) -> [String] {
        let installDates = storage.installDates ?? [:]
        let due = installDates
            .filter { date.timeIntervalSince($0.value) >= Self.retentionPeriod }
            .map(\.key)
            .sorted()
        guard !due.isEmpty else { return [] }

        storage.installDates = installDates.filter { !due.contains($0.key) }
        return due
    }

    /// Moves every pending installation `interval` earlier, so a debug build can reach the check without waiting.
    public func backdateInstallations(by interval: TimeInterval) {
        storage.installDates = storage.installDates?.mapValues { $0 - interval }
    }
}
