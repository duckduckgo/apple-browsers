//
//  DefaultRemoteMessagingSurveyURLBuilder.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import Foundation
import Subscription

public protocol VPNActivationDateProviding {
    func daysSinceActivation() -> Int?
    func daysSinceLastActive() -> Int?
}

public struct DefaultRemoteMessagingSurveyURLBuilder: RemoteMessagingSurveyActionMapping {

    private let statisticsStore: StatisticsStore
    private let vpnActivationDateStore: VPNActivationDateProviding
    private let subscription: PrivacyProSubscription?
    private let localeIdentifier: String

    public init(statisticsStore: StatisticsStore,
                vpnActivationDateStore: VPNActivationDateProviding,
                subscription: PrivacyProSubscription?,
                localeIdentifier: String = Locale.current.identifier) {
        self.statisticsStore = statisticsStore
        self.vpnActivationDateStore = vpnActivationDateStore
        self.subscription = subscription
        self.localeIdentifier = localeIdentifier
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func add(parameters: [RemoteMessagingSurveyActionParameter], to surveyURL: URL) -> URL {
        guard var components = URLComponents(string: surveyURL.absoluteString) else {
            assertionFailure("Could not build URL components from survey URL")
            return surveyURL
        }

        var queryItems = components.queryItems ?? []

        for parameter in parameters {
            switch parameter {
            case .atb:
                if let atb = statisticsStore.atb {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: atb))
                }
            case .atbVariant:
                if let variant = statisticsStore.variant {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: variant))
                }
            case .osVersion:
                let os = ProcessInfo().operatingSystemVersion
                let version = "\(os.majorVersion)"

                queryItems.append(URLQueryItem(name: parameter.rawValue, value: version))
            case .appVersion:
                queryItems.append(URLQueryItem(name: parameter.rawValue, value: AppVersion.shared.versionAndBuildNumber))
            case .hardwareModel:
                let model = hardwareModel().addingPercentEncoding(withAllowedCharacters: .alphanumerics)
                queryItems.append(URLQueryItem(name: parameter.rawValue, value: model))
            case .daysInstalled:
                if let installDate = statisticsStore.installDate,
                   let daysSinceInstall = Calendar.current.numberOfDaysBetween(installDate, and: Date()) {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(describing: daysSinceInstall)))
                }
            case .locale:
                let formattedLocale = LocaleMatchingAttribute.localeIdentifierAsJsonFormat(localeIdentifier)
                queryItems.append(URLQueryItem(name: parameter.rawValue, value: formattedLocale))
            case .privacyProStatus:
                if let privacyProStatusSurveyParameter = subscription?.privacyProStatusSurveyParameter {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: privacyProStatusSurveyParameter))
                }
            case .privacyProPlatform:
                if let privacyProPlatformSurveyParameter = subscription?.privacyProPlatformSurveyParameter {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: privacyProPlatformSurveyParameter))
                }
            case .privacyProBilling:
                if let privacyProBillingSurveyParameter = subscription?.privacyProBillingSurveyParameter {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: privacyProBillingSurveyParameter))
                }

            case .privacyProDaysSincePurchase:
                if let startDate = subscription?.startedAt,
                   let daysSincePurchase = Calendar.current.numberOfDaysBetween(startDate, and: Date()) {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(describing: daysSincePurchase)))
                }
            case .privacyProDaysUntilExpiry:
                if let expiryDate = subscription?.expiresOrRenewsAt,
                   let daysUntilExpiry = Calendar.current.numberOfDaysBetween(Date(), and: expiryDate) {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(describing: daysUntilExpiry)))
                }
            case .vpnFirstUsed:
                if let vpnFirstUsed = vpnActivationDateStore.daysSinceActivation() {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(describing: vpnFirstUsed)))
                }
            case .vpnLastUsed:
                if let vpnLastUsed = vpnActivationDateStore.daysSinceLastActive() {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(describing: vpnLastUsed)))
                }
            }
        }

        components.queryItems = queryItems

        return components.url ?? surveyURL
    }

    private func hardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        return identifier
    }

}

extension PrivacyProSubscription {
    var privacyProStatusSurveyParameter: String {
        switch status {
        case .autoRenewable:
            return "auto_renewable"
        case .notAutoRenewable:
            return "not_auto_renewable"
        case .gracePeriod:
            return "grace_period"
        case .inactive:
            return "inactive"
        case .expired:
            return "expired"
        case .unknown:
            return "unknown"
        }
    }

    var privacyProPlatformSurveyParameter: String {
        switch platform {
        case .apple:
            return "apple"
        case .google:
            return "google"
        case .stripe:
            return "stripe"
        case .unknown:
            return "unknown"
        }
    }

    var privacyProBillingSurveyParameter: String {
        switch billingPeriod {
        case .monthly:
            return "monthly"
        case .yearly:
            return "yearly"
        case .unknown:
            return "unknown"
        }
    }
}
