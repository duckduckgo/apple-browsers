//
//  OnboardingRestorePromptHandler.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

protocol OnboardingRestorePromptHandling {
    func isEligibleForRestorePrompt() -> Bool
    func restoreSyncAccount()
}

struct OnboardingRestorePromptHandler: OnboardingRestorePromptHandling {

    enum Configuration {
        case enabled
        case disabled
    }

    private let configuration: Configuration
    private let syncAutoRestoreHandler: SyncAutoRestoreHandling
    private let authenticator: Authenticating

    init(configuration: Configuration = .disabled,
         syncAutoRestoreHandler: SyncAutoRestoreHandling,
         authenticator: Authenticating = Authenticator()) {
        self.configuration = configuration
        self.syncAutoRestoreHandler = syncAutoRestoreHandler
        self.authenticator = authenticator
    }

    func isEligibleForRestorePrompt() -> Bool {
        guard case .enabled = configuration else {
            return false
        }
        return syncAutoRestoreHandler.isEligibleForAutoRestore() && authenticator.canAuthenticate()
    }

    func restoreSyncAccount() {
        guard case .enabled = configuration else {
            return
        }
        Task {
            try? await syncAutoRestoreHandler.restoreFromPreservedAccount(source: .onboarding)
        }
    }
}
