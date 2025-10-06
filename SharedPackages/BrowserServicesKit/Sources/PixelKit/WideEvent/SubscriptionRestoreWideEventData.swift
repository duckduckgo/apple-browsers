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
                emailAddressRestoreLastURL: EmailAddressRestoreURL? = nil,
                appleAccountRestoreDuration: WideEvent.MeasuredInterval? = nil,
                emailAddressRestoreDuration: WideEvent.MeasuredInterval? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.restorePlatform = restorePlatform
        self.emailAddressRestoreLastURL = emailAddressRestoreLastURL
        self.appleAccountRestoreDuration = appleAccountRestoreDuration
        self.emailAddressRestoreDuration = emailAddressRestoreDuration
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }
}

extension SubscriptionRestoreWideEventData {

    public enum RestorePlatform: String, Codable, CaseIterable {
        case appleAccount = "apple_account"
        case emailAddress = "email_address"
        case purchaseBackgroundTask = "purchase_background_task"
    }

    public enum EmailAddressRestoreURL: String, Codable, CaseIterable {
        case activationflowStart = "activation_flow_start" // subscriptions/activation-flow/this-device
        case activateByEmail = "activate_by_email" // subscriptions/activation-flow/this-device/activate-by-email
        case activateByEmailOTP = "activate_by_email_otp" // subscriptions/activation-flow/this-device/activate-by-email/otp
        case activateByEmailSuccess = "activate_by_email_success" // subscriptions/activation-flow/this-device/activate-by-email/success
    }

    public enum StatusReason: String {
        // FAILURE reasons
        case error

        // UNKNOWN reasons
        case partialData = "partial_data"
        case timeout
    }
}

extension SubscriptionRestoreWideEventData {

    public func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        params[WideEventParameter.Feature.name] = "restore-purchase"

        // Restore platform (apple-account | email-address | purchase_background_task)
        params[WideEventParameter.SubscriptionRestoreFeature.restorePlatform] = restorePlatform.rawValue

        // Email flow “last URL” milestone (only for email journey)
        if let lastURL = emailAddressRestoreLastURL {
            params[WideEventParameter.SubscriptionRestoreFeature.emailAddressRestoreLastURL] = lastURL.rawValue
        }

        // Latencies (bucketed)
        if let interval = appleAccountRestoreDuration,
           let start = interval.start, let end = interval.end {
            let ms = max(0, Int(end.timeIntervalSince(start) * 1000))
            params[WideEventParameter.SubscriptionRestoreFeature.appleAccountRestoreLatency] = String(appleAccountBucket(ms))
        }

        if let interval = emailAddressRestoreDuration,
           let start = interval.start, let end = interval.end {
            let ms = max(0, Int(end.timeIntervalSince(start) * 1000))
            params[WideEventParameter.SubscriptionRestoreFeature.emailAddressRestoreLatency] = String(emailAddressBucket(ms))
        }

        return params
    }

    private func appleAccountBucket(_ ms: Int) -> Int {
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

    private func emailAddressBucket(_ ms: Int) -> Int {
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
