//
//  ReinstallingUserDetecting.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

// MARK: - Protocols

/// Detects whether the current app launch is from a user who previously had the app installed.
///
/// **Note: This feature is only available for Sparkle builds.** App Store builds cannot reliably
/// detect reinstalls because there's no way to distinguish App Store updates from reinstalls.
///
/// Uses bundle creation date comparison to detect reinstalls (Sparkle builds only).
///
/// Detection logic:
/// 1. Store the app bundle's creation date in the ThrowingKeyValueStore  on first launch
/// 2. On subsequent launches, compare current bundle's creation date with stored date
/// 3. If dates differ → new bundle installed (check if Sparkle update or reinstall)
/// 4. If dates match → same bundle, existing user
///
/// Call `checkForReinstallingUser()` once early in app launch (before the SparkleUpdater gets initialized),
/// then access `isReinstallingUser` anywhere in the app to get the stored result.
protocol ReinstallingUserDetecting {

    /// Returns `true` if a reinstall was detected.
    ///
    /// This returns the stored result from `checkForReinstallingUser()`.
    /// Returns `false` if the check has not been performed yet or if running on App Store build.
    var isReinstallingUser: Bool { get }

    /// Performs the reinstall detection check and stores the result.
    ///
    /// This should be called once early in app launch, before any code writes to the App Group Container.
    /// The result is stored in UserDefaults and can be accessed via `isReinstallingUser`.
    ///
    /// On App Store builds, this is a no-op since reinstall detection is not supported.
    func checkForReinstallingUser() throws
}

/// Provides the URL of the application bundle.
protocol BundleURLProviding {
    var bundleURL: URL { get }
}

extension Bundle: BundleURLProviding {}

// MARK: - Implementation

/// Default implementation that uses bundle creation date comparison for reinstall detection.
final class DefaultReinstallUserDetection: ReinstallingUserDetecting {

    private enum Keys {
        /// Bundle creation date stored in App Group UserDefaults
        static let storedBundleCreationDate = "reinstall.detection.bundle-creation-date"
        /// The result of the reinstall check
        static let isReinstallingUser = "reinstall.detection.is-reinstalling-user"
    }

    private let buildType: ApplicationBuildType
    private let fileManager: FileManager
    private let bundleURLProvider: BundleURLProviding
    private let keyValueStore: ThrowingKeyValueStoring
    private let standardDefaults: UserDefaults

    init(
        buildType: ApplicationBuildType = StandardApplicationBuildType(),
        fileManager: FileManager = .default,
        bundleURLProvider: BundleURLProviding = Bundle.main,
        keyValueStore: ThrowingKeyValueStoring,
        standardDefaults: UserDefaults = .standard
    ) {
        self.buildType = buildType
        self.fileManager = fileManager
        self.bundleURLProvider = bundleURLProvider
        self.keyValueStore = keyValueStore
        self.standardDefaults = standardDefaults
    }

    var isReinstallingUser: Bool {
        guard buildType.isSparkleBuild else {
            // Reinstall detection is not supported for App Store builds
            return false
        }

        do {
            let storedValue = try keyValueStore.object(forKey: Keys.isReinstallingUser) as? Bool
            guard let storedValue else { return false }

            return storedValue
        } catch {
            return false
        }
    }

    func checkForReinstallingUser() throws {
        guard buildType.isSparkleBuild else {
            // App Store builds: No-op - reinstall detection is not supported
            return
        }

        guard let currentBundleCreationDate = getBundleCreationDate() else {
            // Can't read bundle metadata - skip detection
            return
        }

        let storedCreationDate = try keyValueStore.object(forKey: Keys.storedBundleCreationDate) as? Date

        // Case 1: No stored date → First launch ever (or first launch with this feature)
        guard let storedCreationDate = storedCreationDate else {
            // Store current bundle's creation date for future comparisons
            try keyValueStore.set(currentBundleCreationDate, forKey: Keys.storedBundleCreationDate)
            return
        }

        // Case 2: Dates match → Same bundle, existing user
        if areDatesEqual(storedCreationDate, currentBundleCreationDate) {
            return
        }

        // Case 3: Dates differ → New bundle installed
        // Determine if this was a Sparkle update or a reinstall
        if wasSparkleUpdate() {
            // Sparkle update - not a reinstall
            // Update stored date to current bundle
            try keyValueStore.set(currentBundleCreationDate, forKey: Keys.storedBundleCreationDate)
            return
        }

        // Not a Sparkle update → Reinstall detected (or manual update, which we treat as reinstall)
        try keyValueStore.set(true, forKey: Keys.isReinstallingUser)
        try keyValueStore.set(currentBundleCreationDate, forKey: Keys.storedBundleCreationDate)
    }

    // MARK: - Bundle Metadata

    /// Gets the creation date of the app bundle.
    private func getBundleCreationDate() -> Date? {
        let bundleURL = bundleURLProvider.bundleURL

        do {
            let attributes = try fileManager.attributesOfItem(atPath: bundleURL.path)
            return attributes[.creationDate] as? Date
        } catch {
            return nil
        }
    }

    /// Compares two dates with a small tolerance (1 second) to handle filesystem precision.
    private func areDatesEqual(_ date1: Date, _ date2: Date) -> Bool {
        abs(date1.timeIntervalSince(date2)) < 1.0
    }

    // MARK: - Sparkle Update Detection

    /// Checks if Sparkle initiated an update (by looking for pending update metadata).
    ///
    /// Sparkle stores metadata in UserDefaults before restarting for an update.
    /// If this metadata exists, Sparkle initiated the update.
    private func wasSparkleUpdate() -> Bool {
        // Check if Sparkle stored pending update metadata
        let settings = standardDefaults.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        return (try? settings.pendingUpdateSourceVersion) != nil
    }
}
