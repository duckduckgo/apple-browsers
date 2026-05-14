//
//  SyncAutoRestoreHandler.swift
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

import Core
import DDGSync
import SyncUI_iOS

enum SyncAutoRestorePixelSource: String {
    case onboarding
    case settings
}

protocol SyncAutoRestoreSyncing {
    var account: SyncAccount? { get }
    var authState: SyncAuthState { get }
    func enableSyncFromPreservedAccount() async throws
}

extension DDGSync: SyncAutoRestoreSyncing {}

protocol SyncAutoRestoreHandling: SyncAutoRestoreProviding {
    func clearDecision()
    func isEligibleForAutoRestore() -> Bool
    func restoreFromPreservedAccount(source: SyncAutoRestorePixelSource) async throws
}

final class SyncAutoRestoreHandler: SyncAutoRestoreHandling {

    private let decisionManager: SyncAutoRestoreDecisionManaging
    private let syncService: SyncAutoRestoreSyncing

    init(decisionManager: SyncAutoRestoreDecisionManaging,
         syncService: SyncAutoRestoreSyncing) {
        self.decisionManager = decisionManager
        self.syncService = syncService
    }

    var isAutoRestoreFeatureEnabled: Bool {
        decisionManager.isAutoRestoreFeatureEnabled
    }

    func existingDecision() -> Bool? {
        decisionManager.existingDecision()
    }

    func persistDecision(_ decision: Bool) throws {
        try decisionManager.persistDecision(decision)
    }

    func clearDecision() {
        decisionManager.clearDecision()
    }

    func isEligibleForAutoRestore() -> Bool {
        evaluateAutoRestoreEligibility()
    }

    func restoreFromPreservedAccount(source: SyncAutoRestorePixelSource) async throws {
        do {
            try await syncService.enableSyncFromPreservedAccount()
            Pixel.fire(pixel: .syncAutoRestoreSuccess, withAdditionalParameters: [PixelParameters.source: source.rawValue])
        } catch {
            Pixel.fire(pixel: .syncAutoRestoreFailure, error: error, withAdditionalParameters: [PixelParameters.source: source.rawValue])
            throw error
        }
    }

    private func evaluateAutoRestoreEligibility() -> Bool {
        guard decisionManager.isAutoRestoreFeatureEnabled else {
            return false
        }

        guard decisionManager.existingDecision() == true else {
            return false
        }

        guard syncService.account != nil else {
            return false
        }

        guard syncService.authState == .inactive else {
            return false
        }

        return true
    }
}
