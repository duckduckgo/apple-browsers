//
//  SparkleUpdateController.swift
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

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
protocol SparkleCustomFeedURLProviding {
    func setCustomFeedURL(_ urlString: String)
    func resetFeedURLToDefault()
}
#endif

protocol SparkleUpdateControllerProtocol: UpdateController {
    // Sparkle-specific state
    var isAtRestartCheckpoint: Bool { get }
    var shouldForceUpdateCheck: Bool { get }
    var useLegacyAutoRestartLogic: Bool { get }
    var willRelaunchAppPublisher: AnyPublisher<Void, Never> { get }

    // Sparkle-specific methods
    func checkForUpdateRespectingRollout()
    func runUpdateFromMenuItem()
    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress)
    func log()
}

final class SparkleUpdateController: NSObject, SparkleUpdateControllerProtocol {

    enum Constants {
        static let internalChannelName = "internal-channel"
    }

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

    // Struct used to persist pending update info across app restarts
    struct PendingUpdateInfo: Codable {
        let version: String
        let build: String
        let date: Date
        let releaseNotes: [String]
        let releaseNotesSubscription: [String]
        let isCritical: Bool

        init(version: String, build: String, date: Date, releaseNotes: [String], releaseNotesSubscription: [String], isCritical: Bool) {
            self.version = version
            self.build = build
            self.date = date
            self.releaseNotes = releaseNotes
            self.releaseNotesSubscription = releaseNotesSubscription
            self.isCritical = isCritical
        }

        init(from item: SUAppcastItem) {
            self.version = item.displayVersionString
            self.build = item.versionString
            self.date = item.date ?? Date()
            let (notes, notesSubscription) = ReleaseNotesParser.parseReleaseNotes(from: item.itemDescription)
            self.releaseNotes = notes
            self.releaseNotesSubscription = notesSubscription
            self.isCritical = item.isCriticalUpdate
        }
    }

    @Published private(set) var updateProgress = UpdateCycleProgress.default {
        didSet {
            if let cachedUpdateResult {
                refreshUpdateFromCache(cachedUpdateResult)
                needsNotificationDot = hasPendingUpdate
            }
            showUpdateNotificationIfNeeded()

            // Dismiss stale "update available" popover when download begins
            if case .downloadDidStart = updateProgress {
                notificationPresenter.dismissIfPresented()
            }
        }
    }

    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    @Published private(set) var latestUpdate: Update?

    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published private(set) var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    var mustShowUpdateIndicators: Bool { hasPendingUpdate }
    let clearsNotificationDotOnMenuOpen = true

    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>

    private var updateValidityStartDate: Date? {
        get { try? settings.updateValidityStartDate }
        set { try? settings.set(newValue, for: \.updateValidityStartDate) }
    }

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
    private var customFeedURL: String? {
        get {
            return try? settings.debugSparkleCustomFeedURL
        }
        set {
            try? settings.set(newValue, for: \.debugSparkleCustomFeedURL)
        }
    }
#endif

    private var pendingUpdateInfo: PendingUpdateInfo? {
        get {
            try? settings.pendingUpdateInfo
        }
        set {
            try? settings.set(newValue, for: \.pendingUpdateInfo)
        }
    }

    var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }
    var lastUpdateNotificationShownDate: Date = .distantPast

    private var shouldShowUpdateNotification: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    var areAutomaticUpdatesEnabled: Bool {
        get {
            (try? settings.automaticUpdates) ?? true
        }
        set {
            let oldValue = areAutomaticUpdatesEnabled
            guard newValue != oldValue else { return }

            updateWideEvent.cancelFlow(reason: .settingsChanged)
            userDriver?.cancelAndDismissCurrentUpdate()

            if useLegacyAutoRestartLogic {
                updater = nil
            } else {
                updater?.resetUpdateCycle()
            }

            try? settings.set(newValue, for: \.automaticUpdates)

            updateWideEvent.areAutomaticUpdatesEnabled = newValue
            // Cancel with .settingsChanged reason to distinguish from user-initiated
            // cancellations. The 0.1s delay allows updater reconfiguration to complete.
            updateWideEvent.cancelFlow(reason: .settingsChanged)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                _ = try? self?.configureUpdater()
                self?.checkForUpdateSkippingRollout()
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

    var needsNotificationDot: Bool {
        get {
            (try? settings.pendingUpdateShown) ?? false
        }
        set {
            try? settings.set(newValue, for: \.pendingUpdateShown)
            notificationDotSubject.send(newValue)
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

    private let updateCheckState: UpdateCheckState

    // MARK: - WideEvent Tracking

    let updateWideEvent: SparkleUpdateWideEvent

    // MARK: - Update Detection

    private let applicationUpdateDetector: ApplicationUpdateDetector
    private let updateCompletionValidator: SparkleUpdateCompletionValidator

    // MARK: - Feature Flags support

    private let featureFlagger: FeatureFlagger

    var useLegacyAutoRestartLogic: Bool {
        !featureFlagger.isFeatureOn(.updatesWontAutomaticallyRestartApp)
    }
    private var canBuildsExpire: Bool {
        featureFlagger.isFeatureOn(.updatesWontAutomaticallyRestartApp)
    }

    // MARK: - Public

    init(internalUserDecider: InternalUserDecider,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         updateCheckState: UpdateCheckState = UpdateCheckState(),
         keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard,
         updateWideEvent: SparkleUpdateWideEvent? = nil) {

        willRelaunchAppPublisher = willRelaunchAppSubject.eraseToAnyPublisher()
        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
        self.updateCheckState = updateCheckState
        self.settings = keyValueStore.throwingKeyedStoring()

        // Capture the current value before initializing updateWideEvent
        let currentAutomaticUpdatesEnabled = (try? self.settings.automaticUpdates) ?? true

        self.applicationUpdateDetector = ApplicationUpdateDetector(settings: self.settings)
        self.updateCompletionValidator = SparkleUpdateCompletionValidator(settings: self.settings)

        self.updateWideEvent = updateWideEvent ?? SparkleUpdateWideEvent(
            wideEventManager: NSApp.delegateTyped.wideEvent,
            internalUserDecider: internalUserDecider,
            areAutomaticUpdatesEnabled: currentAutomaticUpdatesEnabled,
            settings: self.settings
        )
        super.init()

        // Clean up abandoned flows from previous sessions before starting any new checks
        self.updateWideEvent.cleanupAbandonedFlows()

        _ = try? configureUpdater()

        checkForUpdateRespectingRollout()
        subscribeToResignKeyNotifications()

        validateUpdateExpectations()
    }

    private func validateUpdateExpectations() {
        // Validate expectations from previous update attempt if any
        let updateStatus = applicationUpdateDetector.isApplicationUpdated()
        let currentVersion = AppVersion.shared.versionNumber
        let currentBuild = AppVersion.shared.buildNumber

        updateCompletionValidator.validateExpectations(
            updateStatus: updateStatus,
            currentVersion: currentVersion,
            currentBuild: currentBuild)
    }

    private var cancellables = Set<AnyCancellable>()

    private func subscribeToResignKeyNotifications() {
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] _ in
                self?.checkForUpdateRespectingRollout()
            }
            // Store subscription to keep it alive
            .store(in: &cancellables)
    }

    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress) {
        /// Displays the "Browser Updated/Downgraded" notification only after the first complete update cycle
        if updateProgress.isDone, shouldCheckNewApplicationVersion {
            /// Proceed only if no newer update is available for the user
            if case .updateCycleDone(.finishedWithNoUpdateFound) = updateProgress {
               checkNewApplicationVersion()
            }
            shouldCheckNewApplicationVersion = false
        }
    }

    private func checkNewApplicationVersion() {
        let updateStatus = applicationUpdateDetector.isApplicationUpdated()

        switch updateStatus {
        case .noChange: break
        case .updated:
            notificationPresenter.showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserUpdatedNotification, buttonText: UserText.viewDetails)
        case .downgraded:
            notificationPresenter.showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserDowngradedNotification, buttonText: UserText.viewDetails)
        }
    }

    // Check for updates while adhering to the rollout schedule
    // This is the default behavior
    func checkForUpdateRespectingRollout() {
#if DEBUG
        guard NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG) else {
            return
        }
#endif
        Task { @UpdateCheckActor in
            await performUpdateCheck()
        }
    }

    @UpdateCheckActor
    private func performUpdateCheck() async {
        // Check if we can start a new check (Sparkle availability + rate limiting)
        let updaterAvailability = SparkleUpdaterAvailabilityChecker(updater: updater)
        guard await updateCheckState.canStartNewCheck(updater: updaterAvailability, latestUpdate: latestUpdate) else {
            Logger.updates.debug("Update check skipped - not allowed by Sparkle or rate limited")
            return
        }

        if case .updaterError = userDriver?.updateProgress {
            updateWideEvent.cancelFlow(reason: .newCheckStarted)
            userDriver?.cancelAndDismissCurrentUpdate()
        }

        // Create the actual update task
        Task { @MainActor in
            // Handle expired builds first (critical path)
            guard !discardCurrentUpdateIfExpiredAndCheckAgain(skipRollout: false) else {
                return
            }

            guard let updater, !updater.sessionInProgress else { return }

            // Start WideEvent tracking after precondition checks to ensure we only track
            // flows that actually reach Sparkle. Failed preconditions (expired builds,
            // rate limiting, Sparkle unavailability) don't create flows.
            updateWideEvent.startFlow(initiationType: .automatic)

            Logger.updates.log("Checking for updates respecting rollout")
            updater.checkForUpdatesInBackground()
        }
    }

    private var isBuildExpired: Bool {
        canBuildsExpire && shouldForceUpdateCheck
    }

    @discardableResult
    private func discardCurrentUpdateIfExpiredAndCheckAgain(skipRollout: Bool) -> Bool {
        guard isBuildExpired else {
            return false
        }

        updateWideEvent.cancelFlow(reason: .buildExpired)
        userDriver?.cancelAndDismissCurrentUpdate()
        if useLegacyAutoRestartLogic {
            updater = nil
        } else {
            updater?.resetUpdateCycle()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  let updater = try? configureUpdater() else {
                return
            }

            if skipRollout {
                updater.checkForUpdates()
            } else {
                updater.checkForUpdatesInBackground()
            }
        }

        return true
    }

    // Check for updates immediately, bypassing the rollout schedule
    // This is used for user-initiated update checks only
    func checkForUpdateSkippingRollout() {
        // Start WideEvent tracking for manual update check
        updateWideEvent.startFlow(initiationType: .manual)

        Task { @UpdateCheckActor in
            await performUpdateCheckSkippingRollout()
        }
    }

    func openUpdatesPage() {
        DispatchQueue.main.async {
            Application.appDelegate.windowControllersManager.showTab(with: .releaseNotes)
        }
    }

    @UpdateCheckActor
    private func performUpdateCheckSkippingRollout() async {
        // User-initiated checks skip rate limiting but still respect Sparkle availability
        let updaterAvailability = SparkleUpdaterAvailabilityChecker(updater: updater)
        guard await updateCheckState.canStartNewCheck(updater: updaterAvailability, latestUpdate: latestUpdate, minimumInterval: 0) else {
            Logger.updates.debug("User-initiated update check skipped - not allowed by Sparkle")
            return
        }

        Logger.updates.debug("User-initiated update check starting")

        if case .updaterError = userDriver?.updateProgress {
            updateWideEvent.cancelFlow(reason: .newCheckStarted)
            userDriver?.cancelAndDismissCurrentUpdate()
        }

        // Create the actual update task
        Task { @MainActor in
            // Handle expired builds first (critical path)
            guard !discardCurrentUpdateIfExpiredAndCheckAgain(skipRollout: true) else {
                return
            }

            guard let updater, !updater.sessionInProgress else { return }

            // Record that preconditions were met before calling Sparkle
            Logger.updates.debug("Preconditions met, checking for updates")

            Logger.updates.log("Checking for updates skipping rollout")
            updater.checkForUpdates()
        }
    }

    // MARK: - Private

    // Cache the pending update info to persist across app restarts
    private func cachePendingUpdate(from item: SUAppcastItem) {
        let info = PendingUpdateInfo(from: item)
        pendingUpdateInfo = info
        Logger.updates.log("Cached pending update info for version \(info.version) build \(info.build)")
    }

    // Determines if a forced update check is necessary
    //
    // Due to frequent releases (weekly public, daily internal), the downloaded update
    // may become obsolete if the user doesn't relaunch the app for an extended period.
    var shouldForceUpdateCheck: Bool {
        guard let updateValidityStartDate else {
            return true
        }

        let threshold = internalUserDecider.isInternalUser ? TimeInterval.hours(1) : TimeInterval.days(1)
        return Date().timeIntervalSince(updateValidityStartDate) > threshold
    }

    // Configures the updater
    //
    @discardableResult
    private func configureUpdater() throws -> SPUUpdater? {
        // Workaround to reset the updater state
        cachedUpdateResult = nil

        if !useLegacyAutoRestartLogic, let userDriver {
            userDriver.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled
        } else {
            userDriver = UpdateUserDriver(internalUserDecider: internalUserDecider,
                                          areAutomaticUpdatesEnabled: areAutomaticUpdatesEnabled,
                                          useLegacyAutoRestartLogic: useLegacyAutoRestartLogic,
                                          settings: settings)
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
        // Some older version uses SUAutomaticallyUpdate to control app restart behavior
        // We disable it to prevent interference with our custom updater UI
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
        // Duplicating the code a bit to make the feature flag separation clearer
        // remove this comment once the feature flag is removed.
        guard useLegacyAutoRestartLogic else {
            openUpdatesPage()

            if shouldForceUpdateCheck {
                checkForUpdateRespectingRollout()
                return
            }

            runUpdate()
            return
        }

        if shouldForceUpdateCheck {
            openUpdatesPage()
        }

        runUpdate()
    }

    @objc func runUpdate() {
        guard let userDriver else { return }

        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidRunUpdate))

        guard useLegacyAutoRestartLogic else {
            resumeUpdater()
            return
        }

        guard shouldForceUpdateCheck else {
            resumeUpdater()
            return
        }

        updateWideEvent.cancelFlow(reason: .newCheckStarted)
        userDriver.cancelAndDismissCurrentUpdate()
        if useLegacyAutoRestartLogic {
            updater = nil
        } else {
            updater?.resetUpdateCycle()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            _ = try? self?.configureUpdater()
            self?.checkForUpdateSkippingRollout()
        }
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
extension SparkleUpdateController: SparkleCustomFeedURLProviding {}
#endif

extension SparkleUpdateController: SPUUpdaterDelegate {

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

        // Mark that user interacted with "Restart to Update" button
        // This sets lastKnownStep to .restartingToUpdate to distinguish from
        // users who just quit the app (which stays at .extractionCompleted)
        updateWideEvent.didInitiateRestart()

        // Capture metadata from wide event before app terminates
        if let flowData = updateWideEvent.getCurrentFlowData() {
            updateCompletionValidator.storePendingUpdateMetadata(
                sourceVersion: flowData.fromVersion,
                sourceBuild: flowData.fromBuild,
                expectedVersion: flowData.toVersion ?? "unknown",
                expectedBuild: flowData.toBuild ?? "unknown",
                initiationType: flowData.initiationType.rawValue,
                updateConfiguration: flowData.updateConfiguration.rawValue
            )
        }

        // Note: Wide event completion is handled by handleAppTermination()
        // which fires when the app actually terminates
        willRelaunchAppSubject.send()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Logger.updates.error("Updater did abort with error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
        let errorCode = (error as NSError).code
        guard ![Int(Sparkle.SUError.noUpdateError.rawValue),
                // Triggered when the user cancels the update during installation
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
        // Hardcodes known Sparkle failures to ensure that no file paths are ever included.
        // Any unrecognized strings will be sent with "unknown", and will need to be debugged further as it means there
        // is a Sparkle error that isn't being accounted for in this list.
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
        updateValidityStartDate = Date()

        cachePendingUpdate(from: item)

        // Split responsibility: Sparkle delegate provides update metadata,
        // WideEvent tracks it. This is where we first learn target version/build.
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

        // Edge case: User upgrades to latest version within their rollout group
        // But fetched release notes are outdated due to rollout group reset
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

        if !useLegacyAutoRestartLogic,
           let userDriver {

            userDriver.updateLastUpdateDownloadedDate()
        }
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
            Task { @UpdateCheckActor in await updateCheckState.recordCheckTime() }
            // NOTE: For install-and-restart scenarios, this delegate method is NOT called
            // because the app terminates before the completion handler fires.
            // Wide event completion happens in updaterWillRelaunchApplication instead.
            // This branch only handles non-restart success cases (e.g., updates dismissed/skipped).
        } else if let errorCode = (error as? NSError)?.code, errorCode == Int(Sparkle.SUError.noUpdateError.rawValue) {
            Logger.updates.log("Updater did finish update cycle with no update found")
            updateProgress = .updateCycleDone(.finishedWithNoUpdateFound)
            Task { @UpdateCheckActor in await updateCheckState.recordCheckTime() }
            updateWideEvent.completeFlow(status: .success(reason: UpdateWideEventData.SuccessReason.noUpdateAvailable.rawValue))
        } else if let error {
            Logger.updates.log("Updater did finish update cycle with error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
            updateProgress = .updaterError(error)
            // Complete WideEvent with failure
            updateWideEvent.completeFlow(status: .failure, error: error)
        }
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

#endif
