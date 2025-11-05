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

@available(iOS 18.0, *)
protocol AutofillExtensionSettingsViewModelDelegate: AnyObject {
    func autofillExtensionSettingsViewModel(_ viewModel: AutofillExtensionSettingsViewModel, authDisabled: Bool)
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
    weak var delegate: (any AutofillExtensionSettingsViewModelDelegate)?

    @Published var isExtensionEnabled: Bool = false
    @Published var isShowingActivationView: Bool = false
    @Published private(set) var isEnableRequestThrottled: Bool = false


    init(credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
         settingsHelper: any AutofillExtensionSettingsHelping = DefaultAutofillExtensionSettingsHelper(),
         enableRetryThrottleDuration: TimeInterval = Constants.enableRetryThrottleDuration) {
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
        if isEnableRequestThrottled {
            if let remaining = remainingEnableRequestThrottleInterval, remaining > 0 {
                await disableExtension()
                return
            }
            clearEnableRequestThrottle()
        }

        delegate?.autofillExtensionSettingsViewModel(self, authDisabled: true)
        let result = await settingsHelper.requestToTurnOnCredentialProviderExtension()
        Logger.autofill.debug("Extension enabled result: \(result)")
        await updateExtensionStatus()
        if isExtensionEnabled {
            isShowingActivationView = true
        } else {
            if result {
                await disableExtension()
            }
            startEnableRequestThrottle()
            isShowingActivationView = false
        }
        delegate?.autofillExtensionSettingsViewModel(self, authDisabled: false)
    }

    func disableExtension() async {
        do {
            delegate?.autofillExtensionSettingsViewModel(self, authDisabled: true)
            try await settingsHelper.openCredentialProviderAppSettings()
        } catch {
            delegate?.autofillExtensionSettingsViewModel(self, authDisabled: false)
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

        enableRetryTimer = Timer.scheduledTimer(withTimeInterval: enableRetryThrottleDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.clearEnableRequestThrottle()
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
