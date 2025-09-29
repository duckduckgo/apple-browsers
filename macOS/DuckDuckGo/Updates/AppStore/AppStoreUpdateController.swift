//
//  AppStoreUpdateController.swift
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

#if APPSTORE

import Foundation
import Combine
import os.log
import Common
import AppKit
import BrowserServicesKit
import FeatureFlags

final class AppStoreUpdateController: NSObject, UpdateController {
    @Published private(set) var latestUpdate: Update?
    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published private(set) var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    @Published var needsNotificationDot: Bool = false
    private let notificationDotSubject = CurrentValueSubject<Bool, Never>(false)
    lazy var notificationDotPublisher = notificationDotSubject.eraseToAnyPublisher()

    lazy var notificationPresenter = UpdateNotificationPresenter()

    var lastUpdateCheckDate: Date?
    var lastUpdateNotificationShownDate: Date = .distantPast

    /// Automatic updates for App Store users cannot be enabled from the browser.
    var areAutomaticUpdatesEnabled: Bool = false

    @Published private(set) var updateProgress = UpdateCycleProgress.default
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    // MARK: - Dependencies

    private let updateCheckState: UpdateCheckState
    private let updaterChecker: AppStoreUpdaterAvailabilityChecker
    private let releaseChecker: LatestReleaseChecker
    private let featureFlagger: FeatureFlagger
    private let internalUserDecider: InternalUserDecider
    private let appStoreOpener: AppStoreOpener

    // MARK: - Initialization

    init(updateCheckState: UpdateCheckState = UpdateCheckState(),
         releaseChecker: LatestReleaseChecker = LatestReleaseChecker(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         internalUserDecider: InternalUserDecider = NSApp.delegateTyped.internalUserDecider,
         appStoreOpener: AppStoreOpener = DefaultAppStoreOpener()) {
        self.updateCheckState = updateCheckState
        self.updaterChecker = AppStoreUpdaterAvailabilityChecker()
        self.releaseChecker = releaseChecker
        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
        self.appStoreOpener = appStoreOpener
        super.init()

        // Only setup cloud checking if feature flag is on
        if featureFlagger.isFeatureOn(.appStoreCheckForUpdatesFlow) {
            // Observe needsNotificationDot changes
            $needsNotificationDot
                .sink { [weak self] value in
                    self?.notificationDotSubject.send(value)
                }
                .store(in: &cancellables)

            // Start automatic update checking
            checkForUpdateAutomatically()
            subscribeToWindowResignKeyNotifications()
        }
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Automatic Check for Updates Subscriptions

    private func subscribeToWindowResignKeyNotifications() {
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] _ in
                self?.checkForUpdateAutomatically()
            }
            .store(in: &cancellables)
    }

    // MARK: - Update Check Methods

    /// Checks for updates respecting automatic update settings and rate limiting
    func checkForUpdateAutomatically() {
        // Only do automatic checks if feature flag is on
        guard featureFlagger.isFeatureOn(.appStoreCheckForUpdatesFlow) else {
            return // Legacy mode: no automatic checks
        }

        Task { @UpdateCheckActor in
            await performUpdateCheck()
        }
    }

    /// User-initiated update check (bypasses automatic update settings and rate limiting)
    func checkForUpdateSkippingRollout() {
        if featureFlagger.isFeatureOn(.appStoreCheckForUpdatesFlow) {
            // New flow - check cloud for updates
            Task { @UpdateCheckActor in
                // User-initiated checks skip rate limiting but still log the attempt
                guard await updateCheckState.canStartNewCheck(updater: updaterChecker, minimumInterval: 0) else {
                    Logger.updates.debug("User-initiated App Store update check skipped - updater not available")
                    return
                }

                Logger.updates.debug("User-initiated App Store update check starting")
                await performUpdateCheck(dismissRateLimiting: true)
            }
        } else {
            // Legacy flow - direct to App Store (no cloud checking)
            openUpdatesPage()
        }
    }

    /// For App Store builds given that we cannot run an update. We just check for a new by going to the App Store.
    func runUpdate() {
        openUpdatesPage()
    }

    // MARK: - Private Update Logic

    @UpdateCheckActor
    private func performUpdateCheck(dismissRateLimiting: Bool = false) async {
        // Check if we can start a new check (rate limiting for automatic checks)
        if !dismissRateLimiting {
            guard await updateCheckState.canStartNewCheck(updater: updaterChecker) else {
                Logger.updates.debug("App Store update check skipped - rate limited")
                return
            }
        }

        do {
            updateProgress = .updateCycleDidStart
            let releaseMetadata = try await releaseChecker.getLatestReleaseAvailable(for: .macOSAppStore)
            let currentVersion = getCurrentAppVersion()
            let currentBuild = getCurrentAppBuild()

            Logger.updates.log("Checking App Store update: current=\(currentVersion ?? "unknown"), remote=\(releaseMetadata.latestVersion)")

            let isUpdateAvailable = await isUpdateAvailable(
                currentVersion: currentVersion,
                currentBuild: currentBuild,
                remoteVersion: releaseMetadata.latestVersion,
                remoteBuild: String(releaseMetadata.buildNumber)
            )

            await MainActor.run {
                self.lastUpdateCheckDate = Date()

                if isUpdateAvailable {
                    let update = Update(releaseMetadata: releaseMetadata, isInstalled: false)
                    self.latestUpdate = update
                    self.hasPendingUpdate = true
                    self.needsNotificationDot = true

                    Logger.updates.log("App Store update available: \(releaseMetadata.latestVersion)")
                    updateProgress = .updateCycleDone(.finishedWithNoError)
                } else {
                    self.hasPendingUpdate = false
                    self.needsNotificationDot = false

                    Logger.updates.log("App Store: no update available")
                    updateProgress = .updateCycleDone(.finishedWithNoUpdateFound)
                }
            }

            showUpdateNotificationIfNeeded()

            // Record check time for rate limiting
            await updateCheckState.recordCheckTime()

        } catch {
            /// If we fail to fetch the latest version we do not want to show any messages to the user.
            updateProgress = .updateCycleDone(.finishedWithNoUpdateFound)
            Logger.updates.error("Failed to check for App Store updates: \(error.localizedDescription)")

            await MainActor.run {
                self.lastUpdateCheckDate = Date()
            }
        }
    }

    @objc func openUpdatesPage() {
        appStoreOpener.openAppStore()
    }

    // MARK: - Private Methods

    private func getCurrentAppVersion() -> String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func getCurrentAppBuild() -> String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    internal func isUpdateAvailable(currentVersion: String?,
                                    currentBuild: String?,
                                    remoteVersion: String,
                                    remoteBuild: String) async -> Bool {

        // Internal user debug override for testing
        let debugSettings = UpdatesDebugSettings()
        if debugSettings.forceUpdateAvailable && internalUserDecider.isInternalUser {
            Logger.updates.debug("🧪 INTERNAL DEBUG: Forcing update available = true")
            return true
        }

        guard let currentVersion = currentVersion else { return true }

        // Use semantic version comparison
        let result = compareSemanticVersions(currentVersion, remoteVersion)

        if result == .orderedAscending {
            // Current version is older than remote
            return true
        } else if result == .orderedSame {
            // Same version, check build numbers
            if let currentBuild = currentBuild {
                let buildResult = compareSemanticVersions(currentBuild, remoteBuild)
                return buildResult == .orderedAscending
            }
            return false
        } else {
            // Current version is newer than remote
            return false
        }
    }

    internal func compareSemanticVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }

        let maxComponents = max(v1Components.count, v2Components.count)

        for i in 0..<maxComponents {
            let v1Component = i < v1Components.count ? v1Components[i] : 0
            let v2Component = i < v2Components.count ? v2Components[i] : 0

            if v1Component < v2Component {
                return .orderedAscending
            } else if v1Component > v2Component {
                return .orderedDescending
            }
        }

        return .orderedSame
    }
}

#endif
