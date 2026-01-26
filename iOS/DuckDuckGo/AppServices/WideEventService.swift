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
    private let featureFlagger: FeatureFlagger
    private let subscriptionManager: SubscriptionManager

    private var isProcessing = false

    init(wideEvent: WideEventManaging, featureFlagger: FeatureFlagger, subscriptionManager: SubscriptionManager) {
        self.wideEvent = wideEvent
        self.featureFlagger = featureFlagger
        self.subscriptionManager = subscriptionManager
    }

    nonisolated func resume() {
        Task {
            await sendPendingEvents(trigger: .appLaunch)
        }
    }

    func sendPendingEvents(trigger: WideEventCompletionTrigger) async {
        guard !isProcessing else { return }
        isProcessing = true

        let shouldSendDataImportWideEvent = featureFlagger.isFeatureOn(.dataImportWideEventMeasurement)

        await processCompletion(SubscriptionRestoreWideEventData.self, trigger: trigger)
        await processCompletion(VPNConnectionWideEventData.self, trigger: trigger)
        await processSubscriptionPurchaseCompletion(trigger: trigger)

        if shouldSendDataImportWideEvent {
            await processCompletion(DataImportWideEventData.self, trigger: trigger)
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
            let entitlements = try await subscriptionManager.currentSubscriptionFeatures()
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
        switch flag {
        case .postEndpoint:
#if DEBUG || ALPHA || EXPERIMENTAL
            return false
#else
            return featureFlagger.isFeatureOn(.wideEventPostEndpoint)
#endif
        }
    }
}
