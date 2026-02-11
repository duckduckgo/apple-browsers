//
//  SubscriptionInstrumentationPixelHandler.swift
//  DuckDuckGo
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
import Core
import Subscription

final class SubscriptionInstrumentationPixelHandler {

    private let subscriptionDataReporter: SubscriptionDataReporting?

    init(subscriptionDataReporter: SubscriptionDataReporting? = nil) {
        self.subscriptionDataReporter = subscriptionDataReporter
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
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseAttempt,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .purchaseSuccess(let origin):
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            UniquePixel.fire(pixel: .subscriptionActivated)
            fireAttributionPixel(origin: origin)

        case .purchaseSuccessStripe(let origin):
            // iOS does not use Stripe for in-app purchases, but fire the same success pixels
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            UniquePixel.fire(pixel: .subscriptionActivated)
            fireAttributionPixel(origin: origin)

        case .purchaseFailure(let step, _):
            switch step {
            case .flowStart:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureOther,
                                             pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            case .accountCreate:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureAccountNotCreated,
                                             pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            case .accountPayment:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureStoreError,
                                             pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            case .accountActivation:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureBackendError,
                                             pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            }

        case .purchasePendingTransaction:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureStoreError,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .existingSubscriptionFound:
            Pixel.fire(pixel: .subscriptionRestoreAfterPurchaseAttempt)

        case .restoreStoreStart:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionRestorePurchaseStoreStart,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .restoreStoreSuccess:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionRestorePurchaseStoreSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .restoreStoreFailureNotFound:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionRestorePurchaseStoreFailureNotFound,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .restoreStoreFailureOther:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionRestorePurchaseStoreFailureOther,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .restoreEmailStart:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionRestorePurchaseEmailStart,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)

        case .restoreEmailSuccess:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionRestorePurchaseEmailSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        }
    }

    private func fireAttributionPixel(origin: String?) {
        Pixel.fireAttribution(pixel: .subscriptionSuccessfulSubscriptionAttribution,
                              origin: origin,
                              subscriptionDataReporter: subscriptionDataReporter)
    }
}
