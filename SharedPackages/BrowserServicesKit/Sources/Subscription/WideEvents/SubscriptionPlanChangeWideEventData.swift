//
//  SubscriptionPlanChangeWideEventData.swift
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

/// Wide event data for subscription plan changes (upgrades, downgrades, crossgrades)
public class SubscriptionPlanChangeWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "subscription_plan_change",
        featureName: "subscription-plan-change",
        mobileMetaType: "ios-subscription-plan-change",
        desktopMetaType: "macos-subscription-plan-change",
        version: "1.0.0"
    )

    public static let confirmationTimeout: TimeInterval = .hours(4)

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public let purchasePlatform: PurchasePlatform
    public let changeType: ChangeType?
    public let fromPlan: String
    public let toPlan: String

    public var paymentDuration: WideEvent.MeasuredInterval?
    public var confirmationDuration: WideEvent.MeasuredInterval?

    public var failingStep: FailingStep?
    public var errorData: WideEventErrorData?

    public var entitlementsChecker: (() async -> Bool)?

    private enum CodingKeys: String, CodingKey {
        case globalData, contextData, appData
        case purchasePlatform, changeType, fromPlan, toPlan
        case paymentDuration, confirmationDuration
        case failingStep, errorData
    }

    public init(purchasePlatform: PurchasePlatform,
                changeType: ChangeType?,
                fromPlan: String,
                toPlan: String,
                failingStep: FailingStep? = nil,
                paymentDuration: WideEvent.MeasuredInterval? = nil,
                confirmationDuration: WideEvent.MeasuredInterval? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.purchasePlatform = purchasePlatform
        self.changeType = changeType
        self.fromPlan = fromPlan
        self.toPlan = toPlan
        self.failingStep = failingStep
        self.paymentDuration = paymentDuration
        self.confirmationDuration = confirmationDuration
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            guard var interval = confirmationDuration, let start = interval.start else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            guard interval.end == nil else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            if let checker = entitlementsChecker, await checker() {
                interval.complete()
                confirmationDuration = interval
                return .complete(.success(reason: StatusReason.missingEntitlementsDelayedActivation.rawValue))
            }

            if Date() >= start.addingTimeInterval(Self.confirmationTimeout) {
                return .complete(.unknown(reason: StatusReason.missingEntitlements.rawValue))
            }

            return .keepPending
        }
    }
}

extension SubscriptionPlanChangeWideEventData {

    public enum PurchasePlatform: String, Codable, CaseIterable {
        case appStore = "app_store"
        case stripe
        case playStore = "play_store"
    }

    public enum ChangeType: String, Codable, CaseIterable {
        case upgrade = "UPGRADE"
        case downgrade = "DOWNGRADE"
        case crossgrade = "CROSSGRADE"
    }

    public enum FailingStep: String, Codable, CaseIterable {
        case payment = "ACCOUNT_PAYMENT"
        case confirmation = "ACCOUNT_ACTIVATION"
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
        case missingEntitlements = "missing_entitlements"
        case missingEntitlementsDelayedActivation = "missing_entitlements_delayed_activation"
    }

    public func pixelParameters() -> [String: String] {
        let bucket: DurationBucket = .bucketed(Self.bucket)

        return Dictionary(compacting: [
            (WideEventParameter.PlanChangeFeature.purchasePlatform, purchasePlatform.rawValue),
            (WideEventParameter.PlanChangeFeature.fromPlan, fromPlan),
            (WideEventParameter.PlanChangeFeature.toPlan, toPlan),
            (WideEventParameter.PlanChangeFeature.subscriptionIdentifier, toPlan),
            (WideEventParameter.PlanChangeFeature.changeType, changeType?.rawValue),
            (WideEventParameter.PlanChangeFeature.failingStep, failingStep?.rawValue),
            (WideEventParameter.PlanChangeFeature.paymentLatency, paymentDuration?.stringValue(bucket)),
            (WideEventParameter.PlanChangeFeature.confirmationLatency, confirmationDuration?.stringValue(bucket)),
        ])
    }

    public func markAsFailed(at step: FailingStep, error: Error) {
        self.failingStep = step
        self.errorData = WideEventErrorData(error: error)
    }

    private static func bucket(_ ms: Double) -> Int {
        switch ms {
        case 0..<1000: return 1000
        case 1000..<5000: return 5000
        case 5000..<10000: return 10000
        case 10000..<30000: return 30000
        case 30000..<60000: return 60000
        case 60000..<300000: return 300000
        default: return 600000
        }
    }
}

extension WideEventParameter {

    public enum PlanChangeFeature {
        public static let purchasePlatform = "feature.data.ext.purchase_platform"
        public static let changeType = "feature.data.ext.change_type"
        public static let fromPlan = "feature.data.ext.from_plan"
        public static let toPlan = "feature.data.ext.to_plan"
        public static let subscriptionIdentifier = "feature.data.ext.subscription_identifier"
        public static let failingStep = "feature.data.ext.failing_step"
        public static let paymentLatency = "feature.data.ext.payment_latency_ms_bucketed"
        public static let confirmationLatency = "feature.data.ext.confirmation_latency_ms_bucketed"
    }
}
