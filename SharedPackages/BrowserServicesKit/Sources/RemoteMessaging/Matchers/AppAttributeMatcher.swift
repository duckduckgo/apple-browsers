//
//  AppAttributeMatcher.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Common
import BrowserServicesKit

#if os(iOS)
public typealias AppAttributeMatcher = MobileAppAttributeMatcher
#elseif os(macOS)
public typealias AppAttributeMatcher = DesktopAppAttributeMatcher
#endif

public typealias MobileAppAttributeMatcher = CommonAppAttributeMatcher

public struct DesktopAppAttributeMatcher: AttributeMatching {
    private let isInstalledMacAppStore: Bool

    private let commonAppAttributeMatcher: CommonAppAttributeMatcher

    public init(statisticsStore: StatisticsStore, variantManager: VariantManager, isInternalUser: Bool = true, isInstalledMacAppStore: Bool) {
        self.isInstalledMacAppStore = isInstalledMacAppStore

        commonAppAttributeMatcher = .init(statisticsStore: statisticsStore, variantManager: variantManager, isInternalUser: isInternalUser)
    }

    public init(
        bundleId: String,
        appVersion: String,
        isInternalUser: Bool,
        statisticsStore: StatisticsStore,
        variantManager: VariantManager,
        isInstalledMacAppStore: Bool
    ) {
        self.isInstalledMacAppStore = isInstalledMacAppStore

        commonAppAttributeMatcher = .init(
            bundleId: bundleId,
            appVersion: appVersion,
            isInternalUser: isInternalUser,
            statisticsStore: statisticsStore,
            variantManager: variantManager
        )
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as IsInstalledMacAppStoreMatchingAttribute:
            return matchingAttribute.evaluate(for: isInstalledMacAppStore)
        default:
            return commonAppAttributeMatcher.evaluate(matchingAttribute: matchingAttribute)
        }
    }
}

public struct CommonAppAttributeMatcher: AttributeMatching {

    private let bundleId: String
    private let appVersion: String
    private let isInternalUser: Bool
    private let statisticsStore: StatisticsStore
    private let variantManager: VariantManager

    public init(statisticsStore: StatisticsStore, variantManager: VariantManager, isInternalUser: Bool = true) {
        if AppVersion.shared.identifier.isEmpty {
            assertionFailure("BundleIdentifier should not be empty")
        }
        self.init(bundleId: AppVersion.shared.identifier,
                  appVersion: AppVersion.shared.versionNumber,
                  isInternalUser: isInternalUser,
                  statisticsStore: statisticsStore,
                  variantManager: variantManager)
    }

    public init(bundleId: String, appVersion: String, isInternalUser: Bool, statisticsStore: StatisticsStore, variantManager: VariantManager) {
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.isInternalUser = isInternalUser
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as IsInternalUserMatchingAttribute:
            return matchingAttribute.evaluate(for: isInternalUser)
        case let matchingAttribute as AppIdMatchingAttribute:
            guard matchingAttribute.value?.isEmpty == false else {
                return .fail
            }
            return matchingAttribute.evaluate(for: bundleId)
        case let matchingAttribute as AppVersionMatchingAttribute:
            return matchingAttribute.evaluate(for: appVersion)
        case let matchingAttribute as AtbMatchingAttribute:
            return matchingAttribute.evaluate(for: statisticsStore.atb)
        case let matchingAttribute as AppAtbMatchingAttribute:
            return matchingAttribute.evaluate(for: statisticsStore.appRetentionAtb)
        case let matchingAttribute as SearchAtbMatchingAttribute:
            return matchingAttribute.evaluate(for: statisticsStore.searchRetentionAtb)
        case let matchingAttribute as ExpVariantMatchingAttribute:
            return matchingAttribute.evaluate(for: variantManager.currentVariant?.name)
        default:
            return nil
        }
    }
}
