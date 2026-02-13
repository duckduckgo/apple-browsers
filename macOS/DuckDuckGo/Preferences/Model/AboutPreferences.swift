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
import FeatureFlags
import os.log
import Persistence
import PixelKit
import PrivacyConfig

final class AboutPreferences: ObservableObject, PreferencesTabOpening {

    let appVersionModel: AppVersionModel
    @Published var featureFlagOverrideToggle = false
    private let featureFlagger: FeatureFlagger
    let windowControllersManager: WindowControllersManagerProtocol
    let supportedOSChecker: SupportedOSChecking
    private var cancellables = Set<AnyCancellable>()
    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>

    init(internalUserDecider: InternalUserDecider,
         featureFlagger: FeatureFlagger,
         windowControllersManager: WindowControllersManagerProtocol,
         keyValueStore: ThrowingKeyValueStoring,
         supportedOSChecker: SupportedOSChecking? = nil) {

        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager
        self.settings = keyValueStore.throwingKeyedStoring()
        self.appVersionModel = .init(appVersion: AppVersion(), internalUserDecider: internalUserDecider)
        self.supportedOSChecker = supportedOSChecker ?? SupportedOSChecker(featureFlagger: featureFlagger)
        internalUserDecider.isInternalUserPublisher
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

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

    var useLegacyAutoRestartLogic: Bool {
        #if SPARKLE
        (updateController as? any SparkleUpdateControllerProtocol)?.useLegacyAutoRestartLogic ?? false
        #else
        false
        #endif
    }

    var shouldShowUpdateStatus: Bool {
        #if SPARKLE
        // For Sparkle builds: always show update status regardless of feature flag
        return true
        #else
        // For App Store builds: only show update status if feature flag is enabled
        return featureFlagger.isFeatureOn(.appStoreUpdateFlow)
        #endif
    }

    var mustCheckForUpdatesBeforeUserCanTakeAction: Bool {
        !useLegacyAutoRestartLogic
    }

    @Published var updateState = UpdateState.upToDate

    func runUpdate() {
        // Track Update DuckDuckGo button tapped in About preferences
        PixelKit.fire(UpdateFlowPixels.updateDuckDuckGoButtonTapped)
        updateController?.runUpdate()
    }

    var updateController: UpdateController? {
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
            #if SPARKLE
            if isAtRestartCheckpoint {
                return UpdateButtonConfiguration(
                    title: UserText.restartToUpdate,
                    action: runUpdate,
                    enabled: true)
            }
            #endif
            if hasPendingUpdate {
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
        let latestUpdate = updateController.latestUpdate
        let progress = updateController.updateProgress
        Logger.updates.log("🔍 AboutPreferences.refreshUpdateState: latestUpdate=\(latestUpdate != nil, privacy: .public), progress=\(progress, privacy: .public), hasPendingUpdate=\(updateController.hasPendingUpdate, privacy: .public)")
        updateState = UpdateState(from: latestUpdate, progress: progress)
        Logger.updates.log("🔍 AboutPreferences.refreshUpdateState: updateState=\(String(describing: self.updateState), privacy: .public)")
    }

#if SPARKLE
    private var isAtRestartCheckpoint: Bool {
        guard let updateController = updateController as? any SparkleUpdateControllerProtocol else { return false }
        return updateController.isAtRestartCheckpoint
    }
#endif

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
    var customFeedURL: String? {
        return try? settings.debugSparkleCustomFeedURL
    }
#endif

    private var cancellable: AnyCancellable?

    let displayableAboutURL: String = URL.aboutDuckDuckGo
        .toString(decodePunycode: false, dropScheme: true, dropTrailingSlash: false)

    var osSupportWarning: OSSupportWarning? {
        supportedOSChecker.supportWarning
    }

    @MainActor
    func openFeedbackForm() {
        NSApp.delegateTyped.openFeedback(nil)
    }

    func copy(_ value: String) {
        NSPasteboard.general.copy(value)
    }

    @MainActor func checkForAppStoreUpdate() {
        PixelKit.fire(UpdateFlowPixels.checkForUpdate(source: .aboutMenu))
        NSWorkspace.shared.open(.appStore)
    }

    func checkForUpdate(userInitiated: Bool) {
        if userInitiated {
            updateController?.checkForUpdateSkippingRollout()
        } else {
            #if SPARKLE
            guard let updateController = updateController as? any SparkleUpdateControllerProtocol else { return }
            updateController.checkForUpdateRespectingRollout()
            #endif
        }
    }
}
