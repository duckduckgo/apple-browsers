//
//  SyncRecoveryPromptService.swift
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
import UIKit
import Core
import BrowserServicesKit
import Persistence
import DDGSync

@MainActor
final class SyncRecoveryPromptService {

    private(set) lazy var presenter: SyncRecoveryPromptPresenting = SyncRecoveryPromptPresenter()

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let isOnboardingComplete: Bool

    enum Key {
        static let hasPerformedSyncRecoveryCheck: String = "com.duckduckgo.syncrecovery.check.performed"
    }

    private var hasPerformedCheck: Bool {
        get {
            (try? keyValueStore.object(forKey: Key.hasPerformedSyncRecoveryCheck) as? Bool) ?? false
        }
        set {
            try? keyValueStore.set(newValue, forKey: Key.hasPerformedSyncRecoveryCheck)
        }
    }

    init(featureFlagger: FeatureFlagger,
         syncService: DDGSyncing,
         keyValueStore: ThrowingKeyValueStoring,
         isOnboardingComplete: Bool) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.keyValueStore = keyValueStore
        self.isOnboardingComplete = isOnboardingComplete
    }

    func shouldShowPrompt() -> Bool {
        guard isFeatureFlagEnabled else {
            Logger.sync.debug("[Sync Recovery] Feature flag disabled")
            return false
        }

        guard isOnboardingComplete else {
            Logger.sync.debug("[Sync Recovery] Onboarding not complete")
            return false
        }

        guard !hasAlreadyPerformedCheck else {
            Logger.sync.debug("[Sync Recovery] Already performed check")
            return false
        }

        guard !isSyncAlreadyEnabled else {
            Logger.sync.debug("[Sync Recovery] Sync already enabled")
            return false
        }

        hasPerformedCheck = true
        Logger.sync.debug("[Sync Recovery] All conditions met - prompt can be shown")

        return true
    }

    // MARK: - Show Criteria Variables

    private var isFeatureFlagEnabled: Bool {
        featureFlagger.isFeatureOn(.newDeviceSyncPrompt)
    }

    // MARK: - Exclusion Criteria Variables

    private var hasAlreadyPerformedCheck: Bool {
        hasPerformedCheck
    }

    private var isSyncAlreadyEnabled: Bool {
        syncService.account != nil
    }

    @discardableResult
    func tryPresentSyncRecoveryPrompt(from viewController: UIViewController,
                                      onSyncFlowSelected: @escaping (String) -> Void) -> Bool {
        guard shouldShowPrompt() else {
            return false
        }

        presenter.presentSyncRecoveryPrompt(
            from: viewController,
            onSyncFlowSelected: onSyncFlowSelected
        )
        return true
    }
}
