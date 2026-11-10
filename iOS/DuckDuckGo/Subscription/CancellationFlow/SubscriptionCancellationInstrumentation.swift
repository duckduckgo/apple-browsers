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
    func cancelClicked()
    func appStoreSubscriptionCancelled(entry: SubscriptionCancellationEntry, subscription: DuckDuckGoSubscription)
    func flowLoadFailed(_ error: Error)
    func featureInfoFailed(entitlement: SubscriptionEntitlement)
}

struct SubscriptionCancellationInstrumentation: SubscriptionCancellationInstrumenting {

    private let pixelFiring: PixelFiring?
    private let now: () -> Date

    init(pixelFiring: PixelFiring? = PixelKit.shared, now: @escaping () -> Date = Date.init) {
        self.pixelFiring = pixelFiring
        self.now = now
    }

    func cancelClicked() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationCancelClick)
    }

    func appStoreSubscriptionCancelled(entry: SubscriptionCancellationEntry, subscription: DuckDuckGoSubscription) {
        let daysSincePurchase = SubscriptionDaysSincePurchaseBucket(startedAt: subscription.startedAt, now: now())
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationAppStoreCancelled(entry: entry,
                                                                                      isTrial: subscription.hasActiveTrialOffer,
                                                                                      daysSincePurchase: daysSincePurchase))
    }

    func flowLoadFailed(_ error: Error) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(error), frequency: .dailyAndCount)
    }

    func featureInfoFailed(entitlement: SubscriptionEntitlement) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: entitlement), frequency: .dailyAndCount)
    }
}
