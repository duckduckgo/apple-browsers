//
//  SubscriptionInstrumentation.swift
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
import PixelKit

public protocol SubscriptionInstrumentation: AnyObject {

    // MARK: - Purchase Flow

    /// Called when user taps subscribe button. Fires attempt pixel only.
    /// Note: Wide event is NOT started here - it starts after initial purchase succeeds.
    func purchaseAttempted()

    func purchaseFlowStarted(subscriptionId: String?,
                             freeTrialEligible: Bool,
                             origin: String?,
                             purchasePlatform: SubscriptionPurchaseWideEventData.PurchasePlatform)

    func purchaseSucceeded(origin: String?)
    func purchaseSucceededStripe(origin: String?)

    func purchaseFailed(error: Error, step: SubscriptionPurchaseWideEventData.FailingStep)
    func purchaseCancelled()
    func purchasePendingTransaction()
    func existingSubscriptionFoundDuringPurchase()

    // MARK: - Restore Flow

    func restoreStoreStarted(origin: String)
    func restoreStoreSucceeded()
    func restoreStoreFailed(error: AppStoreRestoreFlowError)
    func restoreStoreCancelled()

    func beginRestoreEmailAttempt(origin: String?)
    func endRestoreEmailAttempt()
    func restoreEmailSucceeded()
    func restoreEmailFailed(error: Error?)

    func restoreBackgroundCheckStarted(origin: String)
    func restoreBackgroundCheckSucceeded()
    func restoreBackgroundCheckFailed(error: Error)

    // MARK: - Plan Change Flow

    func planChangeStarted(from: String,
                           to: String,
                           changeType: SubscriptionPlanChangeWideEventData.ChangeType?,
                           origin: String?,
                           purchasePlatform: SubscriptionPlanChangeWideEventData.PurchasePlatform)

    func planChangePaymentSucceeded()
    func planChangeSucceeded()
    func planChangeFailed(error: Error, step: SubscriptionPlanChangeWideEventData.FailingStep)
    func planChangeCancelled()

    // MARK: - Wide Event Updates

    func updatePurchaseAccountCreationDuration(_ duration: WideEvent.MeasuredInterval)
    func startPurchaseActivationTiming()
    func updateEmailRestoreURL(_ url: SubscriptionRestoreWideEventData.EmailAddressRestoreURL)
    func discardPurchaseFlow()
}
