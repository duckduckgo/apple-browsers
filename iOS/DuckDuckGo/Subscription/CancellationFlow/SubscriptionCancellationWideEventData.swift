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

final class SubscriptionCancellationWideEventData: WideEventData {
    static let metadata = WideEventMetadata(
        pixelName: "subscription_cancellation",
        featureName: "subscription-cancellation",
        mobileMetaType: "ios-subscription-cancellation",
        desktopMetaType: "macos-subscription-cancellation",
        version: "1.1.0"
    )

    static let cancellationTimeout: TimeInterval = .hours(24)

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData

    let entryPoint: EntryPoint
    let purchasePlatform: SubscriptionPurchaseWideEventData.PurchasePlatform
    let isTrial: Bool
    let subscriptionIdentifier: String
    let daysSincePurchase: SubscriptionDaysSincePurchaseBucket
    let daysUntilRenewal: SubscriptionDaysSincePurchaseBucket
    let startDate: Date

    var errorData: WideEventErrorData?

    var subscriptionFetcher: (() async throws -> DuckDuckGoSubscription?)?

    private enum CodingKeys: String, CodingKey {
        case globalData, contextData, appData
        case entryPoint, purchasePlatform, isTrial, subscriptionIdentifier
        case daysSincePurchase, daysUntilRenewal, startDate
        case errorData
    }

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
            let now = Date()
            guard let subscriptionFetcher else {
                return timeoutDecision(now: now, reason: .partialData)
            }
            do {
                return completionDecision(for: try await subscriptionFetcher(), now: now)
            } catch {
                return timeoutDecision(now: now, reason: .partialData)
            }
        }
    }

    func completionDecision(for subscription: DuckDuckGoSubscription?, now: Date) -> WideEventCompletionDecision {
        guard let subscription else {
            return .complete(.unknown(reason: StatusReason.noSubscription.rawValue))
        }

        switch subscription.status {
        case .notAutoRenewable:
            return .complete(.success(reason: StatusReason.autoRenewDisabled.rawValue))
        case .autoRenewable, .gracePeriod:
            if subscription.productId != subscriptionIdentifier {
                return .complete(.unknown(reason: StatusReason.planChanged.rawValue))
            }
            return timeoutDecision(now: now, reason: .notCancelledBeforeTimeout)
        case .expired, .inactive, .unknown:
            return .complete(.unknown(reason: StatusReason.partialData.rawValue))
        }
    }

    private func timeoutDecision(now: Date, reason: StatusReason) -> WideEventCompletionDecision {
        if now >= startDate.addingTimeInterval(Self.cancellationTimeout) {
            return .complete(.unknown(reason: reason.rawValue))
        }
        return .keepPending
    }
}

extension SubscriptionCancellationWideEventData {

    enum EntryPoint: String, Codable, CaseIterable {
        case cancelSubscription = "cancel_subscription"
        case manageSubscription = "manage_subscription"
        case managePaymentOrCancel = "manage_payment_or_cancel"
        case changePlan = "change_plan"
    }

    enum StatusReason: String {
        case autoRenewDisabled = "auto_renew_disabled"
        case notCancelledBeforeTimeout = "not_cancelled_before_timeout"
        case planChanged = "plan_changed"
        case noSubscription = "no_subscription"
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
