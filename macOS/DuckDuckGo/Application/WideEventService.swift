//
//  WideEventService.swift
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
import PixelKit
import Subscription

final class WideEventService {
    private let wideEvent: WideEventManaging
    private let featureFlagger: FeatureFlagger
    private let subscriptionBridge: SubscriptionAuthV1toV2Bridge
    private let activationTimeoutInterval: TimeInterval = .hours(4)
    private let restoreTimeoutInterval: TimeInterval = .minutes(15)

    init(wideEvent: WideEventManaging, featureFlagger: FeatureFlagger, subscriptionBridge: SubscriptionAuthV1toV2Bridge) {
        self.wideEvent = wideEvent
        self.featureFlagger = featureFlagger
        self.subscriptionBridge = subscriptionBridge
    }

    // Processes all pending wide pixels in a single pass, handling both abandoned pixels (flows that were
    // interrupted) and delayed pixels (flows that are still in-progress but may need timeout handling).
    func processPixels() async {
        let shouldSendSubscriptionPurchaseWidePixel = featureFlagger.isFeatureOn(.subscriptionPurchaseWidePixelMeasurement)
        let shouldSendSubscriptionRestoreWidePixel = featureFlagger.isFeatureOn(.subscriptionRestoreWidePixelMeasurement)

        if !shouldSendSubscriptionPurchaseWidePixel && !shouldSendSubscriptionRestoreWidePixel {
            return
        }

        if shouldSendSubscriptionPurchaseWidePixel {
            await processSubscriptionPurchasePixels()
        }
        if shouldSendSubscriptionRestoreWidePixel {
            await processSubscriptionRestorePixels()
        }
    }

    // MARK: - Subscription Purchase

    private func processSubscriptionPurchasePixels() async {
        let pending: [SubscriptionPurchaseWideEventData] = wideEvent.getAllFlowData(SubscriptionPurchaseWideEventData.self)

        for data in pending {
            // Check if this is an in-progress pixel (has activation start but no end)
            if let interval = data.activateAccountDuration, let start = interval.start, interval.end == nil {
                // In-progress: check if activation completed or timed out
                if await checkForCurrentEntitlements() {
                    // Activation succeeded, report as success with delayed activation reason
                    var completedInterval = interval
                    completedInterval.complete()
                    data.activateAccountDuration = completedInterval

                    let reason = SubscriptionPurchaseWideEventData.StatusReason.missingEntitlementsDelayedActivation.rawValue
                    _ = try? await wideEvent.completeFlow(data, status: .success(reason: reason))
                } else {
                    let deadline = start.addingTimeInterval(activationTimeoutInterval)
                    if Date() >= deadline {
                        // Timed out without entitlements, report as unknown
                        let reason = SubscriptionPurchaseWideEventData.StatusReason.missingEntitlements.rawValue
                        _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: reason))
                    }
                    // If still within timeout window, leave it pending (do nothing)
                }
            } else {
                // Not in-progress: this is an abandoned pixel
                _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionPurchaseWideEventData.StatusReason.partialData.rawValue))
            }
        }
    }

    private func checkForCurrentEntitlements() async -> Bool {
        do {
            let entitlements = try await subscriptionBridge.currentSubscriptionFeatures()
            return !entitlements.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Subscription Restore

    private func processSubscriptionRestorePixels() async {
        let pending: [SubscriptionRestoreWideEventData] = wideEvent.getAllFlowData(SubscriptionRestoreWideEventData.self)

        for data in pending {
            // Check if either restore duration is in-progress (has start but no end)
            let appleInProgress = data.appleAccountRestoreDuration?.start != nil && data.appleAccountRestoreDuration?.end == nil
            let emailInProgress = data.emailAddressRestoreDuration?.start != nil && data.emailAddressRestoreDuration?.end == nil

            if appleInProgress || emailInProgress {
                // In-progress: check if timed out
                // At most one will be non-nil
                if let interval = data.appleAccountRestoreDuration ?? data.emailAddressRestoreDuration,
                   let start = interval.start {
                    let deadline = start.addingTimeInterval(restoreTimeoutInterval)
                    if Date() >= deadline {
                        // Timed out, report as unknown
                        _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.timeout.rawValue))
                    }
                    // If still within timeout window, leave it pending (do nothing)
                }
            } else {
                // Not in-progress: this is an abandoned pixel
                _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.partialData.rawValue))
            }
        }
    }
}
