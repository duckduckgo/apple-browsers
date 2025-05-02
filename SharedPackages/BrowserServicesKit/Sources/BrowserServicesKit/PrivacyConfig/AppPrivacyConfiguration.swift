//
//  AppPrivacyConfiguration.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public struct AppPrivacyConfiguration: PrivacyConfiguration {

    private enum Constants {
        static let enabledKey = "enabled"
        static let lastRolloutCountKey = "lastRolloutCount"
        static let installedDaysKey = "installedDays"
    }

    private(set) public var identifier: String

    private let data: PrivacyConfigurationData
    private let locallyUnprotected: DomainsProtectionStore
    private let internalUserDecider: InternalUserDecider
    private let userDefaults: UserDefaults
    private let locale: Locale
    private let installDate: Date?
    static let experimentManagerQueue = DispatchQueue(label: "com.experimentManager.queue")

    public init(data: PrivacyConfigurationData,
                identifier: String,
                localProtection: DomainsProtectionStore,
                internalUserDecider: InternalUserDecider,
                userDefaults: UserDefaults = UserDefaults(),
                locale: Locale = Locale.current,
                installDate: Date? = nil) {
        self.data = data
        self.identifier = identifier
        self.locallyUnprotected = localProtection
        self.internalUserDecider = internalUserDecider
        self.userDefaults = userDefaults
        self.locale = locale
        self.installDate = installDate
    }

    public var version: String? {
        return data.version
    }

    public var userUnprotectedDomains: [String] {
        return Array(locallyUnprotected.unprotectedDomains).normalizedDomainsForContentBlocking().sorted()
    }

    public var tempUnprotectedDomains: [String] {
        return data.unprotectedTemporary.map { $0.domain }.normalizedDomainsForContentBlocking()
    }

    public var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist {
        return data.trackerAllowlist
    }

    func parse(versionString: String) -> [Int] {
        return versionString.split(separator: ".").map { Int($0) ?? 0 }
    }

    func satisfiesMinVersion(_ version: String?,
                             versionProvider: AppVersionProvider) -> Bool {
        if let minSupportedVersion = version,
           let appVersion = versionProvider.appVersion() {
            let minVersion = parse(versionString: minSupportedVersion)
            let currentVersion = parse(versionString: appVersion)

            for i in 0..<max(minVersion.count, currentVersion.count) {
                let minSegment = i < minVersion.count ? minVersion[i] : 0
                let currSegment = i < currentVersion.count ? currentVersion[i] : 0

                if currSegment > minSegment {
                    return true
                }
                if currSegment < minSegment {
                    return false
                }
            }
        }

        return true
    }

    func satisfiesInstalledDays(_ featureKey: PrivacyFeature, installDate: Date?) -> Bool {
        // if the key is not present, then feature is enabled by default
        guard let installedDays = settings(for: featureKey)[Constants.installedDaysKey] else { return true }

        if let installedDaysCount = installedDays as? Int,
           let installDate = installDate,
           let daysSinceInstall = Calendar.current.numberOfDaysBetween(installDate, and: Date()) {
            return daysSinceInstall <= installedDaysCount
        }

        return false
    }

    public func isEnabled(featureKey: PrivacyFeature,
                          versionProvider: AppVersionProvider = AppVersionProvider(),
                          defaultValue: Bool = false) -> Bool {
        switch stateFor(featureKey: featureKey, versionProvider: versionProvider) {
        case .enabled:
            return true
        case .disabled(.featureMissing):
            return defaultValue
        case .disabled:
            return false
        }
    }

    public func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState {
        guard let feature = data.features[featureKey.rawValue] else { return .disabled(.featureMissing) }

        let satisfiesMinVersion = satisfiesMinVersion(feature.minSupportedVersion, versionProvider: versionProvider)
        let satisfiesInstalledDays = satisfiesInstalledDays(featureKey, installDate: installDate)

        switch feature.state {
        case PrivacyConfigurationData.State.enabled:
            guard satisfiesMinVersion else { return .disabled(.appVersionNotSupported) }
            guard satisfiesInstalledDays else { return .disabled(.tooOldInstallation) }

            return .enabled
        case PrivacyConfigurationData.State.internal:
            guard internalUserDecider.isInternalUser else { return .disabled(.limitedToInternalUsers) }
            guard satisfiesMinVersion else { return .disabled(.appVersionNotSupported) }
            guard satisfiesInstalledDays else { return .disabled(.tooOldInstallation) }

            return .enabled
        default: return .disabled(.disabledInConfig)
        }
    }

    private func isRolloutEnabled(subfeatureID: SubfeatureID,
                                  parentID: ParentFeatureID,
                                  rolloutSteps: [PrivacyConfigurationData.PrivacyFeature.Feature.RolloutStep],
                                  randomizer: (Range<Double>) -> Double) -> Bool {
        // Empty rollouts should be default enabled
        guard !rolloutSteps.isEmpty else { return true }

        let defsPrefix = "config.\(parentID).\(subfeatureID)"
        if userDefaults.bool(forKey: "\(defsPrefix).\(Constants.enabledKey)") {
            return true
        }

        var willEnable = false
        let rollouts = Array(Set(rolloutSteps.filter({ $0.percent >= 0.0 && $0.percent <= 100.0 }))).sorted(by: { $0.percent < $1.percent })
        if let rolloutSize = userDefaults.value(forKey: "\(defsPrefix).\(Constants.lastRolloutCountKey)") as? Int {
            guard rolloutSize < rollouts.count else { return false }
            // Sanity check as we need at least two values to compute the new probability
            guard rollouts.count > 1 else { return false }

            // If the user has seen the rollout before, and the rollout count has changed
            // Try again with the new probability
            let y = rollouts[rollouts.count - 1].percent
            let x = rollouts[rollouts.count - 2].percent
            let prob = (y - x) / (100.0 - x)
            if randomizer(0..<1) < prob {
                // enable the feature
                willEnable = true
            }
        } else {
            // First time user sees feature
            let probability = (rollouts.count > 1 ? rollouts.last?.percent : rollouts.first?.percent) ?? 0.0
            willEnable = randomizer(0..<100) < probability
        }

        guard willEnable else {
            userDefaults.set(rollouts.count, forKey: "\(defsPrefix).\(Constants.lastRolloutCountKey)")
            return false
        }

        userDefaults.set(true, forKey: "\(defsPrefix).\(Constants.enabledKey)")
        return true
    }

    public func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool {
        switch stateFor(subfeature, versionProvider: versionProvider, randomizer: randomizer) {
        case .enabled:
            return true
        case .disabled(.featureMissing):
            return defaultValue
        case .disabled:
            return false
        }
    }

    public func stateFor(_ subfeature: any PrivacySubfeature,
                         versionProvider: AppVersionProvider,
                         randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        guard let subfeatureData = subfeatures(for: subfeature.parent)[subfeature.rawValue] else {
            return .disabled(.featureMissing)
        }

        return stateFor(subfeatureID: subfeature.rawValue, subfeatureData: subfeatureData, parentFeature: subfeature.parent, versionProvider: versionProvider, randomizer: randomizer)
    }

    private func stateFor(subfeatureID: SubfeatureID,
                          subfeatureData: PrivacyConfigurationData.PrivacyFeature.Feature,
                          parentFeature: PrivacyFeature,
                          versionProvider: AppVersionProvider,
                          randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        // Step 1: Check parent feature state
        let parentState = stateFor(featureKey: parentFeature, versionProvider: versionProvider)
        guard case .enabled = parentState else { return parentState }

        // Step 2: Check  version
        let satisfiesMinVersion = satisfiesMinVersion(subfeatureData.minSupportedVersion, versionProvider: versionProvider)

        // Step 3: Check sub-feature state
        switch subfeatureData.state {
        case PrivacyConfigurationData.State.enabled:
            guard satisfiesMinVersion else { return .disabled(.appVersionNotSupported) }
        case PrivacyConfigurationData.State.internal:
            guard internalUserDecider.isInternalUser else { return .disabled(.limitedToInternalUsers) }
            guard satisfiesMinVersion else { return .disabled(.appVersionNotSupported) }
        default: return .disabled(.disabledInConfig)
        }

        // Step 4: Handle Rollouts
        if let rollout = subfeatureData.rollout,
           !isRolloutEnabled(subfeatureID: subfeatureID, parentID: parentFeature.rawValue, rolloutSteps: rollout.steps, randomizer: randomizer) {
            return .disabled(.stillInRollout)
        }

        // Step 5: Check Targets
        return checkTargets(subfeatureData)
    }

    private func checkTargets(_ subfeatureData: PrivacyConfigurationData.PrivacyFeature.Feature?) -> PrivacyConfigurationFeatureState {
        // Check Targets
        if let targets = subfeatureData?.targets, !matchTargets(targets: targets){
            return .disabled(.targetDoesNotMatch)
        }
        return .enabled
    }

    private func matchTargets(targets: [PrivacyConfigurationData.PrivacyFeature.Feature.Target]) -> Bool {
        targets.contains { target in
            (target.localeCountry == nil || target.localeCountry == locale.regionCode) &&
            (target.localeLanguage == nil || target.localeLanguage == locale.languageCode)
        }
    }

    private func subfeatures(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.Features {
        return data.features[feature.rawValue]?.features ?? [:]
    }

    public func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] {
        guard let feature = data.features[featureKey.rawValue] else { return [] }

        return feature.exceptions.map { $0.domain }.normalizedDomainsForContentBlocking()
    }

    public func isFeature(_ feature: PrivacyFeature, enabledForDomain domain: String?) -> Bool {
        guard isEnabled(featureKey: feature) else {
            return false
        }

        if let domain = domain,
           isTempUnprotected(domain: domain) ||
            isUserUnprotected(domain: domain) ||
            isInExceptionList(domain: domain, forFeature: feature) {
            return false
        }
        return true
    }

    public func isProtected(domain: String?) -> Bool {
        guard let domain = domain else { return true }

        return !isTempUnprotected(domain: domain) && !isUserUnprotected(domain: domain) &&
        !isInExceptionList(domain: domain, forFeature: .contentBlocking)
    }

    public func isUserUnprotected(domain: String?) -> Bool {
        guard let domain = domain else { return false }

        return userUnprotectedDomains.contains(domain)
    }

    public func isTempUnprotected(domain: String?) -> Bool {
        return isDomain(domain, wildcardMatching: tempUnprotectedDomains)
    }

    public func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool {
        return isDomain(domain, wildcardMatching: exceptionsList(forFeature: featureKey))
    }

    private func isDomain(_ domain: String?, wildcardMatching domainsList: [String]) -> Bool {
        guard let domain = domain else { return false }

        let trimmedDomains = domainsList.filter { !$0.trimmingWhitespace().isEmpty }

        // Break domain apart to handle www.*
        var tempDomain = domain
        while tempDomain.contains(".") {
            if trimmedDomains.contains(tempDomain) {
                return true
            }

            let comps = tempDomain.split(separator: ".")
            tempDomain = comps.dropFirst().joined(separator: ".")
        }

        return false
    }

    public func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        return data.features[feature.rawValue]?.settings ?? [:]
    }

    public func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        guard let subfeatureData = subfeatures(for: subfeature.parent)[subfeature.rawValue] else {
            return nil
        }
        return subfeatureData.settings
    }

    public func userEnabledProtection(forDomain domain: String) {
        let domainToRemove = locallyUnprotected.unprotectedDomains.first { unprotectedDomain in
            unprotectedDomain.punycodeEncodedHostname.lowercased() == domain
        }
        locallyUnprotected.enableProtection(forDomain: domainToRemove ?? domain)
    }

    public func userDisabledProtection(forDomain domain: String) {
        locallyUnprotected.disableProtection(forDomain: domain.punycodeEncodedHostname.lowercased())
    }
}

extension AppPrivacyConfiguration {

    public func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider,
                         randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        guard let parentFeature = PrivacyFeature(rawValue: parentFeatureID) else { return .disabled(.featureMissing) }
        guard let subfeatureData = subfeatures(for: parentFeature)[subfeatureID] else { return .disabled(.featureMissing) }
        return stateFor(subfeatureID: subfeatureID, subfeatureData: subfeatureData, parentFeature: parentFeature, versionProvider: versionProvider, randomizer: randomizer)
    }

    public func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
        subfeatures(for: subfeature.parent)[subfeature.rawValue]?.cohorts
    }

    public func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
        guard let parentFeature = PrivacyFeature(rawValue: parentFeatureID) else { return nil }
        return subfeatures(for: parentFeature)[subfeatureID]?.cohorts
    }
}

extension Array where Element == String {

    func normalizedDomainsForContentBlocking() -> [String] {
        map { domain in
            domain.punycodeEncodedHostname.lowercased()
        }
    }
}
