//
//  MockPrivacyConfiguration.swift
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

import PrivacyConfig

public class MockPrivacyConfiguration: PrivacyConfiguration {

    public init() {}

    public var isFeatureEnabledCheck: ((PrivacyFeature, AppVersionProvider) -> Bool)?
    public var isSubfeatureEnabledCheck: ((any PrivacySubfeature, AppVersionProvider) -> Bool)?

    public func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider, defaultValue: Bool) -> Bool {
        isFeatureEnabledCheck?(featureKey, versionProvider) ?? true
    }

    public func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool {
        isSubfeatureEnabledCheck?(subfeature, versionProvider) ?? false
    }

    public func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState {
        return .enabled
    }

    public func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        if isSubfeatureEnabledCheck?(subfeature, versionProvider) == true {
            return .enabled
        }
        return .disabled(.disabledInConfig)
    }

    public func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        return .enabled
    }

    public func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    public func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    public func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        featureSettings
    }

    public func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        subfeatureSettings
    }

    public var exceptionsList: (PrivacyFeature) -> [String] = { _ in [] }
    public var featureSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings = [:]
    public var subfeatureSettings: PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings?

    public var identifier: String = "abcd"
    public var version: String? = "123456789"
    public var userUnprotectedDomains: [String] = []
    public var tempUnprotectedDomains: [String] = []
    public var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(json: ["state": "disabled"])!
    public func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { [] }
    public func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    public func isProtected(domain: String?) -> Bool { false }
    public func isUserUnprotected(domain: String?) -> Bool { false }
    public func isTempUnprotected(domain: String?) -> Bool { false }
    public func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    public func userEnabledProtection(forDomain: String) {}
    public func userDisabledProtection(forDomain: String) {}
}
