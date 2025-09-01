//
//  WidePixelService.swift
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

final class WidePixelService {
    private let widePixel: WidePixelManaging
    private let featureFlagger: FeatureFlagger
    private let subscriptionBridge: SubscriptionAuthV1toV2Bridge
    private let activationTimeoutInterval: TimeInterval = .hours(4)

    private let sendQueue = DispatchQueue(label: "com.duckduckgo.wide-pixel.send-queue", qos: .utility)

    init(widePixel: WidePixelManaging, featureFlagger: FeatureFlagger, subscriptionBridge: SubscriptionAuthV1toV2Bridge) {
        self.widePixel = widePixel
        self.featureFlagger = featureFlagger
        self.subscriptionBridge = subscriptionBridge
    }

    func resume() {
        sendDelayedPixels { }
    }

    // Runs at app launch, and sends pixels which were abandoned during a flow, such as the user exiting the app during
    // the flow, or the app crashing.
    func sendAbandonedPixels(completion: @escaping () -> Void) {
        guard featureFlagger.isFeatureOn(.subscriptionPurchaseWidePixelMeasurement) else {
            completion()
            return
        }

        sendQueue.async { [weak self] in
            guard let self else { return }

            Task {
                await self.sendAbandonedSubscriptionPurchasePixels()

                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // Sends pixels which are currently incomplete but may complete later.
    func sendDelayedPixels(completion: @escaping () -> Void) {
        guard featureFlagger.isFeatureOn(.subscriptionPurchaseWidePixelMeasurement) else {
            completion()
            return
        }

        sendQueue.async { [weak self] in
            guard let self else { return }

            Task {
                await self.sendDelayedSubscriptionPurchasePixels()

                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // MARK: - Subscription Purchase

    private func sendAbandonedSubscriptionPurchasePixels() async {
        let pending: [SubscriptionPurchaseWidePixelData] = widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self)

        // Any pixels that aren't pending activation are considered abandoned at launch.
        // Pixels that are pending activation will be handled in the delayed function, in the case that activation takes
        // a while.
        for data in pending {
            //  Pending pixels are identified by having an activation start but no end - skip them in this case.
            if data.activateAccountDuration?.start != nil && data.activateAccountDuration?.end == nil {
                continue
            }

            widePixel.completeFlow(data, status: .unknown(reason: SubscriptionPurchaseWidePixelData.StatusReason.partialData.rawValue)) { _, _ in }
        }
    }

    private func sendDelayedSubscriptionPurchasePixels() async {
        let pending: [SubscriptionPurchaseWidePixelData] = widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self)

        for data in pending {
            // Pending pixels are identified by having an activation start but no end.
            guard var interval = data.activateAccountDuration, let start = interval.start, interval.end == nil else {
                continue
            }

            if await checkForCurrentEntitlements() {
                // Activation happened, report the flow as a success but with a delay
                interval.complete()
                data.activateAccountDuration = interval

                let reason = SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlementsDelayedActivation.rawValue
                widePixel.completeFlow(data, status: .success(reason: reason)) { _, _ in }
            } else {
                let deadline = start.addingTimeInterval(activationTimeoutInterval)
                if Date() < deadline {
                    // Still within activation window → leave it pending, do nothing
                    continue
                }

                // Timed out and still no entitlements → report unknown due to missing entitlements
                let reason = SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlements.rawValue
                widePixel.completeFlow(data, status: .unknown(reason: reason)) { _, _ in }
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
}
