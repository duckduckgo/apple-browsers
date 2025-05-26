//
//  PrivacyConfiguration.swift
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

public enum PrivacyConfigurationFeatureState: Equatable {
    case enabled
    case disabled(PrivacyConfigurationFeatureDisabledReason)
}

public enum PrivacyConfigurationFeatureDisabledReason: Equatable {
    case featureMissing
    case disabledInConfig
    case appVersionNotSupported
    case tooOldInstallation
    case limitedToInternalUsers
    case stillInRollout
    case targetDoesNotMatch
    case experimentCohortDoesNotMatch
}

public protocol PrivacyConfiguration {

    /// Identifier of given Privacy Configuration, typically an ETag
    var identifier: String { get }

    /// Version of config parsed from the `version` key
    var version: String? { get }

    /// Domains for which user has toggled protection off.
    ///
    /// Use `isUserUnprotected(domain:)` to check if given domain is unprotected.
    var userUnprotectedDomains: [String] { get }

    /// Domains for which all protections has been disabled because of some broken functionality
    ///
    /// Use `isTempUnprotected(domain:)` to check if given domain is unprotected.
    var tempUnprotectedDomains: [String] { get }

    /// Trackers that has been allow listed because of site breakage
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist { get }

    /// Checks if a given feature is enabled for a given version, allowing a default value to be set in the case that there is no definition for that feature on the config
    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider, defaultValue: Bool) -> Bool

    /// Returns the state of a given feature for a given version
    func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState

    /// Checks if a given feature is enabled for a given version, allowing a default value to be set in the case that there is no definition for that feature on the config
    func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool

    /// Returns the state of a given subfeature for a given version
    func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState

    /// Domains for which given PrivacyFeature is disabled.
    ///
    /// Use `isTempUnprotected(domain:)` to check if a feature is disabled for the given domain.
    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String]

    /// Check the protection status of given domain.
    ///
    /// Returns true if all below is true:
    ///  - Domain is not user unprotected.
    ///  - Domain is not in temp list.
    ///  - Domain is not in an exception list for content blocking feature.
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool

    /// Check the protection status of given domain.
    ///
    /// Returns true if all below is true:
    ///  - Domain is not user unprotected.
    ///  - Domain is not in temp list.
    ///  - Domain is not in an exception list for content blocking feature.
    func isProtected(domain: String?) -> Bool

    /// Check if given domain is locally unprotected.
    ///
    /// Returns true for exact match, but false for subdomains.
    func isUserUnprotected(domain: String?) -> Bool

    /// Check if given domain is temp unprotected.
    ///
    /// Returns true for exact match and all subdomains.
    func isTempUnprotected(domain: String?) -> Bool

    /// Check if given domain is in exception list.
    ///
    /// Returns true for exact match and all subdomains.
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool

    /// Returns settings for a specified feature.
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings

    /// Returns settings for a specified subfeature.
    func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings?

    /// Removes given domain from locally unprotected list.
    func userEnabledProtection(forDomain: String)
    /// Adds given domain to locally unprotected list.
    func userDisabledProtection(forDomain: String)

    // APIs used for Experiments
    func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState

    func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]?

    func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]?
}

public extension PrivacyConfiguration {
    func isEnabled(featureKey: PrivacyFeature, defaultValue: Bool = false) -> Bool {
        return isEnabled(featureKey: featureKey, versionProvider: AppVersionProvider(), defaultValue: defaultValue)
    }

    func stateFor(featureKey: PrivacyFeature) -> PrivacyConfigurationFeatureState {
        return stateFor(featureKey: featureKey, versionProvider: AppVersionProvider())
    }

    func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, randomizer: (Range<Double>) -> Double = Double.random(in:), defaultValue: Bool = false) -> Bool {
        return isSubfeatureEnabled(subfeature, versionProvider: AppVersionProvider(), randomizer: randomizer, defaultValue: defaultValue)
    }

    func stateFor(_ subfeature: any PrivacySubfeature, randomizer: (Range<Double>) -> Double = Double.random(in:)) -> PrivacyConfigurationFeatureState {
        return stateFor(subfeature, versionProvider: AppVersionProvider(), randomizer: randomizer)
    }

    func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, randomizer: (Range<Double>) -> Double = Double.random(in:)) -> PrivacyConfigurationFeatureState {
        return stateFor(subfeatureID: subfeatureID, parentFeatureID: parentFeatureID, versionProvider: AppVersionProvider(), randomizer: randomizer)
    }

}
