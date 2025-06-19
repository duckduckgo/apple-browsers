//
//  AboutPreferences.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import SwiftUI
import Common
import Combine
import BrowserServicesKit
import FeatureFlags

final class AboutPreferences: ObservableObject, PreferencesTabOpening {

    static let shared = AboutPreferences(internalUserDecider: NSApp.delegateTyped.internalUserDecider)

    private let internalUserDecider: InternalUserDecider
    @Published var isInternalUser: Bool
    @Published var featureFlagOverrideToggle = false
    private var internalUserCancellable: AnyCancellable?
    private let featureFlagger: FeatureFlagger
    let supportedOSChecker: SupportedOSChecking
    private var cancellables = Set<AnyCancellable>()

    private init(internalUserDecider: InternalUserDecider,
                 featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
                 supportedOSChecker: SupportedOSChecking? = nil) {

        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
        self.isInternalUser = internalUserDecider.isInternalUser
        self.supportedOSChecker = supportedOSChecker ?? SupportedOSChecker(featureFlagger: featureFlagger)
        self.internalUserCancellable = internalUserDecider.isInternalUserPublisher
            .sink { [weak self] in self?.isInternalUser = $0 }

        subscribeToFeatureFlagOverrideChanges()
    }

    private func subscribeToFeatureFlagOverrideChanges() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.flagDidChangePublisher
            .filter { $0.0.category == .osSupportWarnings }
            .sink { [weak self] _ in
                self?.featureFlagOverrideToggle.toggle()
            }
            .store(in: &cancellables)
    }

#if SPARKLE
    var useLegacyAutoRestartLogic: Bool {
        !featureFlagger.isFeatureOn(.updatesWontAutomaticallyRestartApp)
    }

    var mustCheckForUpdatesBeforeUserCanTakeAction: Bool {
        !useLegacyAutoRestartLogic
    }

    @Published var updateState = UpdateState.upToDate

    var updateController: UpdateControllerProtocol? {
        return Application.appDelegate.updateController
    }

    var areAutomaticUpdatesEnabled: Bool {
        get {
            return updateController?.areAutomaticUpdatesEnabled ?? false
        }

        set {
            updateController?.areAutomaticUpdatesEnabled = newValue
        }
    }

    var lastUpdateCheckDate: Date? {
        updateController?.lastUpdateCheckDate
    }

    private var subscribed = false

    private var hasPendingUpdate: Bool {
        updateController?.hasPendingUpdate == true
    }

    private var isAtRestartCheckpoint: Bool {
        updateController?.isAtRestartCheckpoint ?? false
    }

    struct UpdateButtonConfiguration {
        let title: String
        let action: () -> Void
        let enabled: Bool
    }

    var updateButtonConfiguration: UpdateButtonConfiguration {
        switch updateState {
        case .upToDate:
            return UpdateButtonConfiguration(
                title: UserText.checkForUpdate,
                action: { [weak self] in
                    self?.checkForUpdate(userInitiated: true)
                },
                enabled: true)
        case .updateCycle(let progress):
            if isAtRestartCheckpoint {
                return UpdateButtonConfiguration(
                    title: UserText.restartToUpdate,
                    action: runUpdate,
                    enabled: true)
            } else if hasPendingUpdate {
                return UpdateButtonConfiguration(
                    title: UserText.runUpdate,
                    action: runUpdate,
                    enabled: true)
            } else if progress.isFailed {
                return UpdateButtonConfiguration(
                    title: UserText.retryUpdate,
                    action: { [weak self] in
                        self?.checkForUpdate(userInitiated: true)
                    },
                    enabled: true)
            } else {
                return UpdateButtonConfiguration(
                    title: UserText.checkForUpdate,
                    action: { [weak self] in
                        self?.checkForUpdate(userInitiated: true)
                    },
                    enabled: false)
            }
        }
    }

#endif

    let appVersion = AppVersion()

    private var cancellable: AnyCancellable?

    let displayableAboutURL: String = URL.aboutDuckDuckGo
        .toString(decodePunycode: false, dropScheme: true, dropTrailingSlash: false)

    var osSupportWarning: OSSupportWarning? {
        supportedOSChecker.supportWarning
    }

#if FEEDBACK
    @MainActor
    func openFeedbackForm() {
        NSApp.delegateTyped.openFeedback(nil)
    }
#endif

    func copy(_ value: String) {
        NSPasteboard.general.copy(value)
    }

#if SPARKLE
    func checkForUpdate(userInitiated: Bool) {
        if userInitiated {
            updateController?.checkForUpdateSkippingRollout()
        } else {
            updateController?.checkForUpdateRespectingRollout()
        }
    }

    func runUpdate() {
        updateController?.runUpdate()
    }

    func subscribeToUpdateInfoIfNeeded() {
        guard let updateController, !subscribed else { return }

        cancellable = updateController.latestUpdatePublisher
            .combineLatest(updateController.updateProgressPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshUpdateState()
            }

        subscribed = true

        refreshUpdateState()
    }

    private func refreshUpdateState() {
        guard let updateController else { return }
        updateState = UpdateState(from: updateController.latestUpdate, progress: updateController.updateProgress)
    }
#endif

}
