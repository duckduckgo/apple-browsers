//
//  AutofillExtensionSettingsViewModel.swift
//  DuckDuckGo
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

import Foundation
import AuthenticationServices
import BrowserServicesKit
import Core

@available(iOS 18.0, *)
protocol AutofillExtensionSettingsViewModelDelegate: AnyObject {
    func autofillExtensionSettingsViewModel(_ viewModel: AutofillExtensionSettingsViewModel, shouldDisableAuth: Bool)
}

@available(iOS 18.0, *)
protocol AutofillExtensionSettingsHelping {
    func requestToTurnOnCredentialProviderExtension() async -> Bool
    func openCredentialProviderAppSettings() async throws
}

@available(iOS 18.0, *)
struct DefaultAutofillExtensionSettingsHelper: AutofillExtensionSettingsHelping {
    func requestToTurnOnCredentialProviderExtension() async -> Bool {
        await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
    }

    func openCredentialProviderAppSettings() async throws {
        try await ASSettingsHelper.openCredentialProviderAppSettings()
    }
}

@available(iOS 18.0, *)
@MainActor
final class AutofillExtensionSettingsViewModel: ObservableObject {

    private enum Constants {
        static let enableRetryThrottleDuration: TimeInterval = 10
    }

    private let credentialStore: ASCredentialIdentityStoring
    private let settingsHelper: any AutofillExtensionSettingsHelping
    private let enableRetryThrottleDuration: TimeInterval
    private var throttleExpiresAt: Date?
    private var enableRetryTimer: Timer?
    private let pixelSource: String
    weak var delegate: (any AutofillExtensionSettingsViewModelDelegate)?

    @Published var isExtensionEnabled: Bool = false
    @Published var isShowingActivationView: Bool = false
    @Published private(set) var isEnableRequestThrottled: Bool = false

    init(source: AutofillExtensionSettingsViewController.Source? = nil,
         credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
         settingsHelper: any AutofillExtensionSettingsHelping = DefaultAutofillExtensionSettingsHelper(),
         enableRetryThrottleDuration: TimeInterval = Constants.enableRetryThrottleDuration) {
        self.pixelSource = source?.rawValue ?? ""
        self.credentialStore = credentialStore
        self.settingsHelper = settingsHelper
        self.enableRetryThrottleDuration = enableRetryThrottleDuration

        Task { await updateExtensionStatus() }
    }

    func updateExtensionStatus() async {
        let state = await credentialStore.state()
        isExtensionEnabled = state.isEnabled
    }

    func enableExtension() async {
        Pixel.fire(pixel: .autofillExtensionSettingsTurnOnTapped(source: pixelSource),
                   withAdditionalParameters: [PixelParameters.source: pixelSource])

        if isEnableRequestThrottled {
            if let remaining = remainingEnableRequestThrottleInterval, remaining > 0 {
                // Still throttled - redirect to settings instead
                await openSettings()
                Pixel.fire(pixel: .autofillExtensionSettingsTurnOnThrottled(source: pixelSource),
                           withAdditionalParameters: [PixelParameters.source: pixelSource])
                return
            }
            // Throttle expired
            clearEnableRequestThrottle()
        }

        // System prompts trigger authentication on passwords screen, so disabling observers temporarily
        delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: true)
        defer {
            delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: false)
        }

        let userChoseToEnable = await settingsHelper.requestToTurnOnCredentialProviderExtension()
        Logger.autofill.debug("User chose to enable: \(userChoseToEnable)")

        guard userChoseToEnable else {
            // User chose "Not Now" - throttle future requests
            startEnableRequestThrottle()
            Pixel.fire(pixel: .autofillExtensionSettingsTurnOnCancelled(source: pixelSource),
                       withAdditionalParameters: [PixelParameters.source: pixelSource])
            return
        }

        // User chose to enable - verify the result
        await handleEnableAttempt()
    }

    private func handleEnableAttempt() async {
        await updateExtensionStatus()

        if isExtensionEnabled {
            // Success - show activation confirmation
            isShowingActivationView = true

            Pixel.fire(pixel: .autofillExtensionSettingsTurnOnSuccess(source: pixelSource),
                       withAdditionalParameters: [PixelParameters.source: pixelSource])
        } else {
            // User chose to enable but extension not enabled - guide user to settings
            await openSettings()
            startEnableRequestThrottle()
            isShowingActivationView = false

            Pixel.fire(pixel: .autofillExtensionSettingsTurnOnFailed(source: pixelSource),
                       withAdditionalParameters: [PixelParameters.source: pixelSource])
        }
    }

    func disableExtension() async {
        await openSettings()

        Pixel.fire(pixel: .autofillExtensionSettingsTurnOffTapped(source: pixelSource),
                   withAdditionalParameters: [PixelParameters.source: pixelSource])
    }

    private func openSettings() async {
        do {
            delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: true)
            try await settingsHelper.openCredentialProviderAppSettings()
        } catch {
            delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: false)
            Logger.autofill.error("Failed to open credential provider settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    var remainingEnableRequestThrottleInterval: TimeInterval? {
        guard let throttleExpiresAt else {
            return nil
        }
        let remaining = throttleExpiresAt.timeIntervalSinceNow
        if remaining <= 0 {
            clearEnableRequestThrottle()
            return nil
        }
        return remaining
    }

    private func startEnableRequestThrottle() {
        invalidateEnableRetryTimer()
        isEnableRequestThrottled = true
        throttleExpiresAt = Date().addingTimeInterval(enableRetryThrottleDuration)

        enableRetryTimer = Timer.scheduledTimer(withTimeInterval: enableRetryThrottleDuration, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.clearEnableRequestThrottle()
            }
        }
    }

    private func clearEnableRequestThrottle() {
        isEnableRequestThrottled = false
        throttleExpiresAt = nil
        invalidateEnableRetryTimer()
    }

    private func invalidateEnableRetryTimer() {
        enableRetryTimer?.invalidate()
        enableRetryTimer = nil
    }
}
