//
//  QuitSurveyDecider.swift
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

import Common
import FeatureFlags
import Foundation
import os.log
import Persistence
import PrivacyConfig
import AppKit

/// Protocol for deciding whether to show the quit survey.
@MainActor
protocol QuitSurveyDeciding {
    /// Whether the quit survey should be shown based on all conditions.
    var shouldShowQuitSurvey: Bool { get }

    /// Marks that the quit survey has been shown (user has quit once).
    func markQuitSurveyShown()
}

/// Decider that aggregates multiple conditions to determine if the quit survey should be shown.
///
/// The quit survey is shown when ALL of the following conditions are met:
/// 1. The feature flag is enabled
/// 2. No other quit dialogs will be shown (auto-clear warning or active downloads)
/// 3. User is within 0-3 days of first launch (new user)
/// 4. This is the user's first quit
/// 5. User is not reinstalling (reinstalling users are not considered new users)
@MainActor
final class QuitSurveyDecider: QuitSurveyDeciding {

    // MARK: - Constants

    /// The quit survey is shown to users within 0-3 days of first launch
    private static let newUserThresholdDays: TimeInterval = 3

    // MARK: - Dependencies

    private let featureFlagger: FeatureFlagger
    private let dataClearingPreferences: DataClearingPreferences
    private let downloadManager: FileDownloadManagerProtocol
    private let installDate: Date
    private var persistor: QuitSurveyPersistor
    private let reinstallUserDetection: ReinstallingUserDetecting
    private let dateProvider: () -> Date

    // MARK: - Initialization

    init(
        featureFlagger: FeatureFlagger,
        dataClearingPreferences: DataClearingPreferences,
        downloadManager: FileDownloadManagerProtocol,
        installDate: Date,
        persistor: QuitSurveyPersistor,
        reinstallUserDetection: ReinstallingUserDetecting,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.featureFlagger = featureFlagger
        self.dataClearingPreferences = dataClearingPreferences
        self.downloadManager = downloadManager
        self.installDate = installDate
        self.persistor = persistor
        self.reinstallUserDetection = reinstallUserDetection
        self.dateProvider = dateProvider
    }

    // MARK: - QuitSurveyDeciding

    var shouldShowQuitSurvey: Bool {
        // Never show during automation sessions (WebDriver or UI Tests)
        guard !LaunchOptionsHandler().isAutomationSession else { return false }

        // Condition 1: Feature flag is enabled
        guard featureFlagger.isFeatureOn(.firstTimeQuitSurvey) else { return false }

        // Only for debugging purposes when the debug flag is turned on in the Debug menu.
        // Only works for internal users.
        if persistor.alwaysShowQuitSurvey {
            return true
        }

        // Condition 2: No other quit dialogs will be shown
        let willShowAutoClearDialog = dataClearingPreferences.isAutoClearEnabled && dataClearingPreferences.isWarnBeforeClearingEnabled
        let willShowDownloadsDialog = downloadManager.downloads.contains { $0.state.isDownloading }
        let noOtherDialogsWillShow = !willShowAutoClearDialog && !willShowDownloadsDialog

        // Condition 3: User is within 0-3 days of install
        let isNewUser = isWithinNewUserThreshold

        // Condition 4: First quit
        let isFirstQuit = !persistor.hasQuitAppBefore

        // Condition 5: User is not reinstalling (reinstalling users are not considered new users)
        let isNotReinstallingUser = !reinstallUserDetection.isReinstallingUser

        return noOtherDialogsWillShow
            && isNewUser
            && isFirstQuit
            && isNotReinstallingUser
    }

    private var isWithinNewUserThreshold: Bool {
        let thresholdDate = dateProvider().addingTimeInterval(-Self.newUserThresholdDays * 24 * 60 * 60)
        return installDate >= thresholdDate
    }

    func markQuitSurveyShown() {
        persistor.hasQuitAppBefore = true
    }
}

// MARK: - App Termination Decider

/// Handles quit survey presentation during app termination.
@MainActor
struct QuitSurveyAppTerminationDecider {
    let featureFlagger: FeatureFlagger
    let dataClearingPreferences: DataClearingPreferences
    let downloadManager: FileDownloadManagerProtocol
    let installDate: Date?
    let persistor: QuitSurveyPersistor
    let reinstallUserDetection: ReinstallingUserDetecting
    let showQuitSurvey: @MainActor () async -> Void
}

// MARK: - ApplicationTerminationDecider

extension QuitSurveyAppTerminationDecider: ApplicationTerminationDecider {
    func shouldTerminate(isAsync: Bool) -> TerminationQuery {
        let decider = QuitSurveyDecider(
            featureFlagger: featureFlagger,
            dataClearingPreferences: dataClearingPreferences,
            downloadManager: downloadManager,
            installDate: installDate ?? Date.distantPast,
            persistor: persistor,
            reinstallUserDetection: reinstallUserDetection
        )

        guard decider.shouldShowQuitSurvey else {
            return .sync(.next)
        }

        decider.markQuitSurveyShown()

        // Show survey and wait for completion
        return .async(Task { @MainActor in
            await showQuitSurvey()
            // Survey completed - user chose to quit
            return .next
        })
    }
}

// MARK: - Persistor

protocol QuitSurveyPersistor {
    var hasQuitAppBefore: Bool { get set }

    /// Stores the reasons string from the quit survey for the return user pixel.
    /// When set, the return user pixel should be fired on next app launch.
    /// After firing the pixel, this should be cleared to ensure the pixel is only fired once.
    var pendingReturnUserReasons: String? { get set }

    /// Only for internal users, triggered from the debug menu
    var alwaysShowQuitSurvey: Bool { get set }
}

final class QuitSurveyUserDefaultsPersistor: QuitSurveyPersistor {

    private enum Key: String {
        case hasQuitAppBefore = "quit-survey.has-quit-app-before"
        case pendingReturnUserReasons = "quit-survey.pending-return-user-reasons"
        case alwaysShowQuitSurvey = "quit-survey.always-show-quit-survey"
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let internalUserDecider: InternalUserDecider

    init(keyValueStore: ThrowingKeyValueStoring,
         internalUserDecider: InternalUserDecider = NSApp.delegateTyped.internalUserDecider) {
        self.keyValueStore = keyValueStore
        self.internalUserDecider = internalUserDecider
    }

    var hasQuitAppBefore: Bool {
        get {
            do {
                return try keyValueStore.object(forKey: Key.hasQuitAppBefore.rawValue) as? Bool ?? false
            } catch {
                Logger.general.error("Failed to read hasQuitAppBefore from keyValueStore: \(error)")
                return false
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: Key.hasQuitAppBefore.rawValue)
            } catch {
                Logger.general.error("Failed to write hasQuitAppBefore to keyValueStore: \(error)")
            }
        }
    }

    var pendingReturnUserReasons: String? {
        get {
            do {
                return try keyValueStore.object(forKey: Key.pendingReturnUserReasons.rawValue) as? String
            } catch {
                Logger.general.error("Failed to read pendingReturnUserReasons from keyValueStore: \(error)")
                return nil
            }
        }
        set {
            do {
                if let value = newValue {
                    try keyValueStore.set(value, forKey: Key.pendingReturnUserReasons.rawValue)
                } else {
                    try keyValueStore.removeObject(forKey: Key.pendingReturnUserReasons.rawValue)
                }
            } catch {
                Logger.general.error("Failed to write pendingReturnUserReasons to keyValueStore: \(error)")
            }
        }
    }

    var alwaysShowQuitSurvey: Bool {
        get {
            if !internalUserDecider.isInternalUser {
                return false
            }

            do {
                return try keyValueStore.object(forKey: Key.alwaysShowQuitSurvey.rawValue) as? Bool ?? false
            } catch {
                Logger.general.error("Failed to read hasQuitAppBefore from keyValueStore: \(error)")
                return false
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: Key.alwaysShowQuitSurvey.rawValue)
            } catch {
                Logger.general.error("Failed to write hasQuitAppBefore to keyValueStore: \(error)")
            }
        }
    }

}
