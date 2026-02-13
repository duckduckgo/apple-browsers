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
    @MainActor
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

    private let coordinator: AutofillExtensionEnableCoordinator
    private let source: String
    private let experimentPixels: AutofillOnboardingExperimentPixelFiring
    weak var delegate: (any AutofillExtensionSettingsViewModelDelegate)?

    @Published var isExtensionEnabled: Bool = false
    @Published var isShowingActivationView: Bool = false
    /// Temporary flag used to ensure we don't fire pixel on initial state discovery
    private var hasCompletedInitialLoad: Bool = false

    var isEnableRequestThrottled: Bool {
        coordinator.isEnableRequestThrottled
    }

    init(source: String,
         coordinator: AutofillExtensionEnableCoordinator? = nil,
         experimentPixels: AutofillOnboardingExperimentPixelFiring = AutofillOnboardingExperimentPixelReporter()) {
        self.source = source
        self.coordinator = coordinator ?? AutofillExtensionEnableCoordinator(source: source)
        self.experimentPixels = experimentPixels
        self.coordinator.delegate = self
        Task { await updateExtensionStatus() }
    }

    func updateExtensionStatus() async {
        let wasEnabled = isExtensionEnabled
        isExtensionEnabled = await coordinator.updateExtensionStatus()

        if hasCompletedInitialLoad && wasEnabled != isExtensionEnabled {
            experimentPixels.fireAutofillInOtherAppsEnabled(isExtensionEnabled)
        }
        hasCompletedInitialLoad = true
    }

    func enableExtension() async {
        let result = await coordinator.enableExtension()

        switch result {
        case .success:
            isExtensionEnabled = true
            isShowingActivationView = true
            experimentPixels.fireAutofillInOtherAppsEnabled(true)
        case .throttled, .cancelled, .failed:
            isExtensionEnabled = false
            isShowingActivationView = false
        }
    }

    func disableExtension() async {
        do {
            delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: true)
            try await coordinator.openSettings()
        } catch {
            delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: false)
            Logger.autofill.error("Failed to open credential provider settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@available(iOS 18.0, *)
extension AutofillExtensionSettingsViewModel: AutofillExtensionEnableCoordinatorDelegate {
    func autofillExtensionEnableCoordinator(_ coordinator: AutofillExtensionEnableCoordinator, shouldDisableAuth: Bool) {
        delegate?.autofillExtensionSettingsViewModel(self, shouldDisableAuth: shouldDisableAuth)
    }
}
