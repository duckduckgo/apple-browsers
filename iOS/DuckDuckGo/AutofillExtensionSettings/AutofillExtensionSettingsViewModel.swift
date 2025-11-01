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

    private let credentialStore: ASCredentialIdentityStoring
    private let settingsHelper: any AutofillExtensionSettingsHelping

    @Published var isExtensionEnabled: Bool = false
    @Published var isShowingActivationView: Bool = false

    init(credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
         settingsHelper: any AutofillExtensionSettingsHelping = DefaultAutofillExtensionSettingsHelper()) {
        self.credentialStore = credentialStore
        self.settingsHelper = settingsHelper
        Task { await updateExtensionStatus() }
    }

    func updateExtensionStatus() async {
        let state = await credentialStore.state()
        isExtensionEnabled = state.isEnabled
    }

    func enableExtension() async {
        let result = await settingsHelper.requestToTurnOnCredentialProviderExtension()
        Logger.autofill.debug("Extension enabled result: \(result)")
        isShowingActivationView = result
        await updateExtensionStatus()
    }

    func disableExtension() async {
        do {
            try await settingsHelper.openCredentialProviderAppSettings()
        } catch {
            Logger.autofill.error("Failed to open credential provider settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
