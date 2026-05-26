//
//  DuckPlayerPreferences.swift
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

import AppKit
import BrowserServicesKit
import Combine
import DuckPlayer
import Foundation
import PixelKit
import PrivacyConfig

protocol DuckPlayerPreferencesPersistor {
    /// The persistor hadles raw Bool values but each one translates into a DuckPlayerMode:
    /// nil = .alwaysAsk,  false = .disabled, true = .enabled
    /// DuckPlayerMode init takes a Bool and returns the corresponding mode
    var duckPlayerModeBool: Bool? { get set }
    var youtubeOverlayInteracted: Bool { get set }
    var youtubeOverlayAnyButtonPressed: Bool { get set }
    var duckPlayerAutoplay: Bool { get set }
    var duckPlayerOpenInNewTab: Bool { get set }
}

struct DuckPlayerPreferencesUserDefaultsPersistor: DuckPlayerPreferencesPersistor {

    @UserDefaultsWrapper(key: .duckPlayerMode, defaultValue: nil)
    var duckPlayerModeBool: Bool?

    @UserDefaultsWrapper(key: .youtubeOverlayInteracted, defaultValue: false)
    var youtubeOverlayInteracted: Bool

    @UserDefaultsWrapper(key: .youtubeOverlayButtonsUsed, defaultValue: false)
    var youtubeOverlayAnyButtonPressed: Bool

    @UserDefaultsWrapper(key: .duckPlayerAutoplay, defaultValue: true)
    var duckPlayerAutoplay: Bool

    @UserDefaultsWrapper(key: .duckPlayerOpenInNewTab, defaultValue: true)
    var duckPlayerOpenInNewTab: Bool
}

final class DuckPlayerPreferences: ObservableObject {

    /// Posted when `duckPlayerMode` is mutated outside the normal Settings path (e.g. the debug
    /// menu writing directly to UserDefaults). Subscribers re-read from the persistor so any open
    /// Settings pane bound to this `@Published` property refreshes.
    static let duckPlayerModeDidChangeNotification = Notification.Name("duckPlayerModeDidChange")

    private let internalUserDecider: InternalUserDecider
    private let duckPlayerContingencyHandler: DuckPlayerContingencyHandler
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    @Published
    var duckPlayerMode: DuckPlayerMode {
        didSet {
            guard !isApplyingRolloutDefault, !isHandlingExternalChange else { return }
            persistor.duckPlayerModeBool = duckPlayerMode.boolValue
        }
    }

    private var isApplyingRolloutDefault = false
    private var isHandlingExternalChange = false

    @Published
    var duckPlayerAutoplay: Bool {
        didSet {
            persistor.duckPlayerAutoplay = duckPlayerAutoplay
            if duckPlayerAutoplay {
                PixelKit.fire(GeneralPixel.duckPlayerAutoplaySettingsOn, doNotEnforcePrefix: true)
            } else {
                PixelKit.fire(GeneralPixel.duckPlayerAutoplaySettingsOff, doNotEnforcePrefix: true)
            }
        }
    }

    @Published
    var duckPlayerOpenInNewTab: Bool {
        didSet {
            persistor.duckPlayerOpenInNewTab = duckPlayerOpenInNewTab
            if duckPlayerOpenInNewTab {
                PixelKit.fire(GeneralPixel.duckPlayerNewTabSettingsOn, doNotEnforcePrefix: true)
            } else {
                PixelKit.fire(GeneralPixel.duckPlayerNewTabSettingsOff, doNotEnforcePrefix: true)
            }
        }
    }

    var shouldDisplayAutoPlaySettings: Bool {
        privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(DuckPlayerSubfeature.autoplay) || internalUserDecider.isInternalUser
    }

    var isOpenInNewTabSettingsAvailable: Bool {
        privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(DuckPlayerSubfeature.openInNewTab) || internalUserDecider.isInternalUser
    }

    var isNewTabSettingsAvailable: Bool {
        duckPlayerMode != .disabled
    }

    var youtubeOverlayInteracted: Bool {
        didSet {
            persistor.youtubeOverlayInteracted = youtubeOverlayInteracted
        }
    }

    var youtubeOverlayAnyButtonPressed: Bool {
        didSet {
            persistor.youtubeOverlayAnyButtonPressed = youtubeOverlayAnyButtonPressed
        }
    }

    var shouldDisplayContingencyMessage: Bool {
        duckPlayerContingencyHandler.shouldDisplayContingencyMessage
    }

    func reset() {
        youtubeOverlayAnyButtonPressed = false
        youtubeOverlayInteracted = false
        duckPlayerMode = .alwaysAsk
        duckPlayerOpenInNewTab = true
        duckPlayerAutoplay = true
    }

    @MainActor
    func openLearnMoreContingencyURL() {
        guard let url = duckPlayerContingencyHandler.learnMoreURL else { return }
        PixelKit.fire(GeneralPixel.duckPlayerContingencyLearnMoreClicked, doNotEnforcePrefix: true)
        Application.appDelegate.windowControllersManager.show(url: url, source: .ui, newTab: true)
    }

    init(persistor: DuckPlayerPreferencesPersistor = DuckPlayerPreferencesUserDefaultsPersistor(),
         privacyConfigurationManager: PrivacyConfigurationManaging = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager,
         internalUserDecider: InternalUserDecider = NSApp.delegateTyped.internalUserDecider,
         featureFlagger: FeatureFlagger? = nil) {
        self.persistor = persistor
        self.featureFlagger = featureFlagger
        if let stored = persistor.duckPlayerModeBool {
            duckPlayerMode = .init(stored)
        } else {
            duckPlayerMode = featureFlagger?.isFeatureOn(.adBlockingExtensionEnabledByDefault) == true ? .disabled : .alwaysAsk
        }
        youtubeOverlayInteracted = persistor.youtubeOverlayInteracted
        youtubeOverlayAnyButtonPressed = persistor.youtubeOverlayAnyButtonPressed
        duckPlayerAutoplay = persistor.duckPlayerAutoplay
        duckPlayerOpenInNewTab = persistor.duckPlayerOpenInNewTab
        self.privacyConfigurationManager = privacyConfigurationManager
        self.internalUserDecider = internalUserDecider
        self.duckPlayerContingencyHandler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: privacyConfigurationManager)

        featureFlagger?.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshDefaultModeIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: Self.duckPlayerModeDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDuckPlayerModeFromStore()
            }
            .store(in: &cancellables)
    }

    private func refreshDefaultModeIfNeeded() {
        guard persistor.duckPlayerModeBool == nil else { return }
        let resolved: DuckPlayerMode = featureFlagger?.isFeatureOn(.adBlockingExtensionEnabledByDefault) == true ? .disabled : .alwaysAsk
        guard resolved != duckPlayerMode else { return }
        isApplyingRolloutDefault = true
        duckPlayerMode = resolved
        isApplyingRolloutDefault = false
    }

    private func refreshDuckPlayerModeFromStore() {
        let resolved = DuckPlayerMode(persistor.duckPlayerModeBool)
        guard resolved != duckPlayerMode else { return }
        isHandlingExternalChange = true
        duckPlayerMode = resolved
        isHandlingExternalChange = false
    }

    private var persistor: DuckPlayerPreferencesPersistor
    private let featureFlagger: FeatureFlagger?
    private var cancellables: Set<AnyCancellable> = []
}
