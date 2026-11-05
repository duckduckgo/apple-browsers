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
import os.log
import Persistence

/// Reports whether store installs are retained or churned 14 days later, matching Windows.
/// Install dates outlive an uninstall, so removing an extension still reports it as churned.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionRetentionReporter {

    private static let key = "web-extension-retention-install-dates"
    private static let window: TimeInterval = 14 * 24 * 60 * 60
    private static let checkInterval: TimeInterval = 60 * 60

    private let keyValueStore: any ThrowingKeyValueStoring
    private let pixelFiring: WebExtensionPixelFiring
    private let now: () -> Date
    private var lastCheckDate: Date?

    init(keyValueStore: any ThrowingKeyValueStoring, pixelFiring: WebExtensionPixelFiring, now: @escaping () -> Date) {
        self.keyValueStore = keyValueStore
        self.pixelFiring = pixelFiring
        self.now = now
    }

    /// Starts an install's 14-day window. A reinstall restarts it, matching Windows.
    func recordInstall(_ extensionID: String) {
        var installDates = read()
        installDates[extensionID] = now()
        write(installDates)
    }

    /// Reports each install that is 14 days old as retained when it's still installed and enabled, or as churned.
    /// It checks at most once an hour, so a gap in use makes a report late, not lost.
    func reportIfDue(installedExtensions: [InstalledWebExtension], category: (String) -> String?) {
        let date = now()
        if let lastCheckDate, date.timeIntervalSince(lastCheckDate) < Self.checkInterval {
            return
        }
        lastCheckDate = date

        for extensionID in takeDue(at: date) {
            let isEnabled = installedExtensions.contains { $0.storeIdentity?.id == extensionID && !$0.isDisabled }
            let category = category(extensionID)
            pixelFiring.fire(isEnabled ? .retained(extensionID: extensionID, category: category)
                                       : .churned(extensionID: extensionID, category: category))
        }
    }

    /// Removes the due installs as it returns them, so each is judged once.
    private func takeDue(at date: Date) -> [String] {
        var installDates = read()
        let due = installDates.filter { date.timeIntervalSince($0.value) >= Self.window }.keys.sorted()
        guard !due.isEmpty else { return [] }

        for extensionID in due {
            installDates.removeValue(forKey: extensionID)
        }
        write(installDates)
        return due
    }

    private func read() -> [String: Date] {
        do {
            guard let data = try keyValueStore.object(forKey: Self.key) as? Data else { return [:] }
            return try JSONDecoder().decode([String: Date].self, from: data)
        } catch {
            Logger.webExtensions.error("Could not read extension install dates: \(error.localizedDescription)")
            return [:]
        }
    }

    private func write(_ installDates: [String: Date]) {
        do {
            if installDates.isEmpty {
                try keyValueStore.removeObject(forKey: Self.key)
            } else {
                try keyValueStore.set(JSONEncoder().encode(installDates), forKey: Self.key)
            }
        } catch {
            Logger.webExtensions.error("Could not save extension install dates: \(error.localizedDescription)")
        }
    }
}
