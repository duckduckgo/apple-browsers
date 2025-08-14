//
//  SubscriptionWidePixelData.swift
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

public struct SubscriptionPurchaseWidePixelData: WidePixelData {
    public static let pixelName = "subscription_purchase"

    // MARK: Subscription-Specific Info

    public let purchasePlatform: PurchasePlatform
    public var subscriptionIdentifier: String?
    public var freeTrialEligible: Bool?

    // MARK: Performance Metrics (Bucketed)

    /// Measured intervals for each step (persisted as start/end)
    public var createAccountDuration: MeasuredInterval?
    public var completePurchaseDuration: MeasuredInterval?
    public var activateAccountDuration: MeasuredInterval?

    // MARK: Error Information

    public var failingStep: FailingStep?
    public var errorData: WidePixelErrorData?

    // MARK: Context Information

    public var contextData: WidePixelContextData
    public var appData: WidePixelAppData
    public var globalData: WidePixelGlobalData

    // MARK: Initializer

    public init(purchasePlatform: PurchasePlatform,
                failingStep: FailingStep? = nil,
                subscriptionIdentifier: String? = nil,
                freeTrialEligible: Bool? = nil,
                createAccountDuration: MeasuredInterval? = nil,
                completePurchaseDuration: MeasuredInterval? = nil,
                activateAccountDuration: MeasuredInterval? = nil,
                errorData: WidePixelErrorData? = nil,
                contextData: WidePixelContextData = WidePixelContextData(),
                appData: WidePixelAppData = WidePixelAppData(),
                globalData: WidePixelGlobalData = WidePixelGlobalData()) {
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

extension SubscriptionPurchaseWidePixelData {
    public enum PurchasePlatform: String, Codable, CaseIterable {
        case appstore
        case stripe
    }

    public enum FailingStep: String, Codable, CaseIterable {
        case flowStart = "FLOW_START"
        case accountCreate = "ACCOUNT_CREATE"
        case storekitPurchase = "STOREKIT_PURCHASE"
        case accountActivation = "ACCOUNT_ACTIVATION"
    }
}

extension SubscriptionPurchaseWidePixelData {

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters["feature.data.ext.purchase_platform"] = purchasePlatform.rawValue

        if let failingStep = failingStep {
            parameters["feature.data.ext.failing_step"] = failingStep.rawValue
        }

        if let subscriptionIdentifier = subscriptionIdentifier {
            parameters["feature.data.ext.subscription_identifier"] = subscriptionIdentifier
        }

        if let freeTrialEligible = freeTrialEligible {
            parameters["feature.data.ext.free_trial_eligible"] = freeTrialEligible ? "true" : "false"
        }

        if let errorData = errorData {
            parameters["feature.data.error.domain"] = errorData.domain
            parameters["feature.data.error.code"] = String(errorData.code)
            if let underlyingDomain = errorData.underlyingDomain {
                parameters["feature.data.error.underlying_domain"] = underlyingDomain
            }
            if let underlyingCode = errorData.underlyingCode {
                parameters["feature.data.error.underlying_code"] = String(underlyingCode)
            }
        }

        // TODO: Allow buckets to be configurable per interval
        func bucket(_ ms: Int) -> Int {
            switch ms {
            case 0..<1000: return 1000
            case 1000..<5000: return 5000
            case 5000..<10000: return 10000
            case 10000..<30000: return 30000
            case 30000..<60000: return 60000
            default: return 60000
            }
        }

        func emit(_ key: String, interval: MeasuredInterval?) {
            guard let start = interval?.start, let end = interval?.end else { return }
            let ms = max(0, Int(end.timeIntervalSince(start) * 1000))
            parameters[key] = String(bucket(ms))
        }

        emit("feature.data.ext.create_account_latency_ms_bucketed", interval: createAccountDuration)
        emit("feature.data.ext.complete_purchase_latency_ms_bucketed", interval: completePurchaseDuration)
        emit("feature.data.ext.activate_account_latency_ms_bucketed", interval: activateAccountDuration)

        return parameters
    }

    public mutating func markAsFailed(at step: FailingStep, error: Error) {
        self.failingStep = step
        self.errorData = WidePixelErrorData(error: error)
    }

    public mutating func setContext(id: UUID? = nil, name: String? = nil) {
        if let id = id {
            self.contextData = WidePixelContextData(
                id: id,
                name: name ?? self.contextData.name,
                data: self.contextData.data
            )
        } else {
            self.contextData = WidePixelContextData(
                id: self.contextData.id,
                name: name ?? self.contextData.name,
                data: self.contextData.data
            )
        }
    }

}
