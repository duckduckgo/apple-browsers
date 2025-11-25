//
//  AutofillExtensionEnableCoordinator.swift
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
import Core
import BrowserServicesKit

@available(iOS 18.0, *)
protocol AutofillExtensionEnableCoordinatorDelegate: AnyObject {
    @MainActor
    func autofillExtensionEnableCoordinator(_ coordinator: AutofillExtensionEnableCoordinator, shouldDisableAuth: Bool)
}

@available(iOS 18.0, *)
enum AutofillExtensionEnableResult {
    case success
    case throttled
    case cancelled
    case failed
}

@available(iOS 18.0, *)
@MainActor
final class AutofillExtensionEnableCoordinator {

    private enum Constants {
        static let enableRetryThrottleDuration: TimeInterval = 10
    }

    private let credentialStore: ASCredentialIdentityStoring
    private let settingsHelper: any AutofillExtensionSettingsHelping
    private let enableRetryThrottleDuration: TimeInterval
    private let pixelSource: String
    private var throttleExpiresAt: Date?
    private var enableRetryTimer: Timer?

    weak var delegate: (any AutofillExtensionEnableCoordinatorDelegate)?

    private(set) var isEnableRequestThrottled: Bool = false

    init(source: String,
         credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
         settingsHelper: any AutofillExtensionSettingsHelping = DefaultAutofillExtensionSettingsHelper(),
         enableRetryThrottleDuration: TimeInterval = Constants.enableRetryThrottleDuration) {
        self.pixelSource = source
        self.credentialStore = credentialStore
        self.settingsHelper = settingsHelper
        self.enableRetryThrottleDuration = enableRetryThrottleDuration
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

    func enableExtension() async -> AutofillExtensionEnableResult {
        Pixel.fire(pixel: .autofillExtensionSettingsTurnOnTapped,
                   withAdditionalParameters: [PixelParameters.source: pixelSource])

        // Check throttle state
        if isEnableRequestThrottled {
            if let remaining = remainingEnableRequestThrottleInterval, remaining > 0 {
                // Still throttled - redirect to settings
                delegate?.autofillExtensionEnableCoordinator(self, shouldDisableAuth: true)
                try? await settingsHelper.openCredentialProviderAppSettings()
                Pixel.fire(pixel: .autofillExtensionSettingsTurnOnThrottled,
                           withAdditionalParameters: [PixelParameters.source: pixelSource])
                return .throttled
            }
            // Throttle expired
            clearEnableRequestThrottle()
        }

        // System prompts trigger authentication on passwords screen, so disabling observers temporarily
        delegate?.autofillExtensionEnableCoordinator(self, shouldDisableAuth: true)

        let userChoseToEnable = await settingsHelper.requestToTurnOnCredentialProviderExtension()

        guard userChoseToEnable else {
            // User chose "Not Now" - throttle future requests
            startEnableRequestThrottle()
            delegate?.autofillExtensionEnableCoordinator(self, shouldDisableAuth: false)
            Pixel.fire(pixel: .autofillExtensionSettingsTurnOnCancelled,
                       withAdditionalParameters: [PixelParameters.source: pixelSource])
            return .cancelled
        }

        // User chose to enable - verify the result
        let state = await credentialStore.state()
        if state.isEnabled {
            delegate?.autofillExtensionEnableCoordinator(self, shouldDisableAuth: false)
            Pixel.fire(pixel: .autofillExtensionSettingsTurnOnSuccess,
                       withAdditionalParameters: [PixelParameters.source: pixelSource])
            return .success
        } else {
            // User chose to enable but extension not enabled - guide user to settings
            try? await settingsHelper.openCredentialProviderAppSettings()
            startEnableRequestThrottle()
            Pixel.fire(pixel: .autofillExtensionSettingsTurnOnFailed,
                       withAdditionalParameters: [PixelParameters.source: pixelSource])
            return .failed
        }
    }

    func updateExtensionStatus() async -> Bool {
        let state = await credentialStore.state()
        return state.isEnabled
    }

    // MARK: - Throttle Management

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

    func clearEnableRequestThrottle() {
        isEnableRequestThrottled = false
        throttleExpiresAt = nil
        invalidateEnableRetryTimer()
    }

    func openSettings() async throws {
        try await settingsHelper.openCredentialProviderAppSettings()
        Pixel.fire(pixel: .autofillExtensionSettingsTurnOffTapped, withAdditionalParameters: [PixelParameters.source: pixelSource])
    }

    private func invalidateEnableRetryTimer() {
        enableRetryTimer?.invalidate()
        enableRetryTimer = nil
    }
}
