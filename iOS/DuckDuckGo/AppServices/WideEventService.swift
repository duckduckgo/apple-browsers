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
import PixelKit
import Subscription
import VPN

final class WideEventService {
    private let wideEvent: WideEventManaging
    private let featureFlagger: FeatureFlagger
    private let subscriptionBridge: SubscriptionAuthV1toV2Bridge
    private let activationTimeoutInterval: TimeInterval = .hours(4)
    private let restoreTimeoutInterval: TimeInterval = .minutes(15)
    private let vpnConnectionTimeoutInterval: TimeInterval = .minutes(15)

    private let sendQueue = DispatchQueue(label: "com.duckduckgo.wide-pixel.send-queue", qos: .utility)

    init(wideEvent: WideEventManaging, featureFlagger: FeatureFlagger, subscriptionBridge: SubscriptionAuthV1toV2Bridge) {
        self.wideEvent = wideEvent
        self.featureFlagger = featureFlagger
        self.subscriptionBridge = subscriptionBridge
    }

    func resume() {
        sendDelayedPixels { }
    }

    // Runs at app launch, and sends pixels which were abandoned during a flow, such as the user exiting the app during
    // the flow, or the app crashing.
    func sendAbandonedPixels(completion: @escaping () -> Void) {
        let shouldSendSubscriptionPurchaseWidePixel = featureFlagger.isFeatureOn(.subscriptionPurchaseWidePixelMeasurement)
        let shouldSendVPNConnectionWidePixel = featureFlagger.isFeatureOn(.vpnConnectionWidePixelMeasurement)
        
        sendQueue.async { [weak self] in
            guard let self else { return }

            Task {
                await self.sendAbandonedSubscriptionRestorePixels()
                
                if shouldSendSubscriptionPurchaseWidePixel {
                    await self.sendAbandonedSubscriptionPurchasePixels()
                }
                if shouldSendVPNConnectionWidePixel {
                    await self.sendAbandonedVPNConnectionPixels()
                }

                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // Sends pixels which are currently incomplete but may complete later.
    func sendDelayedPixels(completion: @escaping () -> Void) {
        let shouldSendSubscriptionPurchaseWidePixel = featureFlagger.isFeatureOn(.subscriptionPurchaseWidePixelMeasurement)
        let shouldSendVPNConnectionWidePixel = featureFlagger.isFeatureOn(.vpnConnectionWidePixelMeasurement)

        sendQueue.async { [weak self] in
            guard let self else { return }

            Task {
                await self.sendDelayedSubscriptionRestorePixels()
                
                if shouldSendSubscriptionPurchaseWidePixel {
                    await self.sendDelayedSubscriptionPurchasePixels()
                }
                if shouldSendVPNConnectionWidePixel {
                    await self.sendDelayedVPNConnectionPixels()
                }

                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // MARK: - Subscription Purchase

    private func sendAbandonedSubscriptionPurchasePixels() async {
        let pending: [SubscriptionPurchaseWideEventData] = wideEvent.getAllFlowData(SubscriptionPurchaseWideEventData.self)

        // Any pixels that aren't pending activation are considered abandoned at launch.
        // Pixels that are pending activation will be handled in the delayed function, in the case that activation takes
        // a while.
        for data in pending {
            //  Pending pixels are identified by having an activation start but no end - skip them in this case.
            if data.activateAccountDuration?.start != nil && data.activateAccountDuration?.end == nil {
                continue
            }

            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionPurchaseWideEventData.StatusReason.partialData.rawValue))
        }
    }
    
    private func sendDelayedSubscriptionPurchasePixels() async {
        let pending: [SubscriptionPurchaseWideEventData] = wideEvent.getAllFlowData(SubscriptionPurchaseWideEventData.self)

        for data in pending {
            // Pending pixels are identified by having an activation start but no end.
            guard var interval = data.activateAccountDuration, let start = interval.start, interval.end == nil else {
                continue
            }

            if await checkForCurrentEntitlements() {
                // Activation happened, report the flow as a success but with a delay
                interval.complete()
                data.activateAccountDuration = interval

                let reason = SubscriptionPurchaseWideEventData.StatusReason.missingEntitlementsDelayedActivation.rawValue
                _ = try? await wideEvent.completeFlow(data, status: .success(reason: reason))
            } else {
                let deadline = start.addingTimeInterval(activationTimeoutInterval)
                if Date() < deadline {
                    // Still within activation window → leave it pending, do nothing
                    continue
                }

                // Timed out and still no entitlements → report unknown due to missing entitlements
                let reason = SubscriptionPurchaseWideEventData.StatusReason.missingEntitlements.rawValue
                _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: reason))
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

    // In the restore flow, we consider the pixel abandoned if:
    // - The flow is open and has not completed AND
    // - The duration interval is closed (never started OR has closed)
    private func sendAbandonedSubscriptionRestorePixels() async {
        let pending: [SubscriptionRestoreWideEventData] = wideEvent.getAllFlowData(SubscriptionRestoreWideEventData.self)

        for data in pending {
            if data.appleAccountRestoreDuration?.start != nil && data.appleAccountRestoreDuration?.end == nil {
                continue
            }

            if data.emailAddressRestoreDuration?.start != nil && data.emailAddressRestoreDuration?.end == nil {
                continue
            }

            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.partialData.rawValue))
        }
    }

    // In the restore flow, we consider the pixel delayed if:
    // - The flow is open and has not completed AND
    // - The duration interval has started, but has not completed AND
    // - The start time till now has exceed the maximum allowed time (if not, we consider it to be still in progress and allow it to continue)
    private func sendDelayedSubscriptionRestorePixels() async {
        let pending: [SubscriptionRestoreWideEventData] = wideEvent.getAllFlowData(SubscriptionRestoreWideEventData.self)

        for data in pending {
            // At most one will be non-nil
            guard let interval = data.appleAccountRestoreDuration ?? data.emailAddressRestoreDuration else {
                continue
            }

            guard let start = interval.start, interval.end == nil else {
                continue
            }

            let deadline = start.addingTimeInterval(restoreTimeoutInterval)
            if Date() < deadline {
                continue
            }

            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.timeout.rawValue))
        }
    }
    
    // MARK: - VPN Connection

    // In the vpn connection flow, we consider the pixel abandoned if:
    // - The flow is open and has not completed AND
    // - The duration interval is closed (never started OR has closed)
    private func sendAbandonedVPNConnectionPixels() async {
        let pending: [VPNConnectionWideEventData] = wideEvent.getAllFlowData(VPNConnectionWideEventData.self)

        for data in pending {
            if data.overallDuration?.start != nil && data.overallDuration?.end == nil {
                continue
            }

            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: VPNConnectionWideEventData.StatusReason.partialData.rawValue))
        }
    }

    // In the vpn connection flow, we consider the pixel delayed if:
    // - The flow is open and has not completed AND
    // - The duration interval has started, but has not completed AND
    // - The start time till now has exceed the maximum allowed time (if not, we consider it to be still in progress and allow it to continue)
    private func sendDelayedVPNConnectionPixels() async {
        let pending: [VPNConnectionWideEventData] = wideEvent.getAllFlowData(VPNConnectionWideEventData.self)

        for data in pending {
            guard let start = data.overallDuration?.start, data.overallDuration?.end == nil else {
                continue
            }

            let deadline = start.addingTimeInterval(vpnConnectionTimeoutInterval)
            if Date() < deadline {
                continue
            }

            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: VPNConnectionWideEventData.StatusReason.timeout.rawValue))
        }
    }
}
