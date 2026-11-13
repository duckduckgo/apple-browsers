//
//  SubscriptionCancellationInstrumentation.swift
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
import FoundationExtensions
import Networking
import PixelKit
import Subscription
import WideEvent

extension SubscriptionDaysSincePurchaseBucket {

    init(startedAt: Date, now: Date) {
        switch Calendar.current.numberOfDaysBetween(startedAt, and: now) ?? 0 {
        case ...1: self = .d1
        case 2...7: self = .d2To7
        case 8...30: self = .d8To30
        default: self = .d31Plus
        }
    }
}

protocol SubscriptionCancellationInstrumenting {
    func cancelSubscriptionTapped(subscription: DuckDuckGoSubscription?)
    func manageSubscriptionTapped(entryPoint: SubscriptionCancellationWideEventData.EntryPoint, subscription: DuckDuckGoSubscription?)
    func cancelSubscriptionFailed(_ error: Error)
    func appStoreSubscriptionCancelled(entry: SubscriptionCancellationEntry, subscription: DuckDuckGoSubscription)
    func flowLoadFailed(_ error: Error)
    func featureInfoFailed(entitlement: SubscriptionEntitlement)
}

struct SubscriptionCancellationInstrumentation: SubscriptionCancellationInstrumenting {

    private let pixelFiring: PixelFiring?
    private let wideEvent: WideEventManaging?
    private let now: () -> Date

    init(pixelFiring: PixelFiring? = PixelKit.shared, wideEvent: WideEventManaging? = nil, now: @escaping () -> Date = Date.init) {
        self.pixelFiring = pixelFiring
        self.wideEvent = wideEvent
        self.now = now
    }

    func cancelSubscriptionTapped(subscription: DuckDuckGoSubscription?) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationCancelClick)
        startCancellationWideEvent(entryPoint: .cancelSubscription, subscription: subscription)
    }

    func manageSubscriptionTapped(entryPoint: SubscriptionCancellationWideEventData.EntryPoint, subscription: DuckDuckGoSubscription?) {
        startCancellationWideEvent(entryPoint: entryPoint, subscription: subscription)
    }

    private func startCancellationWideEvent(entryPoint: SubscriptionCancellationWideEventData.EntryPoint, subscription: DuckDuckGoSubscription?) {
        guard let wideEvent,
              let subscription,
              subscription.status == .autoRenewable,
              let purchasePlatform = SubscriptionPurchaseWideEventData.PurchasePlatform(subscription.platform),
              wideEvent.getAllFlowData(SubscriptionCancellationWideEventData.self).isEmpty else {
            return
        }

        let tapDate = now()
        wideEvent.startFlow(SubscriptionCancellationWideEventData(
            entryPoint: entryPoint,
            purchasePlatform: purchasePlatform,
            isTrial: subscription.hasActiveTrialOffer,
            subscriptionIdentifier: subscription.productId,
            daysSincePurchase: SubscriptionDaysSincePurchaseBucket(startedAt: subscription.startedAt, now: tapDate),
            daysUntilRenewal: SubscriptionDaysSincePurchaseBucket(startedAt: tapDate, now: subscription.expiresOrRenewsAt),
            startDate: tapDate
        ))
    }

    func cancelSubscriptionFailed(_ error: Error) {
        failPendingCancellation(error)
    }

    private func failPendingCancellation(_ error: Error) {
        guard let wideEvent else { return }
        for data in wideEvent.getAllFlowData(SubscriptionCancellationWideEventData.self) {
            data.errorData = WideEventErrorData(error: error)
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        }
    }

    func appStoreSubscriptionCancelled(entry: SubscriptionCancellationEntry, subscription: DuckDuckGoSubscription) {
        let daysSincePurchase = SubscriptionDaysSincePurchaseBucket(startedAt: subscription.startedAt, now: now())
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationAppStoreCancelled(entry: entry,
                                                                                      isTrial: subscription.hasActiveTrialOffer,
                                                                                      daysSincePurchase: daysSincePurchase))
    }

    func flowLoadFailed(_ error: Error) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(error), frequency: .dailyAndCount)
        failPendingCancellation(error)
    }

    func featureInfoFailed(entitlement: SubscriptionEntitlement) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: entitlement), frequency: .dailyAndCount)
    }
}
