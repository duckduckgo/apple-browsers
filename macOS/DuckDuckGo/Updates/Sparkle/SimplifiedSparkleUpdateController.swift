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
    private enum NotificationDelay {
        static let regular: TimeInterval = .hours(1)
        static let critical: TimeInterval = 0
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

    private func refreshUpdateFromCache(_ cachedUpdateResult: UpdateCheckResult) {
        latestUpdate = Update(appcastItem: cachedUpdateResult.item, isInstalled: cachedUpdateResult.isInstalled, needsLatestReleaseNote: cachedUpdateResult.needsLatestReleaseNote)
        hasPendingUpdate = latestUpdate?.isInstalled == false && updateProgress.isDone && userDriver?.isResumable == true
    }

    @Published private(set) var updateProgress = UpdateCycleProgress.default {
        didSet {
            if let cachedUpdateResult {
                refreshUpdateFromCache(cachedUpdateResult)
            }
            handleUpdateNotification()
        }
    }

    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    @Published private(set) var latestUpdate: Update?

    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published private(set) var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    private(set) var mustShowUpdateIndicators = false

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

    private var shouldShowUpdateNotification: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    @UserDefaultsWrapper(key: .automaticUpdates, defaultValue: true)
    var areAutomaticUpdatesEnabled: Bool {
        willSet {
            if newValue != areAutomaticUpdatesEnabled {
                pendingNotificationTask?.cancel()
                pendingNotificationTask = nil
                updateWideEvent.cancelFlow(reason: .settingsChanged)
                userDriver?.cancelAndDismissCurrentUpdate()
                updater?.resetUpdateCycle()
            }
        }
        didSet {
            if oldValue != areAutomaticUpdatesEnabled {
                updateWideEvent.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled
                updateWideEvent.cancelFlow(reason: .settingsChanged)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    _ = try? self?.configureUpdater()
                    self?.checkForUpdateSkippingRollout()
                }
            }
        }
    }

    var isAtRestartCheckpoint: Bool {
        guard let userDriver else {
            return false
        }

        switch userDriver.updateProgress {
        case .readyToInstallAndRelaunch:
            return true
        case .updateCycleDone(let reason) where reason == .pausedAtRestartCheckpoint:
            return true
        default:
            return false
        }
    }

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
    private(set) var userDriver: UpdateUserDriver?
    private let willRelaunchAppSubject = PassthroughSubject<Void, Never>()
    private var internalUserDecider: InternalUserDecider
    private var updateProcessCancellable: AnyCancellable!

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
        super.init()

        // Clean up abandoned flows from previous sessions before starting any new checks
        self.updateWideEvent.cleanupAbandonedFlows()

        _ = try? configureUpdater()

        checkForUpdateRespectingRollout()

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
        if updateProgress.isDone, shouldCheckNewApplicationVersion {
            if case .updateCycleDone(.finishedWithNoUpdateFound) = updateProgress {
               checkNewApplicationVersion()
            }
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
    /// For automatic updates, regular notifications and the blue dot are delayed by 1 hour
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

        // Automatic updates: delay based on criticality
        let delay = latestUpdate.type == .critical
            ? NotificationDelay.critical
            : NotificationDelay.regular

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
        guard NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG) else {
            return
        }
#endif
        performUpdateCheck()
    }

    private func performUpdateCheck() {
        Task { @MainActor in
            guard let updater, updater.canCheckForUpdates, !updater.sessionInProgress else {
                Logger.updates.debug("Update check skipped - Sparkle not ready or session in progress")
                return
            }

            if case .updaterError = userDriver?.updateProgress {
                updateWideEvent.cancelFlow(reason: .newCheckStarted)
                userDriver?.cancelAndDismissCurrentUpdate()
            }

            updateWideEvent.startFlow(initiationType: .automatic)

            Logger.updates.log("Checking for updates respecting rollout")
            updater.checkForUpdatesInBackground()
        }
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
        Task { @MainActor in
            guard let updater, updater.canCheckForUpdates, !updater.sessionInProgress else {
                Logger.updates.debug("User-initiated update check skipped - Sparkle not ready or session in progress")
                return
            }

            Logger.updates.debug("User-initiated update check starting")

            if case .updaterError = userDriver?.updateProgress {
                updateWideEvent.cancelFlow(reason: .newCheckStarted)
                userDriver?.cancelAndDismissCurrentUpdate()
            }

            Logger.updates.log("Checking for updates skipping rollout")
            updater.checkForUpdates()
        }
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
        cachedUpdateResult = nil

        if let userDriver {
            userDriver.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled
        } else {
            userDriver = UpdateUserDriver(internalUserDecider: internalUserDecider,
                                          areAutomaticUpdatesEnabled: areAutomaticUpdatesEnabled,
                                          useLegacyAutoRestartLogic: false)
        }

        guard let userDriver,
              updater == nil else {
            return nil
        }

        let updater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: userDriver, delegate: self)

#if DEBUG
        if NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG) {
            updater.updateCheckInterval = 10_800
        } else {
            updater.updateCheckInterval = 0
        }
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
#else
        if updater.automaticallyDownloadsUpdates == true {
            updater.automaticallyDownloadsUpdates = false
        }
#endif

        updateProcessCancellable = userDriver.updateProgressPublisher
            .assign(to: \.updateProgress, onWeaklyHeld: self)

        try updater.start()
        self.updater = updater

        return updater
    }

    @objc func runUpdateFromMenuItem() {
        openUpdatesPage()
        runUpdate()
    }

    @objc func runUpdate() {
        guard userDriver != nil else { return }

        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidRunUpdate))
        resumeUpdater()
    }

    private func resumeUpdater() {
        if userDriver?.isResumable == false {
            PixelKit.fire(DebugEvent(GeneralPixel.updaterAttemptToRestartWithoutResumeBlock))
        }
        userDriver?.resume()
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
        if let state = userDriver?.sparkleUpdateState {
            Logger.updates.log("Sparkle update state: (userInitiated: \(state.userInitiated, privacy: .public), stage: \(state.stage.rawValue, privacy: .public))")
        } else {
            Logger.updates.log("Sparkle update state: Unknown")
        }
        if let userDriver {
            Logger.updates.log("isResumable: \(userDriver.isResumable, privacy: .public)")
        }
    }
}

extension SimplifiedSparkleUpdateController: SPUUpdaterDelegate {

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
        Logger.updates.log("Updater did find valid update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
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
        let nsError = error as NSError
        guard let item = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem else { return }

        Logger.updates.log("Updater did not find valid update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")

        let needsLatestReleaseNote = {
            guard let reason = nsError.userInfo[SPUNoUpdateFoundReasonKey] as? Int else { return false }
            return reason == Int(Sparkle.SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue)
        }()
        cachedUpdateResult = UpdateCheckResult(item: item, isInstalled: true, needsLatestReleaseNote: needsLatestReleaseNote)

        cachePendingUpdate(from: item)

        updateWideEvent.didFindNoUpdate()
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        Logger.updates.log("Updater will download update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        updateWideEvent.didStartDownload()
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater did download update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        updateWideEvent.didCompleteDownload()
        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidDownloadUpdate))

        userDriver?.updateLastUpdateDownloadedDate()
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater will extract update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        updateWideEvent.didStartExtraction()
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater did extract update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        updateWideEvent.didCompleteExtraction()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater will install update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        Logger.updates.log("Updater will install update on quit: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        userDriver?.configureResumeBlock(immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if error == nil {
            Logger.updates.log("Updater did finish update cycle with no error")
            updateProgress = .updateCycleDone(.finishedWithNoError)
        } else if let errorCode = (error as? NSError)?.code, errorCode == Int(Sparkle.SUError.noUpdateError.rawValue) {
            Logger.updates.log("Updater did finish update cycle with no update found")
            updateProgress = .updateCycleDone(.finishedWithNoUpdateFound)
            updateWideEvent.completeFlow(status: .success(reason: UpdateWideEventData.SuccessReason.noUpdateAvailable.rawValue))
        } else if let error {
            Logger.updates.log("Updater did finish update cycle with error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
            updateProgress = .updaterError(error)
            updateWideEvent.completeFlow(status: .failure, error: error)
        }
    }
}

#endif

