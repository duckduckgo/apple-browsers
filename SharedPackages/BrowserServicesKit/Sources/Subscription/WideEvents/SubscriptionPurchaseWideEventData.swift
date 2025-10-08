//
//  SubscriptionPurchaseWideEventData.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public class SubscriptionPurchaseWideEventData: WideEventData {
    #if DEBUG
    public static let pixelName = "subscription_purchase_debug"
    #else
    public static let pixelName = "subscription_purchase"
    #endif

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public let purchasePlatform: PurchasePlatform
    public var subscriptionIdentifier: String?
    public var freeTrialEligible: Bool

    public var createAccountDuration: WideEvent.MeasuredInterval?
    public var completePurchaseDuration: WideEvent.MeasuredInterval?
    public var activateAccountDuration: WideEvent.MeasuredInterval?

    public var failingStep: FailingStep?
    public var errorData: WideEventErrorData?

    public init(purchasePlatform: PurchasePlatform,
                failingStep: FailingStep? = nil,
                subscriptionIdentifier: String?,
                freeTrialEligible: Bool,
                createAccountDuration: WideEvent.MeasuredInterval? = nil,
                completePurchaseDuration: WideEvent.MeasuredInterval? = nil,
                activateAccountDuration: WideEvent.MeasuredInterval? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.purchasePlatform = purchasePlatform
        self.failingStep = failingStep
        self.subscriptionIdentifier = subscriptionIdentifier
        self.freeTrialEligible = freeTrialEligible
        self.createAccountDuration = createAccountDuration
        self.completePurchaseDuration = completePurchaseDuration
        self.activateAccountDuration = activateAccountDuration
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }
}

extension SubscriptionPurchaseWideEventData {

    public enum PurchasePlatform: String, Codable, CaseIterable {
        case appStore = "app_store"
        case stripe
    }

    public enum FailingStep: String, Codable, CaseIterable {
        case flowStart = "FLOW_START"
        case accountCreate = "ACCOUNT_CREATE"
        case accountPayment = "ACCOUNT_PAYMENT"
        case accountActivation = "ACCOUNT_ACTIVATION"
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
        case missingEntitlements = "missing_entitlements"
        case missingEntitlementsDelayedActivation = "missing_entitlements_delayed_activation"
    }

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.name] = "subscription-purchase"
        parameters[WideEventParameter.SubscriptionFeature.purchasePlatform] = purchasePlatform.rawValue

        if let failingStep = failingStep {
            parameters[WideEventParameter.SubscriptionFeature.failingStep] = failingStep.rawValue
        }

        if let subscriptionIdentifier = subscriptionIdentifier {
            parameters[WideEventParameter.SubscriptionFeature.subscriptionIdentifier] = subscriptionIdentifier
        }

        parameters[WideEventParameter.SubscriptionFeature.freeTrialEligible] = freeTrialEligible ? "true" : "false"

        if let duration = createAccountDuration?.durationMilliseconds {
            parameters[WideEventParameter.SubscriptionFeature.accountCreationLatency] = String(bucket(duration))
        }

        if let duration = completePurchaseDuration?.durationMilliseconds {
            parameters[WideEventParameter.SubscriptionFeature.accountPaymentLatency] = String(bucket(duration))
        }

        if let duration = activateAccountDuration?.durationMilliseconds {
            parameters[WideEventParameter.SubscriptionFeature.accountActivationLatency] = String(bucket(duration))
        }

        return parameters
    }

    public func markAsFailed(at step: FailingStep, error: Error) {
        self.failingStep = step
        self.errorData = WideEventErrorData(error: error)
    }

    private func bucket(_ ms: Double) -> Int {
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

    public enum SubscriptionFeature {
        static let purchasePlatform = "feature.data.ext.purchase_platform"
        static let failingStep = "feature.data.ext.failing_step"
        static let subscriptionIdentifier = "feature.data.ext.subscription_identifier"
        static let freeTrialEligible = "feature.data.ext.free_trial_eligible"
        static let accountCreationLatency = "feature.data.ext.account_creation_latency_ms_bucketed"
        static let accountPaymentLatency = "feature.data.ext.account_payment_latency_ms_bucketed"
        static let accountActivationLatency = "feature.data.ext.account_activation_latency_ms_bucketed"
    }

}
