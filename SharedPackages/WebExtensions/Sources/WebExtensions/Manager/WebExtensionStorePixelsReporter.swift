//
//  WebExtensionStorePixelsReporter.swift
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

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionStorePixelsReporter {

    private static let checkInterval: TimeInterval = 60 * 60

    private let store: WebExtensionRetentionStore
    private let installationStore: InstalledWebExtensionStoring
    private let pixelFiring: WebExtensionPixelFiring
    private let now: () -> Date
    private var lastCheckDate: Date?

    init(store: WebExtensionRetentionStore, installationStore: InstalledWebExtensionStoring, pixelFiring: WebExtensionPixelFiring, now: @escaping () -> Date) {
        self.store = store
        self.installationStore = installationStore
        self.pixelFiring = pixelFiring
        self.now = now
    }

    /// Starts an install's 14-day window. A reinstall restarts it, matching Windows.
    func recordInstall(_ extensionID: String) {
        store.recordInstallation(of: extensionID, at: now())
    }

    /// Moves pending installs `interval` earlier and lets the next browsing activity check right away, for debugging.
    func backdateInstalls(by interval: TimeInterval) {
        store.backdateInstallations(by: interval)
        lastCheckDate = nil
    }

    /// Skips while the catalog is empty, so the count's denominator is devices that can install store extensions.
    func reportIfDue(chromeWebStore: ChromeWebStoreManaging?) {
        guard shouldReportChurnAndRetained() else {
            return
        }

        let date = markRetainedWasReported()

        // Checked after the hourly check, since it evaluates the whole catalog configuration.
        guard let chromeWebStore, !chromeWebStore.catalogExtensionIDs.isEmpty else {
            return
        }

        // Old and new versions coexist during an update, so each store ID counts once.
        var isEnabledByStoreID: [String: Bool] = [:]
        for installedExtension in installationStore.installedExtensions {
            guard let storeID = installedExtension.storeIdentity?.id else {
                continue
            }

            isEnabledByStoreID[storeID] = (isEnabledByStoreID[storeID] ?? false) || !installedExtension.isDisabled
        }

        pixelFiring.fire(.installedCount(installed: isEnabledByStoreID.count, enabled: isEnabledByStoreID.values.filter { $0 }.count))

        for storeID in store.takeDue(at: date) {
            let reported: WebExtensionPixelExtension = chromeWebStore.catalogEntry(of: storeID)
                .map {
                    .catalog($0)
                } ?? .other

            let enabled = isEnabledByStoreID[storeID] == true

            pixelFiring.fire(enabled ? .retained14Days(extension: reported) : .churned14Days(extension: reported))
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension WebExtensionStorePixelsReporter {

    func shouldReportChurnAndRetained() -> Bool {
        let date = now()
        guard let lastCheckDate, date.timeIntervalSince(lastCheckDate) < Self.checkInterval else {
            return true
        }

        return false
    }

    func markRetainedWasReported() -> Date {
        let output = now()
        lastCheckDate = output
        return output
    }
}
