//
//  DefaultSubscriptionInstrumentation.swift
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
import PixelKit

/// Shared implementation of the subscription instrumentation facade.
/// Handles all subscription-related wide event management and delegates pixel firing to platform-specific handlers.
public final class DefaultSubscriptionInstrumentation: SubscriptionInstrumentation {

    private let wideEvent: WideEventManaging
    private let pixelHandler: EventMapping<SubscriptionInstrumentationEvent>

    private var purchaseWideEventData: SubscriptionPurchaseWideEventData?
    private var restoreWideEventData: SubscriptionRestoreWideEventData?
    private var planChangeWideEventData: SubscriptionPlanChangeWideEventData?
    private var isRestoreEmailAttemptActive = false

    public init(wideEvent: WideEventManaging,
                pixelHandler: EventMapping<SubscriptionInstrumentationEvent>) {
        self.wideEvent = wideEvent
        self.pixelHandler = pixelHandler
    }

    // MARK: - Purchase Flow

    public func purchaseAttempted() {
        pixelHandler.fire(.purchaseAttempt)
    }

    public func purchaseFlowStarted(subscriptionId: String?,
                                    freeTrialEligible: Bool,
                                    origin: String?,
                                    purchasePlatform: SubscriptionPurchaseWideEventData.PurchasePlatform) {
        let data = SubscriptionPurchaseWideEventData(
            purchasePlatform: purchasePlatform,
            subscriptionIdentifier: subscriptionId,
            freeTrialEligible: freeTrialEligible,
            contextData: WideEventContextData(name: origin)
        )
        self.purchaseWideEventData = data
        wideEvent.startFlow(data)
    }

    public func purchaseSucceeded(origin: String?) {
        pixelHandler.fire(.purchaseSuccess(origin: origin))

        if let purchaseWideEventData {
            purchaseWideEventData.activateAccountDuration?.complete()
            wideEvent.updateFlow(purchaseWideEventData)
            wideEvent.completeFlow(purchaseWideEventData, status: .success(reason: nil), onComplete: { _, _ in })
        }
        self.purchaseWideEventData = nil
    }

    public func purchaseSucceededStripe(origin: String?) {
        pixelHandler.fire(.purchaseSuccessStripe(origin: origin))

        if let purchaseWideEventData {
            purchaseWideEventData.activateAccountDuration?.complete()
            wideEvent.updateFlow(purchaseWideEventData)
            wideEvent.completeFlow(purchaseWideEventData, status: .success(reason: nil), onComplete: { _, _ in })
        }
        self.purchaseWideEventData = nil
    }

    public func purchaseFailed(error: Error, step: SubscriptionPurchaseWideEventData.FailingStep) {
        pixelHandler.fire(.purchaseFailure(step: step, error: error))

        if let purchaseWideEventData {
            purchaseWideEventData.markAsFailed(at: step, error: error)
            wideEvent.updateFlow(purchaseWideEventData)
            wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
        }
        self.purchaseWideEventData = nil
    }

    public func purchaseCancelled() {
        if let purchaseWideEventData {
            wideEvent.completeFlow(purchaseWideEventData, status: .cancelled, onComplete: { _, _ in })
        }
        self.purchaseWideEventData = nil
    }

    public func purchasePendingTransaction() {
        pixelHandler.fire(.purchasePendingTransaction)

        if let purchaseWideEventData {
            purchaseWideEventData.markAsFailed(at: .accountPayment, error: AppStorePurchaseFlowError.transactionPendingAuthentication)
            wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
        }
        self.purchaseWideEventData = nil
    }

    public func existingSubscriptionFoundDuringPurchase() {
        pixelHandler.fire(.existingSubscriptionFound)

        if let purchaseWideEventData {
            wideEvent.discardFlow(purchaseWideEventData)
        }
        self.purchaseWideEventData = nil
    }

    // MARK: - Restore Flow

    public func restoreStoreStarted(origin: String) {
        pixelHandler.fire(.restoreStoreStart)

        let data = SubscriptionRestoreWideEventData(
            restorePlatform: .appleAccount,
            appleAccountRestoreDuration: WideEvent.MeasuredInterval.startingNow(),
            contextData: WideEventContextData(name: origin)
        )
        self.restoreWideEventData = data
        wideEvent.startFlow(data)
    }

    public func restoreStoreSucceeded() {
        pixelHandler.fire(.restoreStoreSuccess)

        if let restoreWideEventData {
            restoreWideEventData.appleAccountRestoreDuration?.complete()
            wideEvent.completeFlow(restoreWideEventData, status: .success, onComplete: { _, _ in })
        }
        self.restoreWideEventData = nil
    }

    public func restoreStoreFailed(error: AppStoreRestoreFlowError) {
        switch error {
        case .subscriptionExpired, .missingAccountOrTransactions:
            pixelHandler.fire(.restoreStoreFailureNotFound)
        default:
            pixelHandler.fire(.restoreStoreFailureOther)
        }

        if let restoreWideEventData {
            restoreWideEventData.appleAccountRestoreDuration?.complete()
            restoreWideEventData.errorData = WideEventErrorData(error: error)
            wideEvent.completeFlow(restoreWideEventData, status: .failure, onComplete: { _, _ in })
        }
        self.restoreWideEventData = nil
    }

    public func restoreStoreCancelled() {
        if let restoreWideEventData {
            wideEvent.discardFlow(restoreWideEventData)
        }
        self.restoreWideEventData = nil
    }

    public func beginRestoreEmailAttempt(origin: String?) {
        guard !isRestoreEmailAttemptActive else { return }
        isRestoreEmailAttemptActive = true

        pixelHandler.fire(.restoreEmailStart)

        let data = SubscriptionRestoreWideEventData(
            restorePlatform: .emailAddress,
            emailAddressRestoreDuration: WideEvent.MeasuredInterval.startingNow(),
            contextData: WideEventContextData(name: origin)
        )
        self.restoreWideEventData = data
        wideEvent.startFlow(data)
    }

    public func endRestoreEmailAttempt() {
        if let restoreWideEventData, restoreWideEventData.restorePlatform == .emailAddress {
            wideEvent.discardFlow(restoreWideEventData)
            self.restoreWideEventData = nil
        }
        isRestoreEmailAttemptActive = false
    }

    public func restoreEmailSucceeded() {
        pixelHandler.fire(.restoreEmailSuccess)

        // Complete any local restore flow
        if let restoreWideEventData {
            restoreWideEventData.emailAddressRestoreDuration?.complete()
            wideEvent.completeFlow(restoreWideEventData, status: .success, onComplete: { _, _ in })
        }
        self.restoreWideEventData = nil
        isRestoreEmailAttemptActive = false

        // Also complete any pending email restore flows started by another instrumentation instance
        // (e.g., email restore initiated from app settings but completed in a web view)
        completePendingEmailRestoreFlowsFromOtherInstances(success: true, error: nil)
    }

    public func restoreEmailFailed(error: Error?) {
        // Complete any local restore flow
        if let restoreWideEventData {
            restoreWideEventData.emailAddressRestoreDuration?.complete()
            if let error {
                restoreWideEventData.errorData = WideEventErrorData(error: error)
            }
            wideEvent.completeFlow(restoreWideEventData, status: .failure, onComplete: { _, _ in })
        }
        self.restoreWideEventData = nil
        isRestoreEmailAttemptActive = false

        // Also complete any pending email restore flows started by another instrumentation instance
        completePendingEmailRestoreFlowsFromOtherInstances(success: false, error: error)
    }

    /// Finds and completes any pending email restore wide events that were started by another instrumentation instance.
    ///
    /// This handles the cross-instance coordination case where email restore is initiated from one location
    /// (e.g., app settings using the AppDelegate's instrumentation) but completed in another location
    /// (e.g., a web view using its own local instrumentation instance).
    private func completePendingEmailRestoreFlowsFromOtherInstances(success: Bool, error: Error?) {
        let flows = wideEvent.getAllFlowData(SubscriptionRestoreWideEventData.self)
        let pendingEmailRestoreFlows = flows.filter {
            $0.restorePlatform == .emailAddress &&
            $0.emailAddressRestoreDuration?.start != nil &&
            $0.emailAddressRestoreDuration?.end == nil
        }

        for flowData in pendingEmailRestoreFlows {
            flowData.emailAddressRestoreDuration?.complete()
            if !success, let error {
                flowData.errorData = WideEventErrorData(error: error)
            }
            let status: WideEventStatus = success ? .success : .failure
            wideEvent.completeFlow(flowData, status: status, onComplete: { _, _ in })
        }
    }

    public func restoreBackgroundCheckStarted(origin: String) {
        let data = SubscriptionRestoreWideEventData(
            restorePlatform: .purchaseBackgroundTask,
            appleAccountRestoreDuration: WideEvent.MeasuredInterval.startingNow(),
            contextData: WideEventContextData(name: origin)
        )
        self.restoreWideEventData = data
        wideEvent.startFlow(data)
    }

    public func restoreBackgroundCheckSucceeded() {
        if let restoreWideEventData {
            restoreWideEventData.appleAccountRestoreDuration?.complete()
            wideEvent.completeFlow(restoreWideEventData, status: .success(reason: nil), onComplete: { _, _ in })
        }
        self.restoreWideEventData = nil
    }

    public func restoreBackgroundCheckFailed(error: Error) {
        if let restoreWideEventData {
            restoreWideEventData.appleAccountRestoreDuration?.complete()
            restoreWideEventData.errorData = WideEventErrorData(error: error)
            wideEvent.completeFlow(restoreWideEventData, status: .failure, onComplete: { _, _ in })
        }
        self.restoreWideEventData = nil
    }

    // MARK: - Plan Change Flow

    public func planChangeStarted(from: String,
                                  to: String,
                                  changeType: SubscriptionPlanChangeWideEventData.ChangeType?,
                                  origin: String?,
                                  purchasePlatform: SubscriptionPlanChangeWideEventData.PurchasePlatform) {
        let data = SubscriptionPlanChangeWideEventData(
            purchasePlatform: purchasePlatform,
            changeType: changeType,
            fromPlan: from,
            toPlan: to,
            paymentDuration: WideEvent.MeasuredInterval.startingNow(),
            contextData: WideEventContextData(name: origin)
        )
        self.planChangeWideEventData = data
        wideEvent.startFlow(data)
    }

    public func planChangePaymentSucceeded() {
        if let planChangeWideEventData {
            planChangeWideEventData.paymentDuration?.complete()
            planChangeWideEventData.confirmationDuration = WideEvent.MeasuredInterval.startingNow()
            wideEvent.updateFlow(planChangeWideEventData)
        }
    }

    public func planChangeSucceeded() {
        if let planChangeWideEventData {
            planChangeWideEventData.confirmationDuration?.complete()
            wideEvent.updateFlow(planChangeWideEventData)
            wideEvent.completeFlow(planChangeWideEventData, status: .success, onComplete: { _, _ in })
        }
        self.planChangeWideEventData = nil
    }

    public func planChangeFailed(error: Error, step: SubscriptionPlanChangeWideEventData.FailingStep) {
        if let planChangeWideEventData {
            planChangeWideEventData.markAsFailed(at: step, error: error)
            wideEvent.updateFlow(planChangeWideEventData)
            wideEvent.completeFlow(planChangeWideEventData, status: .failure, onComplete: { _, _ in })
        }
        self.planChangeWideEventData = nil
    }

    public func planChangeCancelled() {
        if let planChangeWideEventData {
            wideEvent.completeFlow(planChangeWideEventData, status: .cancelled, onComplete: { _, _ in })
        }
        self.planChangeWideEventData = nil
    }

    // MARK: - Wide Event Updates

    public func updatePurchaseAccountCreationDuration(_ duration: WideEvent.MeasuredInterval) {
        if let purchaseWideEventData {
            purchaseWideEventData.createAccountDuration = duration
            wideEvent.updateFlow(purchaseWideEventData)
        }
    }

    public func startPurchaseActivationTiming() {
        if let purchaseWideEventData {
            purchaseWideEventData.activateAccountDuration = WideEvent.MeasuredInterval.startingNow()
            wideEvent.updateFlow(purchaseWideEventData)
        }
    }

    public func updateEmailRestoreURL(_ url: SubscriptionRestoreWideEventData.EmailAddressRestoreURL) {
        if let restoreWideEventData {
            restoreWideEventData.emailAddressRestoreLastURL = url
            wideEvent.updateFlow(restoreWideEventData)
        }
    }

    public func discardPurchaseFlow() {
        if let purchaseWideEventData {
            wideEvent.discardFlow(purchaseWideEventData)
        }
        self.purchaseWideEventData = nil
    }
}
