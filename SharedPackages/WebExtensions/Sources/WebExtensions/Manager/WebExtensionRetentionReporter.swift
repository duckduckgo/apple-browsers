//
//  WebExtensionRetentionReporter.swift
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

/// Reports whether store installs are retained or churned 14 days later, matching Windows.
/// Install dates outlive an uninstall, so removing an extension still reports it as churned.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionRetentionReporter {

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

    /// Reports each install that is 14 days old as retained when it's still installed and enabled, or as churned.
    /// It checks at most once an hour, so a gap in use makes a report late, not lost.
    func reportIfDue(installedExtensions: [InstalledWebExtension], category: (String) -> String?) {
        let date = now()
        if let lastCheckDate, date.timeIntervalSince(lastCheckDate) < Self.checkInterval {
            return
        }
        lastCheckDate = date

        for extensionID in store.takeDue(at: date) {
            // Old and new versions coexist during an update, so any enabled copy counts.
            let isEnabled = installedExtensions.contains { $0.storeIdentity?.id == extensionID && !$0.isDisabled }
            let category = category(extensionID)
            pixelFiring.fire(isEnabled ? .retained(extensionID: extensionID, category: category)
                                       : .churned(extensionID: extensionID, category: category))
        }
    }
}
