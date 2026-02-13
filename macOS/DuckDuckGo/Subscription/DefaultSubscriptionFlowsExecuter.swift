//
//  DefaultSubscriptionFlowsExecuter.swift
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
import BrowserServicesKit
import PixelKit
import Subscription
import os.log

/// Protocol for performing App Store subscription tier changes (upgrade, downgrade, cancel pending downgrade).
/// Allows the subscription page feature and native UI (e.g. Preferences cancel downgrade)
/// to share the same implementation via dependency injection.
@MainActor
public protocol SubscriptionFlowsExecuting: AnyObject {

    /// Performs an App Store tier change.
    /// - Returns: `PurchaseUpdate` on success; `nil` on failure or user cancel.
    func performTierChange(to productId: String, changeType: String?, contextName: String) async -> PurchaseUpdate?
}

@MainActor
public final class DefaultSubscriptionFlowsExecuter: SubscriptionFlowsExecuting {

    private let subscriptionManager: SubscriptionManager
    private let uiHandler: SubscriptionUIHandling
    private let wideEvent: WideEventManaging
    private let subscriptionEventReporter: SubscriptionEventReporter
    private let pendingTransactionHandler: PendingTransactionHandling
    private let notificationCenter: NotificationCenter

    init(subscriptionManager: SubscriptionManager,
         uiHandler: SubscriptionUIHandling,
         wideEvent: WideEventManaging,
         subscriptionEventReporter: SubscriptionEventReporter,
         pendingTransactionHandler: PendingTransactionHandling,
         notificationCenter: NotificationCenter = .default) {
        self.subscriptionManager = subscriptionManager
        self.uiHandler = uiHandler
        self.wideEvent = wideEvent
        self.subscriptionEventReporter = subscriptionEventReporter
        self.pendingTransactionHandler = pendingTransactionHandler
        self.notificationCenter = notificationCenter
    }

    public func performTierChange(to productId: String, changeType: String?, contextName: String) async -> PurchaseUpdate? {
        let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
        let fromPlan = currentSubscription?.productId ?? ""
        let resolvedChangeType = SubscriptionPlanChangeWideEventData.ChangeType.parse(string: changeType)
        return await executeAppStoreTierChange(to: productId, changeType: resolvedChangeType, fromPlan: fromPlan, contextName: contextName)
    }

    private func executeAppStoreTierChange(to productId: String, changeType: SubscriptionPlanChangeWideEventData.ChangeType?, fromPlan: String, contextName: String) async -> PurchaseUpdate? {
        guard #available(macOS 12.0, *) else { return nil }

        // Initialize wide event data
        let wideData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: changeType,
            fromPlan: fromPlan,
            toPlan: productId,
            paymentDuration: WideEvent.MeasuredInterval.startingNow(),
            contextData: WideEventContextData(name: contextName)
        )
        wideEvent.startFlow(wideData)

        // 2: Show plan change progress UI to user
        uiHandler.presentProgressViewController(withTitle: UserText.planChangeInProgressTitle)

        // 3: Set up the purchase flow
        let appStorePurchaseFlow = makeAppStorePurchaseFlow()

        // 4: Execute the tier change (uses existing account's externalID)
        Logger.subscription.log("[TierChange] Executing tier change")
        let tierChangeResult = await appStorePurchaseFlow.changeTier(to: productId)

        let purchaseTransactionJWS: String
        switch tierChangeResult {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
            wideData.paymentDuration?.complete()
            wideEvent.updateFlow(wideData)
        case .failure(let error):
            reportPurchaseFlowError(error)
            if error == AppStorePurchaseFlowError.cancelledByUser {
                uiHandler.dismissProgressViewController()
                wideEvent.completeFlow(wideData, status: .cancelled, onComplete: { _, _ in })
            } else {
                await showSomethingWentWrongAlert()
                wideData.markAsFailed(at: SubscriptionPlanChangeWideEventData.FailingStep.payment, error: error)
                wideEvent.updateFlow(wideData)
                wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
            }
            return PurchaseUpdate(type: "canceled")
        }

        // 5: Update UI to indicate that the tier change is completing
        uiHandler.updateProgressViewController(title: UserText.completePlanChangeTitle)

        // Start confirmation timing
        wideData.confirmationDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.updateFlow(wideData)

        // 6: Complete the tier change by confirming with the backend
        let completePurchaseResult = await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS, additionalParams: nil)

        // 7: Handle tier change completion result
        switch completePurchaseResult {
        case .success(let purchaseUpdate):
            Logger.subscription.log("[TierChange] Tier change completed successfully")
            notificationCenter.post(name: .subscriptionDidChange, object: self)
            wideData.confirmationDuration?.complete()
            wideEvent.updateFlow(wideData)
            wideEvent.completeFlow(wideData, status: .success, onComplete: { _, _ in })
            uiHandler.dismissProgressViewController()
            return purchaseUpdate
        case .failure(let error):
            reportPurchaseFlowError(error)
            if case .missingEntitlements = error {
                DispatchQueue.main.async { [weak self] in
                    self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
                }
                uiHandler.dismissProgressViewController()
                return nil
            }
            uiHandler.dismissProgressViewController()
            wideData.markAsFailed(at: .confirmation, error: error)
            wideEvent.updateFlow(wideData)
            wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
            return PurchaseUpdate(type: "completed")
        }
    }

    @available(macOS 12.0, *)
    private func makeAppStorePurchaseFlow() -> DefaultAppStorePurchaseFlow {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(
            subscriptionManager: subscriptionManager,
            storePurchaseManager: subscriptionManager.storePurchaseManager(),
            pendingTransactionHandler: pendingTransactionHandler
        )
        return DefaultAppStorePurchaseFlow(
            subscriptionManager: subscriptionManager,
            storePurchaseManager: subscriptionManager.storePurchaseManager(),
            appStoreRestoreFlow: appStoreRestoreFlow,
            wideEvent: wideEvent,
            pendingTransactionHandler: pendingTransactionHandler
        )
    }

    private func reportPurchaseFlowError(_ error: AppStorePurchaseFlowError) {
        switch error {
        case .noProductsFound:
            subscriptionEventReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
        case .activeSubscriptionAlreadyPresent:
            subscriptionEventReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
        case .authenticatingWithTransactionFailed:
            subscriptionEventReporter.report(subscriptionActivationError: .otherPurchaseError)
        case .accountCreationFailed(let creationError):
            subscriptionEventReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
        case .purchaseFailed(let purchaseError):
            subscriptionEventReporter.report(subscriptionActivationError: .purchaseFailed(purchaseError))
        case .transactionPendingAuthentication:
            pendingTransactionHandler.markPurchasePending()
            subscriptionEventReporter.report(subscriptionActivationError: .purchasePendingTransaction)
        case .cancelledByUser:
            subscriptionEventReporter.report(subscriptionActivationError: .cancelledByUser)
        case .missingEntitlements:
            subscriptionEventReporter.report(subscriptionActivationError: .missingEntitlements)
        case .internalError:
            assertionFailure("Internal error")
        }
    }

    private func showSomethingWentWrongAlert() async {
        await uiHandler.dismissProgressViewAndShow(alertType: .somethingWentWrong, text: nil)
    }

}

extension SubscriptionPlanChangeWideEventData.ChangeType {
    /// Parses a change type string from the frontend (e.g. "upgrade", "downgrade", "crossgrade"; case-insensitive).
    /// Provided here because the app links against remote BrowserServicesKit which may not include this API yet.
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
