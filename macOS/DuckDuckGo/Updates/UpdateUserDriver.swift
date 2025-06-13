//
//  UpdateUserDriver.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Combine
import Foundation
import os.log
import PixelKit
import Sparkle

#if SPARKLE

enum UpdateState {
    case upToDate
    case updateCycle(UpdateCycleProgress)

    init(from update: Update?, progress: UpdateCycleProgress) {
        if let update, !update.isInstalled {
            self = .updateCycle(progress)
        } else if progress.isFailed {
            self = .updateCycle(progress)
        } else {
            self = .upToDate
        }
    }
}

enum UpdateCycleProgress: CustomStringConvertible {
    enum DoneReason: Int {
        case finishedWithNoError = 100
        case finishedWithNoUpdateFound = 101
        case pausedAtDownloadCheckpoint = 102
        case pausedAtRestartCheckpoint = 103
        case proceededToInstallationAtRestartCheckpoint = 104
        case dismissedWithNoError = 105
        case dismissingObsoleteUpdate = 106
    }

    case updateCycleNotStarted
    case updateCycleDidStart
    case updateCycleDone(DoneReason)
    case downloadDidStart
    case downloading(Double)
    case extractionDidStart
    case extracting(Double)
    case readyToInstallAndRelaunch
    case installationDidStart
    case installing
    case updaterError(Error)

    static var `default` = UpdateCycleProgress.updateCycleNotStarted

    var isDone: Bool {
        switch self {
        case .updateCycleDone: return true
        default: return false
        }
    }

    var isIdle: Bool {
        switch self {
        case .updateCycleDone, .updateCycleNotStarted, .updaterError: return true
        default: return false
        }
    }

    var isFailed: Bool {
        switch self {
        case .updaterError: return true
        default: return false
        }
    }

    var description: String {
        switch self {
        case .updateCycleNotStarted: return "updateCycleNotStarted"
        case .updateCycleDidStart: return "updateCycleDidStart"
        case .updateCycleDone(let reason): return "updateCycleDone(\(reason.rawValue))"
        case .downloadDidStart: return "downloadDidStart"
        case .downloading(let percentage): return "downloading(\(percentage))"
        case .extractionDidStart: return "extractionDidStart"
        case .extracting(let percentage): return "extracting(\(percentage))"
        case .readyToInstallAndRelaunch: return "readyToInstallAndRelaunch"
        case .installationDidStart: return "installationDidStart"
        case .installing: return "installing"
        case .updaterError(let error): return "updaterError(\(error.localizedDescription))(\(error.pixelParameters))"
        }
    }
}

final class UpdateUserDriver: NSObject, SPUUserDriver {
    private var internalUserDecider: InternalUserDecider
    private var areAutomaticUpdatesEnabled: Bool

    // Resume the update process when the user explicitly chooses to do so
    private var onResuming: (() -> Void)? {
        didSet {
            if useLegacyAutoRestartLogic {
                updateLastCheckForUpdatesDate()
            }
        }
    }

    @UserDefaultsWrapper(key: .pendingUpdateSince, defaultValue: .distantPast)
    private var pendingUpdateSince: Date

    func updateLastCheckForUpdatesDate() {
        pendingUpdateSince = Date()
    }

    var daysSinceLastUpdateCheck: Int {
        Calendar.current.dateComponents([.day], from: pendingUpdateSince, to: Date()).day ?? Int.max
    }

    // Dismiss the current update for the time being but keep the downloaded file around
    private var onDismiss: () -> Void = {}

    var isResumable: Bool {
        onResuming != nil
    }

    private var bytesToDownload: UInt64 = 0
    private var bytesDownloaded: UInt64 = 0

    @Published var updateProgress = UpdateCycleProgress.default
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    private(set) var sparkleUpdateState: SPUUserUpdateState?

    // MARK: - Feature Flags support

    private let featureFlagger: FeatureFlagger

    private var useLegacyAutoRestartLogic: Bool {
        !featureFlagger.isFeatureOn(.updatesWontAutomaticallyRestartApp)
    }

    // MARK: - Initializers

    init(internalUserDecider: InternalUserDecider,
         areAutomaticUpdatesEnabled: Bool,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {

        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
        self.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled
    }

    func resume() {
        onResuming?()
    }

    func configureResumeBlock(_ block: @escaping () -> Void) {
        guard !isResumable else { return }
        onResuming = block
    }

    func cancelAndDismissCurrentUpdate() {
        onDismiss()
        pendingUpdateSince = .distantPast
    }

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
#if DEBUG
        .init(automaticUpdateChecks: false, sendSystemProfile: false)
#else
        .init(automaticUpdateChecks: true, sendSystemProfile: false)
#endif
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        Logger.updates.log("Updater started performing the update check. (isInternalUser: \(self.internalUserDecider.isInternalUser, privacy: .public))")
        updateProgress = .updateCycleDidStart
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        Logger.updates.log("Updater shown update found: (userInitiated:  \(state.userInitiated, privacy: .public), stage: \(state.stage.rawValue, privacy: .public))")
        sparkleUpdateState = state

        if appcastItem.isInformationOnlyUpdate {
            Logger.updates.log("Updater dismissed due to information only update")
            reply(.dismiss)
        }

        onDismiss = {
            // Dismiss the update for the time being
            // If the update has been updated, it's kept till the next time an update is shown to the user
            // If the update is installing, it's also preserved after dismissing, and will also be installed after the app is terminated
            reply(.dismiss)
        }

        if !areAutomaticUpdatesEnabled {
            onResuming = { reply(.install) }
            updateProgress = .updateCycleDone(.pausedAtDownloadCheckpoint)
            Logger.updates.log("Updater paused at download checkpoint (manual update pending user decision)")
        } else {
            Logger.updates.log("Updater proceeded to installation at download checkpoint")
            reply(.install)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // no-op
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // no-op
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        Logger.updates.error("Updater encountered an error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
        updateProgress = .updaterError(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Logger.updates.log("Updater started downloading the update")
        updateProgress = .downloadDidStart
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        bytesDownloaded = 0
        bytesToDownload = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        bytesDownloaded += length
        if bytesDownloaded > bytesToDownload {
            bytesToDownload = bytesDownloaded
        }
        updateProgress = .downloading(Double(bytesDownloaded) / Double(bytesToDownload))
    }

    func showDownloadDidStartExtractingUpdate() {
        Logger.updates.log("Updater started extracting the update")
        updateProgress = .extractionDidStart
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        updateProgress = .extracting(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        onDismiss = { [weak self] in
            // Cancel the current update that has begun installing and dismiss the update
            // This doesn't actually skip the update in the future (‽)
            reply(.skip)
            self?.updateProgress = .updateCycleDone(.dismissingObsoleteUpdate)
            Logger.updates.log("Updater dismissing obsolete update")
        }

        guard useLegacyAutoRestartLogic else {
            onResuming = { reply(.install) }
            updateProgress = .updateCycleDone(.pausedAtRestartCheckpoint)
            Logger.updates.log("Updater paused at restart checkpoint")
            return
        }

        if areAutomaticUpdatesEnabled {
            onResuming = { reply(.install) }
            updateProgress = .updateCycleDone(.pausedAtRestartCheckpoint)
            Logger.updates.log("Updater paused at restart checkpoint (automatic update pending user decision)")
        } else {
            reply(.install)
            updateProgress = .updateCycleDone(.proceededToInstallationAtRestartCheckpoint)
            Logger.updates.log("Updater proceeded to installation at restart checkpoint")
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Logger.updates.info("Updater started the installation")
        updateProgress = .installationDidStart

        if !applicationTerminated {
            Logger.updates.log("Updater re-sent a quit event")
            retryTerminatingApplication()
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        updateProgress = .installing
        acknowledgement()
    }

    func showUpdateInFocus() {
        // no-op
    }

    func dismissUpdateInstallation() {
        guard !updateProgress.isFailed else { return }
        updateProgress = .updateCycleDone(.dismissedWithNoError)
    }
}

#endif
