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

import BrowserServicesKit
import Common
import FeatureFlags
import Foundation
import os.log
import Persistence

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
/// 3. User is within 14 days of first launch (new user)
/// 4. This is the user's first quit
/// 5. User is not reinstalling (reinstalling users are not considered new users)
@MainActor
final class QuitSurveyDecider: QuitSurveyDeciding {

    // MARK: - Constants

    private static let newUserThresholdDays: TimeInterval = 14

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
        // Condition 1: Feature flag is enabled
        guard featureFlagger.isFeatureOn(.firstTimeQuitSurvey) else { return false }

        // Condition 2: No other quit dialogs will be shown
        let willShowAutoClearDialog = dataClearingPreferences.isAutoClearEnabled && dataClearingPreferences.isWarnBeforeClearingEnabled
        let willShowDownloadsDialog = downloadManager.downloads.contains { $0.state.isDownloading }
        let noOtherDialogsWillShow = !willShowAutoClearDialog && !willShowDownloadsDialog

        // Condition 3: User is within 14 days of install
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

// MARK: - Persistor

protocol QuitSurveyPersistor {
    var hasQuitAppBefore: Bool { get set }
}

final class QuitSurveyUserDefaultsPersistor: QuitSurveyPersistor {

    private enum Key: String {
        case hasQuitAppBefore = "quit-survey.has-quit-app-before"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
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
}
