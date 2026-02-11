//
//  SubscriptionInstrumentationPixelHandler.swift
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
import Common
import PixelKit
import Subscription

final class SubscriptionInstrumentationPixelHandler {

    private let attributionPixelHandler: SubscriptionAttributionPixelHandling

    init(attributionPixelHandler: SubscriptionAttributionPixelHandling = SubscriptionAttributionPixelHandler()) {
        self.attributionPixelHandler = attributionPixelHandler
    }

    func makeEventMapping() -> EventMapping<SubscriptionInstrumentationEvent> {
        EventMapping { [weak self] event, _, _, onComplete in
            self?.handleEvent(event)
            onComplete(nil)
        }
    }

    private func handleEvent(_ event: SubscriptionInstrumentationEvent) {
        switch event {
        case .purchaseAttempt:
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseAttempt, frequency: .legacyDailyAndCount)

        case .purchaseSuccess(let origin):
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseSuccess, frequency: .legacyDailyAndCount)
            PixelKit.fire(SubscriptionPixel.subscriptionActivated, frequency: .uniqueByName)
            fireAttributionPixel(origin: origin)

        case .purchaseSuccessStripe(let origin):
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseStripeSuccess, frequency: .legacyDailyAndCount)
            fireAttributionPixel(origin: origin)

        case .purchaseFailure(let step, let error):
            switch step {
            case .flowStart:
                PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureOther, frequency: .legacyDailyAndCount)
            case .accountCreate:
                PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureAccountNotCreated(error), frequency: .legacyDailyAndCount)
            case .accountPayment:
                PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureStoreError(error), frequency: .legacyDailyAndCount)
            case .accountActivation:
                PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureBackendError, frequency: .legacyDailyAndCount)
            }

        case .purchasePendingTransaction:
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureStoreError(AppStorePurchaseFlowError.transactionPendingAuthentication), frequency: .legacyDailyAndCount)

        case .existingSubscriptionFound:
            PixelKit.fire(SubscriptionPixel.subscriptionRestoreAfterPurchaseAttempt)

        case .restoreStoreStart:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreStart, frequency: .legacyDailyAndCount)

        case .restoreStoreSuccess:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess, frequency: .legacyDailyAndCount)

        case .restoreStoreFailureNotFound:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreFailureNotFound, frequency: .legacyDailyAndCount)

        case .restoreStoreFailureOther:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreFailureOther, frequency: .legacyDailyAndCount)

        case .restoreEmailStart:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseEmailStart, frequency: .legacyDailyAndCount)

        case .restoreEmailSuccess:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseEmailSuccess, frequency: .legacyDailyAndCount)
        }
    }

    private func fireAttributionPixel(origin: String?) {
        attributionPixelHandler.origin = origin
        attributionPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
    }
}
