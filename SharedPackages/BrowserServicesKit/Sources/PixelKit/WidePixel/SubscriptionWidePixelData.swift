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

public class SubscriptionPurchaseWidePixelData: WidePixelData {
    #if DEBUG
    public static let pixelName = "subscription_purchase_debug"
    #else
    public static let pixelName = "subscription_purchase"
    #endif

    public var globalData: WidePixelGlobalData
    public var contextData: WidePixelContextData
    public var appData: WidePixelAppData

    public let purchasePlatform: PurchasePlatform
    public var subscriptionIdentifier: String?
    public var freeTrialEligible: Bool
    public let experimentIDs: [String]

    public var createAccountDuration: WidePixel.MeasuredInterval?
    public var completePurchaseDuration: WidePixel.MeasuredInterval?
    public var activateAccountDuration: WidePixel.MeasuredInterval?

    public var failingStep: FailingStep?
    public var errorData: WidePixelErrorData?

    public init(purchasePlatform: PurchasePlatform,
                failingStep: FailingStep? = nil,
                subscriptionIdentifier: String?,
                freeTrialEligible: Bool,
                experimentIDs: [String] = [],
                createAccountDuration: WidePixel.MeasuredInterval? = nil,
                completePurchaseDuration: WidePixel.MeasuredInterval? = nil,
                activateAccountDuration: WidePixel.MeasuredInterval? = nil,
                errorData: WidePixelErrorData? = nil,
                contextData: WidePixelContextData,
                appData: WidePixelAppData = WidePixelAppData(),
                globalData: WidePixelGlobalData = WidePixelGlobalData()) {
        self.purchasePlatform = purchasePlatform
        self.failingStep = failingStep
        self.subscriptionIdentifier = subscriptionIdentifier
        self.freeTrialEligible = freeTrialEligible
        self.experimentIDs = experimentIDs
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

        parameters[WidePixelParameter.Feature.name] = "subscription-purchase"
        parameters[WidePixelParameter.SubscriptionFeature.purchasePlatform] = purchasePlatform.rawValue

        if let failingStep = failingStep {
            parameters[WidePixelParameter.SubscriptionFeature.failingStep] = failingStep.rawValue
        }

        if let subscriptionIdentifier = subscriptionIdentifier {
            parameters[WidePixelParameter.SubscriptionFeature.subscriptionIdentifier] = subscriptionIdentifier
        }

        parameters[WidePixelParameter.SubscriptionFeature.freeTrialEligible] = freeTrialEligible ? "true" : "false"

        if !experimentIDs.isEmpty {
            parameters[WidePixelParameter.Feature.experimentIDs] = experimentIDs.joined(separator: ",")
        }

        if let errorData = errorData {
            parameters[WidePixelParameter.Feature.errorDomain] = errorData.domain
            parameters[WidePixelParameter.Feature.errorCode] = String(errorData.code)

            if let underlyingDomain = errorData.underlyingDomain {
                parameters[WidePixelParameter.Feature.underlyingErrorDomain] = underlyingDomain
            }

            if let underlyingCode = errorData.underlyingCode {
                parameters[WidePixelParameter.Feature.underlyingErrorCode] = String(underlyingCode)
            }
        }

        func emit(_ key: String, interval: WidePixel.MeasuredInterval?) {
            guard let start = interval?.start, let end = interval?.end else { return }
            let ms = max(0, Int(end.timeIntervalSince(start) * 1000))
            parameters[key] = String(bucket(ms))
        }

        emit(WidePixelParameter.SubscriptionFeature.accountCreationLatency, interval: createAccountDuration)
        emit(WidePixelParameter.SubscriptionFeature.accountPaymentLatency, interval: completePurchaseDuration)
        emit(WidePixelParameter.SubscriptionFeature.accountActivationLatency, interval: activateAccountDuration)

        return parameters
    }

    public func markAsFailed(at step: FailingStep, error: Error) {
        self.failingStep = step
        self.errorData = WidePixelErrorData(error: error)
    }

    private func bucket(_ ms: Int) -> Int {
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
