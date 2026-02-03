//
//  FreeTrialConversionWideEventService.swift
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

import Foundation
import Common
import os.log
import PixelKit

/// Protocol for managing the free trial conversion wide event lifecycle.
public protocol FreeTrialConversionWideEventService: AnyObject {
    /// Starts observing subscription changes to automatically manage the wide event lifecycle.
    /// Call this once during app initialization.
    func startObservingSubscriptionChanges()

    /// Marks VPN as activated for the current free trial flow.
    func markVPNActivated()

    /// Marks PIR as activated for the current free trial flow.
    func markPIRActivated()
}

/// Default implementation that manages the free trial conversion wide event lifecycle.
/// Observes subscription changes to automatically start and complete the wide event.
///
/// Call `startObservingSubscriptionChanges()` once during app initialization.
/// The service will automatically:
/// - Start tracking when a user begins a free trial
/// - Complete with success when the user converts to a paid subscription
/// - Complete with failure when the trial expires without conversion
public final class DefaultFreeTrialConversionWideEventService: FreeTrialConversionWideEventService {

    private let wideEvent: WideEventManaging
    private let notificationCenter: NotificationCenter
    private let isFeatureEnabled: () -> Bool
    private var subscriptionObserver: NSObjectProtocol?

    public init(
        wideEvent: WideEventManaging,
        notificationCenter: NotificationCenter = .default,
        isFeatureEnabled: @escaping () -> Bool = { true }
    ) {
        self.wideEvent = wideEvent
        self.notificationCenter = notificationCenter
        self.isFeatureEnabled = isFeatureEnabled
    }

    deinit {
        if let observer = subscriptionObserver {
            notificationCenter.removeObserver(observer)
        }
    }

    /// Starts observing subscription changes to automatically manage the wide event lifecycle.
    /// Call this once during app initialization.
    public func startObservingSubscriptionChanges() {
        guard subscriptionObserver == nil else { return }

        subscriptionObserver = notificationCenter.addObserver(
            forName: .subscriptionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let subscription = notification.userInfo?[UserDefaultsCacheKey.subscription] as? DuckDuckGoSubscription else {
                return
            }

            Task {
                await self.handleSubscriptionChange(subscription)
            }
        }
    }

    /// Handles a subscription change to start or complete the wide event as appropriate.
    private func handleSubscriptionChange(_ subscription: DuckDuckGoSubscription) async {
        guard isFeatureEnabled() else { return }

        let existingFlow = wideEvent.getAllFlowData(FreeTrialConversionWideEventData.self).first

        if subscription.isActive && subscription.hasActiveTrialOffer {
            // User is in free trial. Start flow if one does not yet exist.
            guard existingFlow == nil else { return }
            let data = FreeTrialConversionWideEventData()
            wideEvent.startFlow(data)
            Logger.subscription.log("[FreeTrialConversion] Started flow")
        } else if subscription.isActive, let data = existingFlow {
            // User is active, but not on trial. Mark the existing flow as completed.
            _ = try? await wideEvent.completeFlow(data, status: .success)
            Logger.subscription.log("[FreeTrialConversion] Completed flow with SUCCESS (user converted to paid)")
        } else if let data = existingFlow {
            // User is no longer active. Mark the existing flow as completed.
            _ = try? await wideEvent.completeFlow(data, status: .failure)
            Logger.subscription.log("[FreeTrialConversion] Completed flow with FAILURE (trial expired)")
        }
    }

    /// Marks VPN as activated for the current free trial flow.
    public func markVPNActivated() {
        guard isFeatureEnabled(),
              let data = wideEvent.getAllFlowData(FreeTrialConversionWideEventData.self).first else {
            return
        }

        data.markVPNActivated()
        wideEvent.updateFlow(data)
        Logger.subscription.log("[FreeTrialConversion] VPN activated (D1: \(data.vpnActivatedD1), D2-D7: \(data.vpnActivatedD2ToD7))")
    }

    /// Marks PIR as activated for the current free trial flow.
    public func markPIRActivated() {
        guard isFeatureEnabled(),
              let data = wideEvent.getAllFlowData(FreeTrialConversionWideEventData.self).first else {
            return
        }

        data.markPIRActivated()
        wideEvent.updateFlow(data)
        Logger.subscription.log("[FreeTrialConversion] PIR activated (D1: \(data.pirActivatedD1), D2-D7: \(data.pirActivatedD2ToD7))")
    }
}
