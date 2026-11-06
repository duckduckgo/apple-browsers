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

import AppKit
import AppUpdaterShared
import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import Foundation
import os.log
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

/// Factory extension that provides the App Store updater implementation.
///
/// This extension is compiled into the AppStoreAppUpdater package and provides
/// the App Store-specific update controller instantiation.
///
/// See `UpdateControllerFactory` in `UpdateController.swift` for details on
/// how `instantiate` is consumed.
extension UpdateControllerFactory: AppStoreUpdateControllerFactory {
    /// Instantiates the App Store update controller.
    @MainActor
    public static func instantiate(internalUserDecider: InternalUserDecider,
                                   featureFlagger: FeatureFlagger,
                                   privacyConfigurationManager: PrivacyConfigurationManaging,
                                   pixelFiring: PixelFiring?,
                                   notificationPresenter: any UpdateNotificationPresenting,
                                   keyValueStore: any ThrowingKeyValueStoring,
                                   isOnboardingFinished: @escaping () -> Bool) -> any UpdateController {
        AppStoreUpdateController(internalUserDecider: internalUserDecider,
                                 featureFlagger: featureFlagger,
                                 privacyConfigurationManager: privacyConfigurationManager,
                                 pixelFiring: pixelFiring,
                                 notificationPresenter: notificationPresenter,
                                 keyValueStore: keyValueStore,
                                 isOnboardingFinished: isOnboardingFinished)
    }
}

@objc public final class AppStoreUpdateController: NSObject, UpdateController {
    @Published public private(set) var latestUpdate: Update?
    public var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published public private(set) var hasPendingUpdate = false
    public var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    public var mustShowUpdateIndicators: Bool { hasPendingUpdate }
    public var clearsNotificationDotOnMenuOpen: Bool { !isMoreProminentUpdatesOn }

    @Published public var needsNotificationDot: Bool = false
    private let notificationDotSubject = CurrentValueSubject<Bool, Never>(false)
    public lazy var notificationDotPublisher = notificationDotSubject.eraseToAnyPublisher()

    public let notificationPresenter: UpdateNotificationPresenting

    public var lastUpdateCheckDate: Date?

    /// Automatic updates for App Store users cannot be enabled from the browser.
    public var areAutomaticUpdatesEnabled: Bool = false

    @Published public private(set) var updateProgress = UpdateCycleProgress.default
    public var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    public let updatePromptStageTracker: UpdatePromptStageTracker?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    private let updateCheckState: UpdateCheckState
    private let updaterChecker: AppStoreUpdaterAvailabilityChecker
    private let releaseChecker: LatestReleaseChecker
    private let pixelFiring: PixelFiring?
    private let internalUserDecider: InternalUserDecider
    private let featureFlagger: FeatureFlagger
    private let promptSettings: () -> MoreProminentUpdatesSettings
    private let appStoreOpener: AppStoreOpener?
    private let isOnboardingFinished: () -> Bool
    private let appVersion: AppVersion
    private let now: () -> Date

    private var isMoreProminentUpdatesOn: Bool {
        featureFlagger.isFeatureOn(.moreProminentUpdates)
    }

    // MARK: - Initialization

    /// Protocol-conforming initializer for production use.
    @MainActor
    public convenience init(internalUserDecider: InternalUserDecider,
                            featureFlagger: FeatureFlagger,
                            privacyConfigurationManager: PrivacyConfigurationManaging,
                            pixelFiring: PixelFiring?,
                            notificationPresenter: any UpdateNotificationPresenting,
                            keyValueStore: any ThrowingKeyValueStoring,
                            isOnboardingFinished: @escaping () -> Bool) {
        let promptSettings = {
            MoreProminentUpdatesSettings(privacyConfig: privacyConfigurationManager.privacyConfig,
                                         isInternalUser: internalUserDecider.isInternalUser)
        }
        let reevaluationTriggers = UpdatePromptStageTracker.didBecomeActive
            .merge(with: internalUserDecider.isInternalUserPublisher.map { _ in }, featureFlagger.updatesPublisher)
            .eraseToAnyPublisher()
        let tracker = UpdatePromptStageTracker(
            store: keyValueStore.throwingKeyedStoring(),
            settings: promptSettings,
            installedVersion: AppVersion().versionAndBuildNumber,
            forcedStage: { internalUserDecider.isInternalUser ? UpdatesDebugSettings().forcedUpdatePromptStage : nil },
            reevaluationTriggers: reevaluationTriggers
        )

        self.init(appStoreOpener: DefaultAppStoreOpener(),
                  internalUserDecider: internalUserDecider,
                  featureFlagger: featureFlagger,
                  promptSettings: promptSettings,
                  updatePromptStageTracker: tracker,
                  pixelFiring: pixelFiring,
                  notificationPresenter: notificationPresenter,
                  isOnboardingFinished: isOnboardingFinished)

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

    /// Internal initializer for testing with minimal dependencies. Doesn't start automatic update checks.
    init(appStoreOpener: AppStoreOpener? = nil,
         internalUserDecider: InternalUserDecider? = nil,
         featureFlagger: FeatureFlagger = MockFeatureFlagger(),
         promptSettings: @escaping () -> MoreProminentUpdatesSettings = { MoreProminentUpdatesSettings(.external) },
         updatePromptStageTracker: UpdatePromptStageTracker? = nil,
         releaseChecker: LatestReleaseChecker = LatestReleaseChecker(),
         pixelFiring: PixelFiring? = nil,
         notificationPresenter: any UpdateNotificationPresenting,
         isOnboardingFinished: @escaping () -> Bool = { true },
         appVersion: AppVersion = AppVersion(),
         now: @escaping () -> Date = Date.init) {
        self.updateCheckState = UpdateCheckState()
        self.updaterChecker = AppStoreUpdaterAvailabilityChecker()
        self.notificationPresenter = notificationPresenter
        self.releaseChecker = releaseChecker
        self.pixelFiring = pixelFiring
        self.internalUserDecider = internalUserDecider ?? MockInternalUserDecider(isInternalUser: false)
        self.featureFlagger = featureFlagger
        self.promptSettings = promptSettings
        self.updatePromptStageTracker = updatePromptStageTracker
        self.appStoreOpener = appStoreOpener
        self.isOnboardingFinished = isOnboardingFinished
        self.appVersion = appVersion
        self.now = now
        super.init()
    }

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
        Task { @UpdateCheckActor in
            await performUpdateCheck()
        }
    }

    /// User-initiated update check (bypasses automatic update settings and rate limiting)
    public func checkForUpdateSkippingRollout() {
        Task { @UpdateCheckActor in
            // User-initiated checks skip rate limiting but still log the attempt
            guard await updateCheckState.canStartNewCheck(updater: updaterChecker, latestUpdate: latestUpdate, minimumInterval: 0) else {
                Logger.updates.debug("User-initiated App Store update check skipped - updater not available")
                return
            }

            Logger.updates.debug("User-initiated App Store update check starting")
            await performUpdateCheck(dismissRateLimiting: true)
        }
    }

    /// For App Store builds given that we cannot run an update. We just check for a new by going to the App Store.
    public func runUpdate() {
        openUpdatesPage()
    }

    // MARK: - Private Update Logic

    @UpdateCheckActor
    func performUpdateCheck(dismissRateLimiting: Bool = false) async {
        // Check if we can start a new check (rate limiting for automatic checks)
        if !dismissRateLimiting {
            guard await updateCheckState.canStartNewCheck(updater: updaterChecker, latestUpdate: latestUpdate) else {
                Logger.updates.debug("App Store update check skipped - rate limited")
                return
            }
        }

        do {
            updateProgress = .updateCycleDidStart
            let releases = try await releaseChecker.getAppStoreReleases()
            let isMoreProminentUpdatesOn = isMoreProminentUpdatesOn
            let currentVersion = getCurrentAppVersion()
            let currentBuild = getCurrentAppBuild()
            let releaseMetadata = await releaseToOffer(from: releases,
                                                       isMoreProminentUpdatesOn: isMoreProminentUpdatesOn,
                                                       currentVersion: currentVersion,
                                                       currentBuild: currentBuild)

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

                // With the flag off, this clears any clock left over from while it was on.
                updatePromptStageTracker?.updateCheckDidFinish(isUpdateAvailable: isMoreProminentUpdatesOn && isUpdateAvailable,
                                                               isCritical: releaseMetadata.isCritical)

                showUpdateNotificationIfNeeded(isOnboardingFinished: isOnboardingFinished)
            }

            // Record check time for rate limiting
            await updateCheckState.recordCheckTime()

        } catch {
            /// If we fail to fetch the latest version we do not want to show any messages to the user.
            updateProgress = .updateCycleDone(.finishedWithNoUpdateFound)

            pixelFiring?.fire(UpdateFlowPixels.releaseMetadataFetchFailed(error: error))

            Logger.updates.error("Failed to check for App Store updates: \(error.localizedDescription)")

            await MainActor.run {
                self.lastUpdateCheckDate = Date()
            }
        }
    }

    @objc public func openUpdatesPage() {
        appStoreOpener?.openAppStore()
    }

    public func handleAppTermination() {
        // Intentional no-op
    }

    // MARK: - Private Methods

    /// The rolling-out release once it's past the buffer, otherwise the latest release.
    /// The offer is critical if the user hasn't installed a critical latest release yet,
    /// so offering a newer release doesn't hide it.
    private func releaseToOffer(from releases: AppStoreReleases,
                                isMoreProminentUpdatesOn: Bool,
                                currentVersion: String?,
                                currentBuild: String?) async -> ReleaseMetadata {
        let offered = isMoreProminentUpdatesOn
            ? releases.releaseToOffer(availableAfter: promptSettings().appStoreUpdateAvailableDelay, now: now())
            : releases.latest

        guard !offered.isCritical, releases.latest.isCritical,
              await isUpdateAvailable(currentVersion: currentVersion,
                                      currentBuild: currentBuild,
                                      remoteVersion: releases.latest.latestVersion,
                                      remoteBuild: String(releases.latest.buildNumber)) else {
            return offered
        }

        return ReleaseMetadata(latestVersion: offered.latestVersion,
                               buildNumber: offered.buildNumber,
                               releaseDate: offered.releaseDate,
                               isCritical: true)
    }

    private func getCurrentAppVersion() -> String? {
        return appVersion.versionNumber.isEmpty ? nil : appVersion.versionNumber
    }

    private func getCurrentAppBuild() -> String? {
        return appVersion.buildNumber.isEmpty ? nil : appVersion.buildNumber
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

        guard let currentVersion else { return true }

        // Use semantic version comparison
        let result = compareSemanticVersions(currentVersion, remoteVersion)

        if result == .orderedAscending {
            // Current version is older than remote
            return true
        } else if result == .orderedSame {
            // Same version, check build numbers
            if let currentBuild {
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
