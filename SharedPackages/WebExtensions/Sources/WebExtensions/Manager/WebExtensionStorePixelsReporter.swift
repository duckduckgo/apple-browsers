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

/// Reports how many store extensions are installed and enabled, and whether store installs are retained or
/// churned 14 days later. Install dates outlive an uninstall, so removing an extension still reports it as churned.
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

    /// Reports how many store extensions are installed and enabled, then each install that is 14 days old as retained
    /// when it's still installed and enabled, or as churned. It checks at most once an hour, so a gap in use makes a
    /// report late, not lost. The count pixel is daily, so each device reports it once a day. Nothing is reported while
    /// the catalog offers no extensions, so the count's denominator is devices that can install store extensions.
    func reportIfDue(chromeWebStore: ChromeWebStoreManaging?) {
        let date = now()
        if let lastCheckDate, date.timeIntervalSince(lastCheckDate) < Self.checkInterval {
            return
        }
        lastCheckDate = date
        // Checked after the hourly check, since it evaluates the whole catalog configuration.
        guard let chromeWebStore, !chromeWebStore.catalogExtensionIDs.isEmpty else { return }

        // Old and new versions coexist during an update, so each store ID counts once.
        var isEnabledByStoreID: [String: Bool] = [:]
        for installedExtension in installationStore.installedExtensions {
            guard let storeID = installedExtension.storeIdentity?.id else { continue }
            isEnabledByStoreID[storeID] = (isEnabledByStoreID[storeID] ?? false) || !installedExtension.isDisabled
        }
        pixelFiring.fire(.installedCount(installed: isEnabledByStoreID.count, enabled: isEnabledByStoreID.values.filter { $0 }.count))

        for storeID in store.takeDue(at: date) {
            let reported: WebExtensionPixelExtension = chromeWebStore.catalogEntry(of: storeID).map { .catalog($0) } ?? .other
            pixelFiring.fire(isEnabledByStoreID[storeID] == true ? .retained14Days(extension: reported) : .churned14Days(extension: reported))
        }
    }
}
