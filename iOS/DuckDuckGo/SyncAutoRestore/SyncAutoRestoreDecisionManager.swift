//
//  SyncAutoRestoreDecisionManager.swift
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

import os.log
import PrivacyConfig

protocol SyncAutoRestoreDecisionManaging {
    var isAutoRestoreFeatureEnabled: Bool { get }
    func existingDecision() -> Bool?
    func persistDecision(_ decision: Bool) throws
    func clearDecision()
    func shouldPreserveAccountWhenSyncDisabled() -> Bool
}

final class SyncAutoRestoreDecisionManager: SyncAutoRestoreDecisionManaging {

    private let decisionStore: SyncAutoRestoreDecisionStoring
    private let featureFlagger: FeatureFlagger

    init(decisionStore: SyncAutoRestoreDecisionStoring = SyncAutoRestoreDecisionStore(),
         featureFlagger: FeatureFlagger) {
        self.decisionStore = decisionStore
        self.featureFlagger = featureFlagger
    }

    var isAutoRestoreFeatureEnabled: Bool {
        return featureFlagger.isFeatureOn(.syncAutoRestore)
    }

    func existingDecision() -> Bool? {
        do {
            return try decisionStore.getDecision()
        } catch {
            Logger.sync.error(
                "[Sync Auto Restore] Failed to read auto-restore decision: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    func persistDecision(_ decision: Bool) throws {
        do {
            try decisionStore.setDecision(decision)
        } catch {
            Logger.sync.error(
                "[Sync Auto Restore] Failed to write auto-restore decision: \(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
    }

    func clearDecision() {
        do {
            try decisionStore.clearDecision()
        } catch {
            Logger.sync.error(
                "[Sync Auto Restore] Failed to clear auto-restore decision: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    func shouldPreserveAccountWhenSyncDisabled() -> Bool {
        guard isAutoRestoreFeatureEnabled else { return false }
        return existingDecision() == true
    }
}
