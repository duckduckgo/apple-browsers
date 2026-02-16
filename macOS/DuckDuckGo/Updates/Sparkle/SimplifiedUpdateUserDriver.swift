//
//  SimplifiedUpdateUserDriver.swift
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

import AppKit
import Foundation
import os.log
import Persistence
import PixelKit
import PrivacyConfig
#if SPARKLE
import Sparkle
#endif

#if SPARKLE
final class SimplifiedUpdateUserDriver: NSObject, SPUUserDriver {
    private var internalUserDecider: InternalUserDecider
    var areAutomaticUpdatesEnabled: Bool
    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>

    private var pendingUpdateSince: Date {
        get { (try? settings.pendingUpdateSince) ?? .distantPast }
        set { try? settings.set(newValue, for: \.pendingUpdateSince) }
    }

    func updateLastUpdateDownloadedDate() {
        pendingUpdateSince = Date()
    }

    var timeIntervalSinceLastUpdateDownloaded: TimeInterval {
        Date().timeIntervalSince(pendingUpdateSince)
    }

    private var onDismiss: () -> Void = {}

    private var bytesToDownload: UInt64 = 0
    private var bytesDownloaded: UInt64 = 0

    let onProgressChange: (UpdateCycleProgress, (() -> Void)?) -> Void

    private(set) var sparkleUpdateState: SPUUserUpdateState?

    // MARK: - Initializers

    init(internalUserDecider: InternalUserDecider,
         areAutomaticUpdatesEnabled: Bool,
         settings: (any ThrowingKeyedStoring<UpdateControllerSettings>),
         onProgressChange: @escaping (UpdateCycleProgress, (() -> Void)?) -> Void) {

        self.internalUserDecider = internalUserDecider
        self.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled
        self.settings = settings
        self.onProgressChange = onProgressChange
    }

    private func dismissCurrentUpdate() {
        onDismiss()
        pendingUpdateSince = .distantPast
    }

    /// Cancels the current update and dismisses any UI.
    ///
    /// User dismissal (via this method) still allows the update to install on quit because
    /// Sparkle preserves downloaded updates. Other cancellation reasons (settings changed,
    /// build expired) discard the update entirely.
    func cancelAndDismissCurrentUpdate() {
        dismissCurrentUpdate()
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
        onProgressChange(.updateCycleDidStart, nil)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        Logger.updates.log("Updater shown update found: (userInitiated:  \(state.userInitiated, privacy: .public), stage: \(state.stage.rawValue, privacy: .public))")
        sparkleUpdateState = state

        if appcastItem.isInformationOnlyUpdate {
            Logger.updates.log("Updater dismissed due to information only update")
            reply(.dismiss)
            return
        }

        onDismiss = {
            // Dismiss the update for the time being
            // If the update has been updated, it's kept till the next time an update is shown to the user
            // If the update is installing, it's also preserved after dismissing, and will also be installed after the app is terminated
            reply(.dismiss)
        }

        if !areAutomaticUpdatesEnabled {
            onProgressChange(.updateCycleDone(.pausedAtDownloadCheckpoint), { reply(.install) })
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

        let errorCode = (error as NSError).code

        // SUResumeAppcastError means the update cycle was cancelled during installation
        // which we don't want to treat as an error
        if errorCode != Int(Sparkle.SUError.resumeAppcastError.rawValue) {
            onProgressChange(.updaterError(error), nil)
        }

        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        onProgressChange(.downloadDidStart, nil)
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
        onProgressChange(.downloading(Double(bytesDownloaded) / Double(bytesToDownload)), nil)
    }

    func showDownloadDidStartExtractingUpdate() {
        onProgressChange(.extractionDidStart, nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        onProgressChange(.extracting(progress), nil)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        onDismiss = { [weak self] in
            // Cancel the current update that has begun installing and dismiss the update
            // This doesn't actually skip the update in the future (‽)
            reply(.skip)
            self?.onProgressChange(.updateCycleDone(.dismissingObsoleteUpdate), nil)
        }

        onProgressChange(.updateCycleDone(.pausedAtRestartCheckpoint), { reply(.install) })
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Logger.updates.info("Updater started the installation")
        onProgressChange(.installationDidStart, nil)

        if !applicationTerminated {
            Logger.updates.log("Updater re-sent a quit event")
            retryTerminatingApplication()
        }
    }

    /// Called after successful update installation.
    ///
    /// Records the timestamp for future time-since-update tracking. This callback happens
    /// AFTER successful installation, making it the authoritative source. Future update
    /// flows will use this to calculate `time_since_last_update_ms`.
    ///
    /// - Parameters:
    ///   - relaunched: Whether the app was relaunched
    ///   - acknowledgement: Callback to acknowledge completion
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        onProgressChange(.installing, nil)
        // Record successful update timestamp for future time-since-update tracking.
        // We do this here (not in WideEvent completion) because this callback happens
        // AFTER successful installation, making it the authoritative source.
        // Future update flows will use this to calculate time_since_last_update_ms.
        try? settings.set(Date(), for: \.lastSuccessfulUpdateDate)
        acknowledgement()
    }

    func showUpdateInFocus() {
        // no-op
    }

    func dismissUpdateInstallation() {
        onProgressChange(.updateCycleDone(.dismissedWithNoError), nil)
    }
}

#endif
