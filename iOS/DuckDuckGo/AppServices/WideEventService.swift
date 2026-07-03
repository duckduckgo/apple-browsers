//
//  WideEventService.swift
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
import BrowserServicesKit
import PrivacyConfig
import PixelKit
import Subscription
import VPN

actor WideEventService {
    private let wideEvent: WideEventManaging
    private let subscriptionManager: SubscriptionManager

    private var isProcessing = false

    init(wideEvent: WideEventManaging, subscriptionManager: SubscriptionManager) {
        self.wideEvent = wideEvent
        self.subscriptionManager = subscriptionManager
    }

    nonisolated func resume() {
        Task {
            // A warm foreground is NOT a launch: the process that started any in-flight flow is still
            // alive, so launch-only events (e.g. AuthV2 token refresh / invalid-token recovery) must not
            // be reconciled here, or we'd close a journey that may still be running. They are completed
            // only on cold launch, when a restarted process proves the prior journey is genuinely stalled.
            await sendPendingEvents(trigger: .appLaunch, includingLaunchOnlyEvents: false)
        }
    }

    func sendPendingEvents(trigger: WideEventCompletionTrigger, includingLaunchOnlyEvents: Bool = true) async {
        guard !isProcessing else { return }
        isProcessing = true

        await processCompletion(SubscriptionRestoreWideEventData.self, trigger: trigger)
        await processCompletion(VPNConnectionWideEventData.self, trigger: trigger)
        await processSubscriptionPurchaseCompletion(trigger: trigger)
        await processCompletion(DataImportWideEventData.self, trigger: trigger)
        await processCompletion(PostIdleSessionWideEventData.self, trigger: trigger)

        if includingLaunchOnlyEvents {
            // Launch-only: only a cold launch proves a still-pending refresh is genuinely stalled.
            await processCompletion(AuthV2TokenRefreshWideEventData.self, trigger: trigger)
        }

        isProcessing = false
    }

    private func processCompletion<T: WideEventData>(_ type: T.Type, trigger: WideEventCompletionTrigger) async {
        for data in wideEvent.getAllFlowData(T.self) {
            if case .complete(let status) = await data.completionDecision(for: trigger) {
                _ = try? await wideEvent.completeFlow(data, status: status)
            }
        }
    }

    private func processSubscriptionPurchaseCompletion(trigger: WideEventCompletionTrigger) async {
        for data in wideEvent.getAllFlowData(SubscriptionPurchaseWideEventData.self) {
            data.entitlementsChecker = { [weak self] in
                await self?.checkForCurrentEntitlements() ?? false
            }

            if case .complete(let status) = await data.completionDecision(for: trigger) {
                _ = try? await wideEvent.completeFlow(data, status: status)
            }
        }
    }

    private func checkForCurrentEntitlements() async -> Bool {
        do {
            let entitlements = try await subscriptionManager.currentSubscriptionFeatures(forceRefresh: true)
            return !entitlements.isEmpty
        } catch {
            return false
        }
    }
}

struct WideEventFeatureFlagAdapter: WideEventFeatureFlagProviding {
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        // There are no flags defined currently, but please replace this with a switch statement when a new flag is added.
        return true
    }
}
