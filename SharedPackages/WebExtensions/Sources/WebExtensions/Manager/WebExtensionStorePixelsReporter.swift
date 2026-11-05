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
    private let pixelFiring: WebExtensionPixelFiring
    private let now: () -> Date
    private var lastCheckDate: Date?

    init(store: WebExtensionRetentionStore, pixelFiring: WebExtensionPixelFiring, now: @escaping () -> Date) {
        self.store = store
        self.pixelFiring = pixelFiring
        self.now = now
    }

    /// Starts an install's 14-day window. A reinstall restarts it, matching Windows.
    func recordInstall(_ extensionID: String) {
        store.recordInstallation(of: extensionID, at: now())
    }

    /// Reports how many store extensions are installed and enabled, then each install that is 14 days old as retained
    /// when it's still installed and enabled, or as churned. It checks at most once an hour, so a gap in use makes a
    /// report late, not lost. The count pixel is daily, so each device reports it once a day.
    func reportIfDue(installedExtensions: [InstalledWebExtension], pixelExtension: (String) -> WebExtensionPixelExtension) {
        let date = now()
        if let lastCheckDate, date.timeIntervalSince(lastCheckDate) < Self.checkInterval {
            return
        }
        lastCheckDate = date

        // Old and new versions coexist during an update, so each store ID counts once.
        var isEnabledByStoreID: [String: Bool] = [:]
        for installedExtension in installedExtensions {
            guard let storeID = installedExtension.storeIdentity?.id else { continue }
            isEnabledByStoreID[storeID] = (isEnabledByStoreID[storeID] ?? false) || !installedExtension.isDisabled
        }
        pixelFiring.fire(.installedCount(installed: isEnabledByStoreID.count, enabled: isEnabledByStoreID.values.filter { $0 }.count))

        for storeID in store.takeDue(at: date) {
            let reported = pixelExtension(storeID)
            pixelFiring.fire(isEnabledByStoreID[storeID] == true ? .retained14Days(extension: reported) : .churned14Days(extension: reported))
        }
    }
}
