//
//  NewBadgeVisibilityManager.swift
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
import Core
import Persistence
import PrivacyConfig

enum NewBadgeFeature: Hashable {
    case personalInformationRemoval

    var firstImpressionDateStorageKey: String {
        switch self {
        case .personalInformationRemoval: return "firstImpressionDatePIRNewBadge"
        }
    }
}

/// The NEW badge, once activated (through a subfeature flag), is displayed
/// for `displayDurationDays` total, with the clock starting at the first impression,
/// and within a `maxMinorReleaseOffset` app version
///
/// Defaults to 7 days and 3 minor releases
protocol NewBadgeConfigProviding {
    func isFeatureOn(_ feature: NewBadgeFeature) -> Bool
    func isWithinReleaseWindow(for feature: NewBadgeFeature, currentAppVersion: String) -> Bool

    func maxMinorReleaseOffset(for feature: NewBadgeFeature) -> Int
    func displayDurationDays(for feature: NewBadgeFeature) -> Int
}

extension NewBadgeConfigProviding {
    func maxMinorReleaseOffset(for feature: NewBadgeFeature) -> Int { 3 }
    func displayDurationDays(for feature: NewBadgeFeature) -> Int { 7 }
}

protocol NewBadgeVisibilityManaging {
    func shouldShowBadge(for feature: NewBadgeFeature) -> Bool
    func storeFirstImpressionDateIfNeeded(for feature: NewBadgeFeature)
}

final class NewBadgeVisibilityManager: NewBadgeVisibilityManaging {

    private let keyValueStore: ThrowingKeyValueStoring
    private let configProvider: NewBadgeConfigProviding
    private let currentAppVersionProvider: () -> String
    private let currentDateProvider: () -> Date
    private let calendar: Calendar

    init(keyValueStore: ThrowingKeyValueStoring,
         configProvider: NewBadgeConfigProviding,
         currentAppVersionProvider: @escaping () -> String,
         currentDateProvider: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.keyValueStore = keyValueStore
        self.configProvider = configProvider
        self.currentAppVersionProvider = currentAppVersionProvider
        self.currentDateProvider = currentDateProvider
        self.calendar = calendar
    }

    func shouldShowBadge(for feature: NewBadgeFeature) -> Bool {
        guard configProvider.isFeatureOn(feature) else { return false }
        guard configProvider.isWithinReleaseWindow(for: feature, currentAppVersion: currentAppVersionProvider()) else { return false }

        let displayDurationDays = configProvider.displayDurationDays(for: feature)
        guard displayDurationDays > 0 else { return false }

        guard let firstDate = firstImpressionDate(for: feature) else { return true }

        let elapsedDays = calendar.dateComponents([.day],
                                                  from: calendar.startOfDay(for: firstDate),
                                                  to: calendar.startOfDay(for: currentDateProvider())).day ?? Int.max
        return elapsedDays < displayDurationDays
    }

    func storeFirstImpressionDateIfNeeded(for feature: NewBadgeFeature) {
        guard shouldShowBadge(for: feature) else { return }
        guard firstImpressionDate(for: feature) == nil else { return }

        try? keyValueStore.set(currentDateProvider(), forKey: feature.firstImpressionDateStorageKey)
    }

    private func firstImpressionDate(for feature: NewBadgeFeature) -> Date? {
        try? keyValueStore.object(forKey: feature.firstImpressionDateStorageKey) as? Date
    }
}

struct DefaultNewBadgeConfigProvider: NewBadgeConfigProviding {

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    func isFeatureOn(_ feature: NewBadgeFeature) -> Bool {
        switch feature {
        case .personalInformationRemoval:
            return featureFlagger.isFeatureOn(.personalInformationRemoval) && privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(DBPSubfeature.goToMarket)
        }
    }

    private func minSupportedVersion(for feature: NewBadgeFeature) -> String? {
        guard let configurationData = try? PrivacyConfigurationData(data: privacyConfigurationManager.currentConfig) else {
            return nil
        }

        switch feature {
        case .personalInformationRemoval:
            return configurationData.features[DBPSubfeature.goToMarket.parent.rawValue]?
                .features[DBPSubfeature.goToMarket.rawValue]?
                .minSupportedVersion
        }
    }

    func isWithinReleaseWindow(for feature: NewBadgeFeature, currentAppVersion: String) -> Bool {
        guard let minimumVersion = minSupportedVersion(for: feature) else {
            return false
        }

        let minVersion = parse(versionString: minimumVersion)
        let currentVersion = parse(versionString: currentAppVersion)

        guard let maxVersion = maximumVersion(from: minVersion, byMinorReleaseOffset: maxMinorReleaseOffset(for: feature)) else {
            return false
        }

        return compareVersions(minVersion, currentVersion) != .orderedDescending && compareVersions(currentVersion, maxVersion) == .orderedAscending
    }

    private func parse(versionString: String) -> [Int] {
        versionString.split(separator: ".").map { Int($0) ?? 0 }
    }

    private func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let lhsSegment = index < lhs.count ? lhs[index] : 0
            let rhsSegment = index < rhs.count ? rhs[index] : 0

            if lhsSegment < rhsSegment {
                return .orderedAscending
            }
            if lhsSegment > rhsSegment {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private func maximumVersion(from minimumVersion: [Int], byMinorReleaseOffset offset: Int) -> [Int]? {
        guard minimumVersion.count == 3 else { return nil }

        var result = minimumVersion
        result[1] += offset
        result[2] = 0

        return result
    }
}
