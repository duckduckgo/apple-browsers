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
import os.log
import Persistence

@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionRetentionSettings: StoringKeys {
    let installDates = StorageKey<[String: Date]>(WebExtensionStorageKeys.retentionInstallDates)

    public init() {}
}

/// Install dates outlive an uninstall, so an extension removed before its check is still judged, as churned.
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionRetentionStore {

    public static let retentionPeriod: TimeInterval = 14 * 24 * 60 * 60

    private let storage: any ThrowingKeyedStoring<WebExtensionRetentionSettings>

    public init(storage: any ThrowingKeyedStoring<WebExtensionRetentionSettings>) {
        self.storage = storage
    }

    public func recordInstallation(of storeID: String, at date: Date) {
        do {
            var installDates = try storage.installDates ?? [:]
            installDates[storeID] = date
            try storage.set(installDates, for: \.installDates)
        } catch {
            Logger.webExtensions.error("Could not record extension install date: \(error.localizedDescription)")
        }
    }

    /// Removes the due store IDs as it returns them, so each installation is judged once.
    public func takeDue(at date: Date) -> [String] {
        do {
            let installDates = try storage.installDates ?? [:]
            let due = installDates
                .filter { date.timeIntervalSince($0.value) >= Self.retentionPeriod }
                .map(\.key)
                .sorted()
            guard !due.isEmpty else { return [] }

            try storage.set(installDates.filter { !due.contains($0.key) }, for: \.installDates)
            return due
        } catch {
            Logger.webExtensions.error("Could not update extension install dates: \(error.localizedDescription)")
            return []
        }
    }

    /// Moves every pending installation `interval` earlier, so a debug build can reach the check without waiting.
    public func backdateInstallations(by interval: TimeInterval) {
        do {
            try storage.set(storage.installDates?.mapValues { $0 - interval }, for: \.installDates)
        } catch {
            Logger.webExtensions.error("Could not backdate extension install dates: \(error.localizedDescription)")
        }
    }
}
