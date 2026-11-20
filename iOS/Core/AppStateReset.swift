//
//  AppStateReset.swift
//  DuckDuckGo
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

import FeatureFlags_iOS
import Foundation

/// Deletes saved settings, feature flag overrides, statistics, tabs and app files, so the next launch starts like a fresh install.
/// Used by the `-clearAllDefaults` launch argument.
public struct AppStateReset {

    private let userDefaults: UserDefaults
    private let fileManager = FileManager.default

    public init(userDefaults: UserDefaults = .app) {
        self.userDefaults = userDefaults
    }

    /// Must be called before feature-flag overrides are written.
    public func reset() {
        if let bundleID = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleID)
        }
        let statisticsGroupName = Bundle.main.appGroup(bundle: .statistics)
        UserDefaults(suiteName: statisticsGroupName)?.removePersistentDomain(forName: statisticsGroupName)
        UserDefaults(suiteName: FeatureFlag.localOverrideStoreName)?.removePersistentDomain(forName: FeatureFlag.localOverrideStoreName)
        clearAppSupportFiles()

        // WebKit stops showing its location prompt for a host after repeated denials and keeps that across launches.
        if let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: libraryDir.appendingPathComponent("WebKit/GeolocationSitesV2.plist"))
        }
    }

    private func clearAppSupportFiles() {
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        // PromptCooldownKeyValueFilesStore — must be removed before AppKeyValueFileStoreService
        // opens the file and acquires its lock.
        try? fileManager.removeItem(at: appSupportDir.appendingPathComponent("AppKeyValueStore"))

        // Tab model — KeyValueFileStore files written by TabsModelPersistence.
        // Without these the app restores the previous browsing session on relaunch.
        try? fileManager.removeItem(at: appSupportDir.appendingPathComponent("TabsModel"))
        try? fileManager.removeItem(at: appSupportDir.appendingPathComponent("FireTabsModel"))

        // WebKit per-tab interaction state (scroll position, form data, WKWebView session).
        // Stored under <AppSupport>/<BundleID>/webview-interaction/ by TabInteractionStateDiskSource.
        if let bundleID = Bundle.main.bundleIdentifier {
            try? fileManager.removeItem(at: appSupportDir
                .appendingPathComponent(bundleID)
                .appendingPathComponent("webview-interaction"))
        }
    }
}
