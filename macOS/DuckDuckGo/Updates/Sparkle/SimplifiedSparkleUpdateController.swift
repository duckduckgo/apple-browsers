//
//  SimplifiedSparkleUpdateController.swift
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

#if SPARKLE

import Foundation
import Common
import Combine
import Sparkle
import Persistence
import SwiftUIExtensions
import PixelKit
import PrivacyConfig
import SwiftUI
import os.log

/// Simplified Sparkle update controller.
///
/// Update checks rely on Sparkle's built-in scheduling (SUScheduledCheckInterval in Info.plist,
/// currently 3 hours) plus check-on-launch. Sparkle's `canCheckForUpdates` and `sessionInProgress`
/// guards prevent concurrent or invalid checks.
final class SimplifiedSparkleUpdateController: NSObject, SparkleUpdateControllerProtocol {

    enum Constants {
        static let internalChannelName = "internal-channel"
        static let pendingUpdateInfoKey = "com.duckduckgo.updateController.pendingUpdateInfo"
    }

    /// Delay before showing update notifications for automatic updates.
    /// Critical updates show immediately; regular updates are delayed to reduce noise
    /// since they'll install on quit anyway.
    enum NotificationDelay {
        static let critical: TimeInterval = 0
        static let internalRegular: TimeInterval = .hours(2)
        static let externalRegular: TimeInterval = .days(2)

        static func delay(for updateType: Update.UpdateType, isInternalUser: Bool) -> TimeInterval {
            if updateType == .critical {
                return critical
            }

            return isInternalUser ? internalRegular : externalRegular
        }
    }

    private var pendingNotificationTask: Task<Void, Never>?

    lazy var notificationPresenter = UpdateNotificationPresenter()
    let willRelaunchAppPublisher: AnyPublisher<Void, Never>

    // Struct used to cache data until the updater finishes checking for updates
    struct UpdateCheckResult {
        let item: SUAppcastItem
        let isInstalled: Bool
        let needsLatestReleaseNote: Bool

        init(item: SUAppcastItem, isInstalled: Bool, needsLatestReleaseNote: Bool = false) {
            self.item = item
            self.isInstalled = isInstalled
            self.needsLatestReleaseNote = needsLatestReleaseNote
        }
    }

    private var cachedUpdateResult: UpdateCheckResult? {
        didSet {
            if let cachedUpdateResult {
                refreshUpdateFromCache(cachedUpdateResult)
            } else {
                latestUpdate = nil
                hasPendingUpdate = false
                needsNotificationDot = false
            }
        }
    }

    private func refreshUpdateFromCache(_ cachedUpdateResult: UpdateCheckResult, progress: UpdateCycleProgress? = nil) {
        latestUpdate = Update(appcastItem: cachedUpdateResult.item, isInstalled: cachedUpdateResult.isInstalled, needsLatestReleaseNote: cachedUpdateResult.needsLatestReleaseNote)
        let isInstalled = latestUpdate?.isInstalled == false
        // Use passed progress if available (avoids @Published willSet timing issue)
        let currentProgress = progress ?? progressState.updateProgress
        let isDone = currentProgress.isDone
        let isResumable = progressState.isResumable
        hasPendingUpdate = isInstalled && isDone && isResumable
    }

    // MARK: - Update Progress State Machine

    private let progressState: UpdateProgressManaging = UpdateProgressState()
    private var progressCancellable: AnyCancellable?

    var updateProgress: UpdateCycleProgress { progressState.updateProgress }
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { progressState.updateProgressPublisher }

    private func handleProgressChange(_ progress: UpdateCycleProgress) {
        if let cachedUpdateResult {
            refreshUpdateFromCache(cachedUpdateResult, progress: progress)
        }
        handleUpdateNotification()
    }

    @Published private(set) var latestUpdate: Update?

    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published private(set) var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    private(set) var mustShowUpdateIndicators = false
    let clearsNotificationDotOnMenuOpen = false

    private let keyValueStore: ThrowingKeyValueStoring

    private var pendingUpdateInfo: Data? {
        get {
            try? keyValueStore.object(forKey: Constants.pendingUpdateInfoKey) as? Data
        }
        set {
            try? keyValueStore.set(newValue, forKey: Constants.pendingUpdateInfoKey)
        }
    }

    var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }
    var lastUpdateNotificationShownDate: Date = .distantPast

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
    @UserDefaultsWrapper(key: .debugSparkleCustomFeedURL)
    private var customFeedURL: String?
#endif

    private var shouldShowUpdateNotification: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    @UserDefaultsWrapper(key: .automaticUpdates, defaultValue: true)
    var areAutomaticUpdatesEnabled: Bool {
        willSet {
            if newValue != areAutomaticUpdatesEnabled {
                pendingNotificationTask?.cancel()
                pendingNotificationTask = nil
            }
        }
        didSet {
            if oldValue != areAutomaticUpdatesEnabled {
                updateWideEvent.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled

                // If switching to automatic while at download checkpoint, trigger download
                if areAutomaticUpdatesEnabled && isAtDownloadCheckpoint {
                    progressState.resumeCallback?()
                }

                userDriver.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled

                // Update Sparkle settings when preference changes
                // Always check for updates; only auto-download when FF on AND automatic enabled
                let featureFlagEnabled = NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG)
                updater?.automaticallyChecksForUpdates = true
                updater?.automaticallyDownloadsUpdates = featureFlagEnabled && areAutomaticUpdatesEnabled
            }
        }
    }

    var isAtRestartCheckpoint: Bool { progressState.isAtRestartCheckpoint }
    var isAtDownloadCheckpoint: Bool { progressState.isAtDownloadCheckpoint }

    // Simplified: Always returns false - no expiration logic
    var shouldForceUpdateCheck: Bool { false }

    // Simplified: Always returns false - only "new" behavior
    var useLegacyAutoRestartLogic: Bool { false }

    @UserDefaultsWrapper(key: .pendingUpdateShown, defaultValue: false)
    var needsNotificationDot: Bool {
        didSet {
            notificationDotSubject.send(needsNotificationDot)
        }
    }

    private let notificationDotSubject = CurrentValueSubject<Bool, Never>(false)
    lazy var notificationDotPublisher = notificationDotSubject.eraseToAnyPublisher()

    private(set) var updater: SPUUpdater?
    private(set) var userDriver: SimplifiedUpdateUserDriver
    private let willRelaunchAppSubject = PassthroughSubject<Void, Never>()
    private var internalUserDecider: InternalUserDecider

    private var shouldCheckNewApplicationVersion = true

    // MARK: - WideEvent Tracking

    let updateWideEvent: SparkleUpdateWideEvent

    // MARK: - Feature Flags support

    private let featureFlagger: FeatureFlagger

    // MARK: - Public

    init(internalUserDecider: InternalUserDecider,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         keyValueStore: ThrowingKeyValueStoring = NSApp.delegateTyped.keyValueStore,
         updateWideEvent: SparkleUpdateWideEvent? = nil) {

        willRelaunchAppPublisher = willRelaunchAppSubject.eraseToAnyPublisher()
        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
        self.keyValueStore = keyValueStore

        // Capture the current value before initializing updateWideEvent
        let currentAutomaticUpdatesEnabled = UserDefaultsWrapper<Bool>(key: .automaticUpdates, defaultValue: true).wrappedValue
        self.updateWideEvent = updateWideEvent ?? SparkleUpdateWideEvent(
            wideEventManager: NSApp.delegateTyped.wideEvent,
            internalUserDecider: internalUserDecider,
            areAutomaticUpdatesEnabled: currentAutomaticUpdatesEnabled
        )
        self.userDriver = SimplifiedUpdateUserDriver(
            internalUserDecider: internalUserDecider,
            areAutomaticUpdatesEnabled: currentAutomaticUpdatesEnabled,
            onProgressChange: progressState.handleProgressChange
        )
        super.init()

        // Subscribe to progress state changes
        progressCancellable = progressState.updateProgressPublisher
            .sink { [weak self] progress in
                self?.handleProgressChange(progress)
            }

        // Clean up abandoned flows from previous sessions before starting any new checks
        self.updateWideEvent.cleanupAbandonedFlows()

        _ = try? configureUpdater()

        validateUpdateExpectations()
    }

    private func validateUpdateExpectations() {
        let updateStatus = ApplicationUpdateDetector.isApplicationUpdated()

        SparkleUpdateCompletionValidator.validateExpectations(
            updateStatus: updateStatus,
            currentVersion: AppVersion.shared.versionNumber,
            currentBuild: AppVersion.shared.buildNumber)
    }

    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress) {
        guard shouldCheckNewApplicationVersion else { return }

        if areAutomaticUpdatesEnabled {
            // Automatic updates: show "browser updated" immediately.
            // The "update available" notification is delayed for automatic updates,
            // so there's no risk of overlapping notifications.
            checkNewApplicationVersion()
            shouldCheckNewApplicationVersion = false
        } else if updateProgress.isDone,
                  case .updateCycleDone(.finishedWithNoUpdateFound) = updateProgress {
            // Manual updates: only show if no newer update is available.
            // Manual mode shows "update available" immediately, so showing
            // "browser updated" at the same time would cause overlapping notifications.
            checkNewApplicationVersion()
            shouldCheckNewApplicationVersion = false
        }
    }

    private func checkNewApplicationVersion() {
        let updateStatus = ApplicationUpdateDetector.isApplicationUpdated()

        switch updateStatus {
        case .noChange: break
        case .updated:
            notificationPresenter.showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserUpdatedNotification, buttonText: UserText.viewDetails)
        case .downgraded:
            notificationPresenter.showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserDowngradedNotification, buttonText: UserText.viewDetails)
        }
    }

    // MARK: - Update Indicators (Dot + Notification + Menu Item)

    /// Shows update UI: blue dot, banner notification, and enables menu item visibility.
    private func showUpdateIndicators() {
        mustShowUpdateIndicators = true
        needsNotificationDot = true
        showUpdateNotificationIfNeeded()
    }

    /// Hides update UI: cancels pending task, hides blue dot, and disables menu item visibility.
    private func hideUpdateIndicators() {
        pendingNotificationTask?.cancel()
        pendingNotificationTask = nil
        mustShowUpdateIndicators = false
        needsNotificationDot = false
    }

    /// Handles update notification and blue dot logic with delays for automatic updates.
    ///
    /// For automatic updates, regular notifications and the blue dot are delayed.
    /// to reduce noise - users who quit within that time get the update silently.
    /// Critical updates show immediately. Manual updates show immediately (unchanged behavior).
    private func handleUpdateNotification() {
        guard let latestUpdate, hasPendingUpdate else {
            hideUpdateIndicators()
            return
        }

        // Already scheduled - don't restart the timer
        guard pendingNotificationTask == nil else { return }

        // Manual updates: show immediately (unchanged behavior)
        guard areAutomaticUpdatesEnabled else {
            showUpdateIndicators()
            return
        }

        // Automatic updates: delay based on criticality and internal/external user status.
        let delay = NotificationDelay.delay(for: latestUpdate.type, isInternalUser: internalUserDecider.isInternalUser)

        if delay == 0 {
            showUpdateIndicators()
        } else {
            scheduleDelayedNotification(delay: delay)
        }
    }

    private func scheduleDelayedNotification(delay: TimeInterval) {
        pendingNotificationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(interval: delay)
            guard let self, !Task.isCancelled, self.hasPendingUpdate else { return }
            self.showUpdateIndicators()
        }
    }

    func checkForUpdateRespectingRollout() {
#if DEBUG
        let featureFlagOn = NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG)
        guard featureFlagOn else {
            Logger.updates.debug("Skipping update check - autoUpdateInDEBUG feature flag is off")
            return
        }
#endif
        performUpdateCheck()
    }

    private func performUpdateCheck() {
        guard let updater, updater.canCheckForUpdates else {
            Logger.updates.debug("Skipping update check - Sparkle not ready")
            return
        }

        // State machine decides if transition is allowed
        if progressState.transition(to: .updateCycleDidStart) {
            updateWideEvent.startFlow(initiationType: .automatic)
        }

        updater.checkForUpdatesInBackground()
    }

    func checkForUpdateSkippingRollout() {
        updateWideEvent.startFlow(initiationType: .manual)
        performUpdateCheckSkippingRollout()
    }

    func openUpdatesPage() {
        DispatchQueue.main.async {
            Application.appDelegate.windowControllersManager.showTab(with: .releaseNotes)
        }
    }

    private func performUpdateCheckSkippingRollout() {
        guard let updater, updater.canCheckForUpdates else {
            Logger.updates.debug("User-initiated update check skipped - Sparkle not ready")
            return
        }

        // State machine decides if transition is allowed
        // Wide event flow already started by caller (checkForUpdateSkippingRollout)
        progressState.transition(to: .updateCycleDidStart)

        Logger.updates.log("Checking for updates skipping rollout")
        updater.checkForUpdates()
    }

    // MARK: - Private

    private func cachePendingUpdate(from item: SUAppcastItem) {
        let info = SparkleUpdateController.PendingUpdateInfo(from: item)
        if let encoded = try? JSONEncoder().encode(info) {
            pendingUpdateInfo = encoded
            Logger.updates.log("Cached pending update info for version \(info.version) build \(info.build)")
        }
    }

    @discardableResult
    private func configureUpdater() throws -> SPUUpdater? {
        guard updater == nil else {
            return nil
        }

        cachedUpdateResult = nil

        let updater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: userDriver, delegate: self)

        let featureFlagEnabled = NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG)

        updater.updateCheckInterval = 10_800
        // Always check for updates (so user sees update available even in manual mode)
        // Only auto-download when FF is on AND automatic updates are enabled
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = featureFlagEnabled && areAutomaticUpdatesEnabled

        try updater.start()
        self.updater = updater

        // Trigger check immediately after start(), before next run loop
        // Per Sparkle docs: checks can be invoked right after start() and before
        // the next runloop cycle to avoid racing with Sparkle's scheduled check
        checkForUpdateRespectingRollout()

        return updater
    }

    @objc func runUpdateFromMenuItem() {
        openUpdatesPage()
        runUpdate()
    }

    @objc func runUpdate() {
        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidRunUpdate))
        resumeUpdater()
    }

    private func resumeUpdater() {
        if !progressState.isResumable {
            PixelKit.fire(DebugEvent(GeneralPixel.updaterAttemptToRestartWithoutResumeBlock))
        }
        progressState.resumeCallback?()
    }

    func handleAppTermination() {
        updateWideEvent.handleAppTermination()
    }

    func log() {
        Logger.updates.log("areAutomaticUpdatesEnabled: \(self.areAutomaticUpdatesEnabled, privacy: .public)")
        Logger.updates.log("updateProgress: \(self.updateProgress, privacy: .public)")
        if let cachedUpdateResult {
            Logger.updates.log("cachedUpdateResult: \(cachedUpdateResult.item.displayVersionString, privacy: .public)(\(cachedUpdateResult.item.versionString, privacy: .public))")
        }
        if let state = userDriver.sparkleUpdateState {
            Logger.updates.log("Sparkle update state: (userInitiated: \(state.userInitiated, privacy: .public), stage: \(state.stage.rawValue, privacy: .public))")
        } else {
            Logger.updates.log("Sparkle update state: Unknown")
        }
        Logger.updates.log("isResumable: \(self.progressState.isResumable, privacy: .public)")
    }

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
    // MARK: - Debug: Custom Feed URL

    func setCustomFeedURL(_ urlString: String) {
        customFeedURL = urlString
    }

    func resetFeedURLToDefault() {
        customFeedURL = nil
    }
#endif
}

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
extension SimplifiedSparkleUpdateController: SparkleCustomFeedURLProviding {}
#endif

extension SimplifiedSparkleUpdateController: SPUUpdaterDelegate {

    func feedURLString(for updater: SPUUpdater) -> String? {
#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
        return customFeedURL
#else
        return nil
#endif
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        if internalUserDecider.isInternalUser {
            return Set([Constants.internalChannelName])
        } else {
            return Set()
        }
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Logger.updates.log("Updater will relaunch application")

        updateWideEvent.didInitiateRestart()

        if let flowData = updateWideEvent.getCurrentFlowData() {
            SparkleUpdateCompletionValidator.storePendingUpdateMetadata(
                sourceVersion: flowData.fromVersion,
                sourceBuild: flowData.fromBuild,
                expectedVersion: flowData.toVersion ?? "unknown",
                expectedBuild: flowData.toBuild ?? "unknown",
                initiationType: flowData.initiationType.rawValue,
                updateConfiguration: flowData.updateConfiguration.rawValue
            )
        }

        willRelaunchAppSubject.send()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Logger.updates.error("Updater did abort with error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
        let errorCode = (error as NSError).code
        guard ![Int(Sparkle.SUError.noUpdateError.rawValue),
                Int(Sparkle.SUError.resumeAppcastError.rawValue),
                Int(Sparkle.SUError.installationCanceledError.rawValue),
                Int(Sparkle.SUError.runningTranslocated.rawValue),
                Int(Sparkle.SUError.downloadError.rawValue)].contains(errorCode) else {
            return
        }

        PixelKit.fire(DebugEvent(
            GeneralPixel.updaterAborted(reason: sparkleUpdaterErrorReason(from: error.localizedDescription)),
            error: error
        ))
    }

    internal func sparkleUpdaterErrorReason(from errorDescription: String) -> String {
        let knownErrorPrefixes = [
            "Failed to resume installing update.",
            "Package installer failed to launch.",
            "Guided package installer failed to launch",
            "Guided package installer returned non-zero exit status",
            "Failed to perform installation because the paths to install at and from are not valid",
            "Failed to recursively update new application's modification time before moving into temporary directory",
            "Failed to perform installation because a path could not be constructed for the old installation",
            "Failed to move the new app",
            "Failed to perform installation because the last path component of the old installation URL could not be constructed.",
            "The update is improperly signed and could not be validated.",
            "Found regular application update",
            "An error occurred while running the updater.",
            "An error occurred while encoding the installer parameters.",
            "An error occurred while starting the installer.",
            "An error occurred while connecting to the installer.",
            "An error occurred while launching the installer.",
            "An error occurred while extracting the archive",
            "An error occurred while downloading the update",
            "An error occurred in retrieving update information",
            "An error occurred while parsing the update feed"
        ]

        for prefix in knownErrorPrefixes where errorDescription.hasPrefix(prefix) {
            return prefix
        }

        return "unknown"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.updates.log("Found update: \(item.displayVersionString, privacy: .public) (\(item.versionString, privacy: .public))")

        // Sparkle background checks bypass our check methods, so ensure tracking exists
        updateWideEvent.ensureFlowExists(initiationType: .automatic)

        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidFindUpdate))
        cachedUpdateResult = UpdateCheckResult(item: item, isInstalled: false)

        cachePendingUpdate(from: item)

        updateWideEvent.didFindUpdate(
            version: item.displayVersionString,
            build: item.versionString,
            isCritical: item.isCriticalUpdate
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Sparkle background checks bypass our check methods, so ensure tracking exists
        updateWideEvent.ensureFlowExists(initiationType: .automatic)

        let nsError = error as NSError
        guard let item = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem else { return }

        Logger.updates.log("Already up to date: \(item.displayVersionString, privacy: .public) (\(item.versionString, privacy: .public))")

        let needsLatestReleaseNote = {
            guard let reason = nsError.userInfo[SPUNoUpdateFoundReasonKey] as? Int else { return false }
            return reason == Int(Sparkle.SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue)
        }()
        cachedUpdateResult = UpdateCheckResult(item: item, isInstalled: true, needsLatestReleaseNote: needsLatestReleaseNote)

        cachePendingUpdate(from: item)

        updateWideEvent.didFindNoUpdate()
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        Logger.updates.log("Downloading update: \(item.displayVersionString, privacy: .public)")
        progressState.transition(to: .downloadDidStart)
        updateWideEvent.didStartDownload()
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Logger.updates.log("Download complete: \(item.displayVersionString, privacy: .public)")
        updateWideEvent.didCompleteDownload()
        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidDownloadUpdate))

        userDriver.updateLastUpdateDownloadedDate()
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        Logger.updates.debug("Extracting update: \(item.displayVersionString, privacy: .public)")
        progressState.transition(to: .extractionDidStart)
        updateWideEvent.didStartExtraction()
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        Logger.updates.debug("Extraction complete: \(item.displayVersionString, privacy: .public)")
        updateWideEvent.didCompleteExtraction()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Logger.updates.log("Installing update: \(item.displayVersionString, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        Logger.updates.log("Update ready - will install on quit: \(item.displayVersionString, privacy: .public)")
        progressState.transition(to: .updateCycleDone(.pausedAtRestartCheckpoint), resume: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if error == nil {
            progressState.transition(to: .updateCycleDone(.finishedWithNoError))
        } else if let errorCode = (error as? NSError)?.code, errorCode == Int(Sparkle.SUError.noUpdateError.rawValue) {
            progressState.transition(to: .updateCycleDone(.finishedWithNoUpdateFound))
            updateWideEvent.completeFlow(status: .success(reason: UpdateWideEventData.SuccessReason.noUpdateAvailable.rawValue))
        } else if let error {
            Logger.updates.error("Update cycle failed: \(error.localizedDescription, privacy: .public)")
            progressState.transition(to: .updaterError(error))
            updateWideEvent.completeFlow(status: .failure, error: error)
        }
    }
}

#endif
