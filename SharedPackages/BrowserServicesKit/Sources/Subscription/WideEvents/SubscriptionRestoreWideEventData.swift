//
//  SubscriptionRestoreWideEventData.swift
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

public class SubscriptionRestoreWideEventData: WideEventData {

    #if DEBUG
    public static let pixelName = "subscription_restore_debug"
    #else
    public static let pixelName = "subscription_restore"
    #endif

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public let restorePlatform: RestorePlatform
    public var appleAccountRestoreDuration: WideEvent.MeasuredInterval?
    public var emailAddressRestoreDuration: WideEvent.MeasuredInterval?
    public var emailAddressRestoreLastURL: EmailAddressRestoreURL?

    public var errorData: WideEventErrorData?

    public init(restorePlatform: RestorePlatform,
                appleAccountRestoreDuration: WideEvent.MeasuredInterval? = nil,
                emailAddressRestoreDuration: WideEvent.MeasuredInterval? = nil,
                emailAddressRestoreLastURL: EmailAddressRestoreURL? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.restorePlatform = restorePlatform
        self.appleAccountRestoreDuration = appleAccountRestoreDuration
        self.emailAddressRestoreDuration = emailAddressRestoreDuration
        self.emailAddressRestoreLastURL = emailAddressRestoreLastURL
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    private static let featureName = "subscription-restore"
}

// MARK: - Public

extension SubscriptionRestoreWideEventData {

    public enum RestorePlatform: String, Codable, CaseIterable {
        case appleAccount = "apple_account"
        case emailAddress = "email_address"
        case purchaseBackgroundTask = "purchase_background_task"
    }

    public enum EmailAddressRestoreURL: String, Codable, CaseIterable {
        case activationFlow = "activation_flow"
        case activationFlowEmail = "activation_flow_email"
        case activationFlowActivateEmail = "activation_flow_activate_email"
        case activationFlowActivateEmailOTP = "activation_flow_activate_email_otp"
        case activationFlowSuccess = "activation_flow_success"

        private static let lookup: [String: Self] = {
            let pairs: [(SubscriptionURL, Self)] = [
                (.activationFlow, .activationFlow),
                (.activationFlowThisDeviceEmailStep, .activationFlowEmail),
                (.activationFlowThisDeviceActivateEmailStep, .activationFlowActivateEmail),
                (.activationFlowThisDeviceActivateEmailOTPStep, .activationFlowActivateEmailOTP),
                (.activationFlowSuccess, .activationFlowSuccess)
            ]

            // forComparison normalize the URL by removing the env query so the result is the same regardless of .stage or .production
            return Dictionary(uniqueKeysWithValues: pairs.map {
                ($0.0.subscriptionURL(environment: .production).forComparison().absoluteString, $0.1)
            })
        }()

        public static func from(_ currentURL: URL) -> Self? {
            let key = currentURL.forComparison().absoluteString
            return Self.lookup[key]
        }
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
        case timeout
    }

    public func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        params[WideEventParameter.Feature.name] = Self.featureName
        params[WideEventParameter.SubscriptionRestoreFeature.restorePlatform] = restorePlatform.rawValue

        if let lastURL = emailAddressRestoreLastURL {
            params[WideEventParameter.SubscriptionRestoreFeature.emailAddressRestoreLastURL] = lastURL.rawValue
        }

        setBucketedLatency(appleAccountRestoreDuration,
                           key: WideEventParameter.SubscriptionRestoreFeature.appleAccountRestoreLatency,
                           bucket: appleAccountBucket,
                           into: &params)

        setBucketedLatency(emailAddressRestoreDuration,
                           key: WideEventParameter.SubscriptionRestoreFeature.emailAddressRestoreLatency,
                           bucket: emailAddressBucket,
                           into: &params)
        return params
    }
}

// MARK: - Private

private extension SubscriptionRestoreWideEventData {

    func setBucketedLatency(_ interval: WideEvent.MeasuredInterval?,
                            key: String,
                            bucket: (Int) -> Int,
                            into params: inout [String: String]) {
        guard let start = interval?.start, let end = interval?.end else { return }
        let ms = max(0, Int(end.timeIntervalSince(start) * 1000))
        params[key] = String(bucket(ms))
    }

    func appleAccountBucket(_ ms: Int) -> Int {
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

    func emailAddressBucket(_ ms: Int) -> Int {
        switch ms {
        case 0..<10000: return 10000
        case 10000..<30000: return 30000
        case 30000..<60000: return 60000
        case 60000..<300000: return 300000
        case 300000..<600000: return 600000
        case 600000..<900000: return 900000
        default: return -1
        }
    }
}

// MARK: - Wide Event Parameters
extension WideEventParameter {

    public enum SubscriptionRestoreFeature {
        static let restorePlatform = "feature.data.ext.restore_platform"
        static let appleAccountRestoreLatency = "feature.data.ext.apple_account_restore_latency_ms_bucketed"
        static let emailAddressRestoreLatency = "feature.data.ext.email_address_restore_latency_ms_bucketed"
        static let emailAddressRestoreLastURL = "feature.data.ext.email_address_restore_last_url"
    }
}
