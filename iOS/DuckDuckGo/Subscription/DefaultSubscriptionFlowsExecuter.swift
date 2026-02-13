//
//  DefaultSubscriptionFlowsExecuter.swift
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
import Subscription
import BrowserServicesKit
import PixelKit
import os.log

/// Protocol for performing App Store subscription tier changes (upgrade, downgrade, cancel pending downgrade).
/// Callback-based API used by the subscription page feature and native Settings cancel-downgrade.
public protocol SubscriptionFlowsExecuting: AnyObject {

    /// Performs an App Store tier change. Reports progress and result via callbacks.
    @MainActor
    func performTierChange(to productId: String,
                           changeType: String?,
                           contextName: String?,
                           setTransactionStatus: ((SubscriptionTransactionStatus) -> Void)?,
                           setTransactionError: ((AppStorePurchaseFlowError?) -> Void)?,
                           pushPurchaseUpdate: ((PurchaseUpdate) async -> Void)?) async
}

/// Performs App Store tier changes (upgrade, downgrade, cancel pending downgrade).
/// Used by both SubscriptionPagesUseSubscriptionFeature (Web flow) and native Settings cancel-downgrade.
public final class DefaultSubscriptionFlowsExecuter: SubscriptionFlowsExecuting {

    private let subscriptionManager: SubscriptionManager
    private let appStorePurchaseFlow: AppStorePurchaseFlow
    private let wideEvent: WideEventManaging
    private let pendingTransactionHandler: PendingTransactionHandling
    private let notificationCenter: NotificationCenter

    public init(subscriptionManager: SubscriptionManager,
                appStorePurchaseFlow: AppStorePurchaseFlow,
                wideEvent: WideEventManaging,
                pendingTransactionHandler: PendingTransactionHandling,
                notificationCenter: NotificationCenter = .default) {
        self.subscriptionManager = subscriptionManager
        self.appStorePurchaseFlow = appStorePurchaseFlow
        self.wideEvent = wideEvent
        self.pendingTransactionHandler = pendingTransactionHandler
        self.notificationCenter = notificationCenter
    }

    @MainActor
    public func performTierChange(to productId: String,
                                  changeType: String?,
                                  contextName: String?,
                                  setTransactionStatus: ((SubscriptionTransactionStatus) -> Void)? = nil,
                                  setTransactionError: ((AppStorePurchaseFlowError?) -> Void)? = nil,
                                  pushPurchaseUpdate: ((PurchaseUpdate) async -> Void)? = nil) async {
        setTransactionError?(nil)
        setTransactionStatus?(.changingPlan)

        // Get current subscription info for wide event tracking
        let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
        let fromPlan = currentSubscription?.productId ?? ""
        let resolvedChangeType = determineChangeType(change: changeType)

        // Initialize wide event data
        let wideData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: resolvedChangeType,
            fromPlan: fromPlan,
            toPlan: productId,
            paymentDuration: WideEvent.MeasuredInterval.startingNow(),
            contextData: WideEventContextData(name: contextName)
        )
        wideEvent.startFlow(wideData)

        // Execute the tier change (uses existing account's externalID)
        Logger.subscription.log("[TierChange] Executing tier change")
        let tierChangeResult = await appStorePurchaseFlow.changeTier(to: productId)

        let transactionJWS: String
        switch tierChangeResult {
        case .success(let jws):
            transactionJWS = jws
            wideData.paymentDuration?.complete()
            wideEvent.updateFlow(wideData)
        case .failure(let error):
            Logger.subscription.error("[TierChange] Tier change failed: \(error.localizedDescription)")
            setTransactionStatus?(.idle)
            setTransactionError?(error)
            switch error {
            case .cancelledByUser:
                wideEvent.completeFlow(wideData, status: .cancelled, onComplete: { _, _ in })
            case .transactionPendingAuthentication:
                pendingTransactionHandler.markPurchasePending()
                wideData.markAsFailed(at: .payment, error: error)
                wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
            default:
                wideData.markAsFailed(at: .payment, error: error)
                wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
            }
            await pushPurchaseUpdate?(.canceled)
            return
        }

        setTransactionStatus?(.planChangePolling)

        guard transactionJWS.isEmpty == false else {
            Logger.subscription.fault("[TierChange] Purchase transaction JWS is empty")
            assertionFailure("Purchase transaction JWS is empty")
            setTransactionStatus?(.idle)
            wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
            return
        }

        // Start confirmation timing
        wideData.confirmationDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.updateFlow(wideData)

        // Complete the tier change by confirming with the backend
        let completeResult = await appStorePurchaseFlow.completeSubscriptionPurchase(with: transactionJWS, additionalParams: nil)

        switch completeResult {
        case .success:
            Logger.subscription.log("[TierChange] Tier change completed successfully")
            notificationCenter.post(name: .subscriptionDidChange, object: self)
            setTransactionStatus?(.idle)
            await pushPurchaseUpdate?(.completed)
            wideData.confirmationDuration?.complete()
            wideEvent.updateFlow(wideData)
            wideEvent.completeFlow(wideData, status: .success, onComplete: { _, _ in })

        case .failure(let error):
            Logger.subscription.error("[TierChange] Complete tier change error: \(error, privacy: .public)")
            setTransactionStatus?(.idle)
            setTransactionError?(error)
            await pushPurchaseUpdate?(.completed)
            if error != .missingEntitlements {
                wideData.markAsFailed(at: .confirmation, error: error)
                wideEvent.updateFlow(wideData)
                wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
            }
        }
    }

    private func determineChangeType(change: String?) -> SubscriptionPlanChangeWideEventData.ChangeType? {
        SubscriptionPlanChangeWideEventData.ChangeType.parse(string: change)
    }
}

extension SubscriptionPlanChangeWideEventData.ChangeType {
    /// Parses a change type string from the frontend (e.g. "upgrade", "downgrade", "crossgrade"; case-insensitive).
    static func parse(string: String?) -> SubscriptionPlanChangeWideEventData.ChangeType? {
        guard let change = string?.lowercased() else { return nil }
        switch change {
        case "upgrade": return .upgrade
        case "downgrade": return .downgrade
        case "crossgrade": return .crossgrade
        default: return nil
        }
    }
}
