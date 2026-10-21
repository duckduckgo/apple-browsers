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
import FoundationExtensions
import Foundation

public protocol VPNActivationDateProviding {
    func daysSinceActivation() -> Int?
    func daysSinceLastActive() -> Int?
}

public struct DefaultRemoteMessagingSurveyURLBuilder: RemoteMessagingSurveyActionMapping {

    private let statisticsStore: StatisticsStore
    private let vpnActivationDateStore: VPNActivationDateProviding
    private let subscriptionDataProvider: SubscriptionSurveyDataProviding?
    private let localeIdentifier: String
    private let autofillUsageStore: AutofillUsageStore?
    private let featureDiscovery: FeatureDiscovery?

    public init(statisticsStore: StatisticsStore,
                vpnActivationDateStore: VPNActivationDateProviding,
                subscriptionDataProvider: SubscriptionSurveyDataProviding?,
                localeIdentifier: String = Locale.current.identifier,
                autofillUsageStore: AutofillUsageStore?,
                featureDiscovery: FeatureDiscovery? = nil) {
        self.statisticsStore = statisticsStore
        self.vpnActivationDateStore = vpnActivationDateStore
        self.subscriptionDataProvider = subscriptionDataProvider
        self.localeIdentifier = localeIdentifier
        self.autofillUsageStore = autofillUsageStore
        self.featureDiscovery = featureDiscovery
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
            case .lastDuckAIUsage:
                let daysSinceLastUsed = featureDiscovery?.daysSinceLastUsed(.aiChat)
                queryItems.append(URLQueryItem(name: parameter.rawValue, value: Self.usageState(daysSinceLastUsage: daysSinceLastUsed)))
            case .lastSearchState:
                queryItems.append(URLQueryItem(name: parameter.rawValue, value: Self.searchState(lastSearchDate: autofillUsageStore?.searchDauDate)))
            case .locale:
                let formattedLocale = LocaleMatchingAttribute.localeIdentifierAsJsonFormat(localeIdentifier)
                queryItems.append(URLQueryItem(name: parameter.rawValue, value: formattedLocale))
            case .subscriptionStatus:
                if let status = subscriptionDataProvider?.subscriptionStatus {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: status))
                }
            case .subscriptionPlatform:
                if let platform = subscriptionDataProvider?.subscriptionPlatform {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: platform))
                }
            case .subscriptionBilling:
                if let billing = subscriptionDataProvider?.subscriptionBilling {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: billing))
                }
            case .subscriptionTier:
                if let tier = subscriptionDataProvider?.subscriptionTier {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: tier))
                }
            case .subscriptionTrialActive:
                if let trialActive = subscriptionDataProvider?.subscriptionTrialActive {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(trialActive)))
                }
            case .subscriptionDaysSincePurchase:
                if let startDate = subscriptionDataProvider?.subscriptionStartDate,
                   let daysSincePurchase = Calendar.current.numberOfDaysBetween(startDate, and: Date()) {
                    queryItems.append(URLQueryItem(name: parameter.rawValue, value: String(describing: daysSincePurchase)))
                }
            case .subscriptionDaysUntilExpiry:
                if let expiryDate = subscriptionDataProvider?.subscriptionExpiryDate,
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

    private static func searchState(lastSearchDate: Date?) -> String {
        guard let lastSearchDate = lastSearchDate else {
            return "none"
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfLast = calendar.startOfDay(for: lastSearchDate)
        let daysApart = calendar
            .dateComponents([.day], from: startOfLast, to: startOfToday)
            .day ?? Int.max

        return usageState(daysSinceLastUsage: daysApart)
    }

    private static func usageState(daysSinceLastUsage: Int?) -> String {
        guard let daysSinceLastUsage else {
            return "none"
        }

        switch daysSinceLastUsage {
        case 0...1:
            return "day"
        case 2...7:
            return "week"
        default:
            return "none"
        }
    }

    public static func refreshLastSearchState(in urlString: String, lastSearchDate: Date?) -> String {
        refreshUsageStates(in: urlString,
                           updatedStates: [.lastSearchState: searchState(lastSearchDate: lastSearchDate)])
    }

    public static func refreshSurveyUsageStates(in urlString: String, lastSearchDate: Date?, daysSinceDuckAIUsed: Int?) -> String {
        refreshUsageStates(
            in: urlString,
            updatedStates: [
                .lastDuckAIUsage: usageState(daysSinceLastUsage: daysSinceDuckAIUsed),
                .lastSearchState: searchState(lastSearchDate: lastSearchDate)
            ]
        )
    }

    private static func refreshUsageStates(in urlString: String, updatedStates: [RemoteMessagingSurveyActionParameter: String]) -> String {
        guard var components = URLComponents(string: urlString),
              let queryItems = components.queryItems else {
            return urlString
        }

        var didUpdateState = false
        components.queryItems = queryItems.map { queryItem in
            guard let parameter = RemoteMessagingSurveyActionParameter(rawValue: queryItem.name),
                  let updatedState = updatedStates[parameter] else {
                return queryItem
            }

            didUpdateState = true
            return URLQueryItem(name: queryItem.name, value: updatedState)
        }

        guard didUpdateState else {
            return urlString
        }

        return components.url?.absoluteString ?? urlString
    }
}
