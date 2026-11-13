//
//  SubscriptionCancellationWideEventData.swift
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
import Subscription
import WideEvent

// Will be moved to a shared package later with macOS change.
final class SubscriptionCancellationWideEventData: WideEventData {
    static let metadata = WideEventMetadata(
        pixelName: "subscription_cancellation",
        featureName: "subscription-cancellation",
        mobileMetaType: "ios-subscription-cancellation",
        // The macOS version of this wide event will be added later.
        desktopMetaType: "macos-subscription-cancellation",
        version: "1.1.0"
    )

    static let cancellationTimeout: TimeInterval = .hours(24)

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    let entryPoint: EntryPoint
    let purchasePlatform: SubscriptionPurchaseWideEventData.PurchasePlatform
    let isTrial: Bool
    let subscriptionIdentifier: String
    let daysSincePurchase: SubscriptionDaysSincePurchaseBucket
    let daysUntilRenewal: SubscriptionDaysSincePurchaseBucket
    let startDate: Date
    var statusReason: StatusReason?

    init(entryPoint: EntryPoint,
                purchasePlatform: SubscriptionPurchaseWideEventData.PurchasePlatform,
                isTrial: Bool,
                subscriptionIdentifier: String,
                daysSincePurchase: SubscriptionDaysSincePurchaseBucket,
                daysUntilRenewal: SubscriptionDaysSincePurchaseBucket,
                startDate: Date,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.entryPoint = entryPoint
        self.purchasePlatform = purchasePlatform
        self.isTrial = isTrial
        self.subscriptionIdentifier = subscriptionIdentifier
        self.daysSincePurchase = daysSincePurchase
        self.daysUntilRenewal = daysUntilRenewal
        self.startDate = startDate
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            guard Date() >= startDate.addingTimeInterval(Self.cancellationTimeout) else {
                return .keepPending
            }
            return .complete(.unknown(reason: StatusReason.timeout.rawValue))
        }
    }
}

extension SubscriptionCancellationWideEventData {

    enum EntryPoint: String, Codable, CaseIterable {
        case cancelSubscription = "cancel_subscription"
        case manageSubscription = "manage_subscription"
        case managePaymentOrCancel = "manage_payment_or_cancel"
        case changePlan = "change_plan"
    }

    enum StatusReason: String, Codable, CaseIterable {
        case notAutoRenewable = "not_auto_renewable"
        case timeout
        case planChanged = "plan_changed"
        case noSubscription = "no_subscription"
        case expired
        case gracePeriod = "grace_period"
        case partialData = "partial_data"
    }

    func jsonParameters() -> [String: Encodable] {
        Dictionary(compacting: [
            (WideEventParameter.SubscriptionCancellationFeature.entryPoint, entryPoint.rawValue),
            (WideEventParameter.SubscriptionCancellationFeature.purchasePlatform, purchasePlatform.rawValue),
            (WideEventParameter.SubscriptionCancellationFeature.isTrial, isTrial),
            (WideEventParameter.SubscriptionCancellationFeature.subscriptionIdentifier, subscriptionIdentifier),
            (WideEventParameter.SubscriptionCancellationFeature.daysSincePurchase, daysSincePurchase.rawValue),
            (WideEventParameter.SubscriptionCancellationFeature.daysUntilRenewal, daysUntilRenewal.rawValue),
            (WideEventParameter.Feature.statusReason, statusReason?.rawValue),
        ])
    }
}

extension SubscriptionPurchaseWideEventData.PurchasePlatform {

    init?(_ platform: DuckDuckGoSubscription.Platform) {
        switch platform {
        case .apple: self = .appStore
        case .stripe: self = .stripe
        case .google, .unknown: return nil
        }
    }
}

extension WideEventParameter {

    enum SubscriptionCancellationFeature {
        static let entryPoint = "feature.data.ext.entry_point"
        static let purchasePlatform = "feature.data.ext.purchase_platform"
        static let isTrial = "feature.data.ext.is_trial"
        static let subscriptionIdentifier = "feature.data.ext.subscription_identifier"
        static let daysSincePurchase = "feature.data.ext.days_since_purchase_bucketed"
        static let daysUntilRenewal = "feature.data.ext.days_until_renewal_bucketed"
    }
}
