//
//  TrackerDataURLOverriderTests.swift
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

import XCTest
import BrowserServicesKit
import Configuration
import Combine

final class TrackerDataURLOverriderTests: XCTestCase {
    private var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!
    private var mockFeatureFlagger: MockFeatureFlaggerMockSettings!
    private var urlProvider: TrackerDataURLProviding!
    let controlURL = "control/url.json"
    let treatmentURL = "treatment/url.json"

    override func setUp() {
        super.setUp()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager()
        mockFeatureFlagger = MockFeatureFlaggerMockSettings()
        urlProvider = TrackerDataURLOverrider(privacyConfigurationManager: mockPrivacyConfigurationManager, featureFlagger: mockFeatureFlagger)
    }

    override func tearDown() {
        urlProvider = nil
        mockPrivacyConfigurationManager = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    func testTrackerDataURL_forControlCohort_returnsControlUrl() throws {
        // GIVEN
        mockFeatureFlagger.mockCohorts = [
            TDSExperimentType.allCases[0].rawValue: TDSExperimentType.Cohort.control]
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.subfeatureSettings = "{ \"controlUrl\": \"\(controlURL)\", \"treatmentUrl\": \"\(treatmentURL)\"}"
        mockPrivacyConfigurationManager.privacyConfig = privacyConfig

        // WHEN
        let url = try XCTUnwrap(urlProvider.trackerDataURL)

        // THEN
        XCTAssertEqual(url.absoluteString, TrackerDataURLOverrider.Constants.baseTDSURLString + controlURL)
    }

    func testTrackerDataURL_forTreatmentCohort_returnsTreatmentUrl() throws {
        // GIVEN
        mockFeatureFlagger.mockCohorts = [
            TDSExperimentType.value(at: 0)!.rawValue: TDSExperimentType.Cohort.treatment]
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.subfeatureSettings = "{ \"controlUrl\": \"\(controlURL)\", \"treatmentUrl\": \"\(treatmentURL)\"}"
        mockPrivacyConfigurationManager.privacyConfig = privacyConfig

        // WHEN
        let url = try XCTUnwrap(urlProvider.trackerDataURL)

        // THEN
        XCTAssertEqual(url.absoluteString, TrackerDataURLOverrider.Constants.baseTDSURLString + treatmentURL)
    }

    func testTrackerDataURL_ifNoSettings_returnsDefaultURL() throws {
        // GIVEN
        mockFeatureFlagger.mockCohorts = [
            TDSExperimentType.value(at: 0)!.rawValue: TDSExperimentType.Cohort.treatment]
        let privacyConfig = MockPrivacyConfiguration()
        mockPrivacyConfigurationManager.privacyConfig = privacyConfig

        // WHEN
        let url = urlProvider.trackerDataURL

        // THEN
        XCTAssertNil(url)
    }

    func testTrackerDataURL_ifNoCohort_returnsDefaultURL() {
        // GIVEN
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.subfeatureSettings = "{ \"controlUrl\": \"\(controlURL)\", \"treatmentUrl\": \"\(treatmentURL)\"}"
        mockPrivacyConfigurationManager.privacyConfig = privacyConfig

        // WHEN
        let url = urlProvider.trackerDataURL

        // THEN
        XCTAssertNil(url)
    }

    func test_trackerDataURL_returnsFirstAvailableCohortURL() throws {
        // GIVEN: Multiple experiments, only the second one has a valid cohort.
        let firstExperimentControlURL = "first-control.json"
        let secondExperimentTreatmentURL = "second-treatment.json"
        let thirdExperimentTreatmentURL = "third-treatment.json"
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.mockSubfeatureSettings = [
            TDSExperimentType.value(at: 0)!.rawValue: """
            {
                "controlUrl": "\(firstExperimentControlURL)",
                "treatmentUrl": "first-treatment.json"
            }
            """,
            TDSExperimentType.value(at: 1)!.subfeature.rawValue: """
            {
                "controlUrl": "second-control.json",
                "treatmentUrl": "\(secondExperimentTreatmentURL)"
            }
            """,
            TDSExperimentType.value(at: 2)!.subfeature.rawValue: """
            {
                "controlUrl": "third-control.json",
                "treatmentUrl": "\(thirdExperimentTreatmentURL)"
            }
            """
        ]
        mockPrivacyConfigurationManager.privacyConfig = privacyConfig
        mockFeatureFlagger.mockCohorts = [
            TDSExperimentType.value(at: 1)!.rawValue: TDSExperimentType.Cohort.treatment,
            TDSExperimentType.value(at: 2)!.rawValue: TDSExperimentType.Cohort.treatment
        ]

        // WHEN
        let url = try XCTUnwrap(urlProvider.trackerDataURL)

        // THEN
        XCTAssertEqual(url.absoluteString, TrackerDataURLOverrider.Constants.baseTDSURLString + secondExperimentTreatmentURL)
    }

}

private class MockFeatureFlaggerMockSettings: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var mockCohorts: [String: any FeatureFlagCohortDescribing] = [:]

    var isFeatureOn = true
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        return isFeatureOn
    }

    func resolveCohort(_ subfeature: any PrivacySubfeature) -> CohortID? {
        return nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return mockCohorts[featureFlag.rawValue]
    }

    var allActiveExperiments: Experiments {
        return [:]
    }
}

class MockPrivacyConfigurationManager: NSObject, PrivacyConfigurationManaging {

    var embeddedConfigData: BrowserServicesKit.PrivacyConfigurationManager.ConfigurationData {
        fatalError("not implemented")
    }

    var fetchedConfigData: BrowserServicesKit.PrivacyConfigurationManager.ConfigurationData? {
        fatalError("not implemented")
    }

    var currentConfig: Data {
        Data()
    }

    func reload(etag: String?, data: Data?) -> BrowserServicesKit.PrivacyConfigurationManager.ReloadResult {
        fatalError("not implemented")
    }

    var updatesPublisher: AnyPublisher<Void, Never> = Just(()).eraseToAnyPublisher()
    var privacyConfig: PrivacyConfiguration = MockPrivacyConfiguration()
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider()
}

class MockPrivacyConfiguration: PrivacyConfiguration {

    var isSubfeatureKeyEnabled: ((any PrivacySubfeature, AppVersionProvider) -> Bool)?
    func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> Bool {
        isSubfeatureKeyEnabled?(subfeature, versionProvider) ?? false
    }

    func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        if isSubfeatureKeyEnabled?(subfeature, versionProvider) == true {
            return .enabled
        }
        return .disabled(.disabledInConfig)
    }

    func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        return .disabled(.disabledInConfig)
    }

    func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    var identifier: String = "MockPrivacyConfiguration"
    var version: String? = "123456789"
    var userUnprotectedDomains: [String] = []
    var tempUnprotectedDomains: [String] = []
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(entries: [:],
                                                                            state: PrivacyConfigurationData.State.enabled)
    var exceptionsList: (PrivacyFeature) -> [String] = { _ in [] }
    var featureSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings = [:]

    var subfeatureSettings: String?
    var mockSubfeatureSettings: [String: String] = [:]
    func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        return subfeatureSettings ?? mockSubfeatureSettings[subfeature.rawValue]
    }

    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { exceptionsList(featureKey) }
    var isFeatureKeyEnabled: ((PrivacyFeature, AppVersionProvider) -> Bool)?
    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> Bool {
        isFeatureKeyEnabled?(featureKey, versionProvider) ?? true
    }
    func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState {
        if isFeatureKeyEnabled?(featureKey, versionProvider) == true {
            return .enabled
        }
        return .disabled(.disabledInConfig)
    }

    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    func isProtected(domain: String?) -> Bool { true }
    func isUserUnprotected(domain: String?) -> Bool { false }
    func isTempUnprotected(domain: String?) -> Bool { false }
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings { featureSettings }
    func userEnabledProtection(forDomain: String) {}
    func userDisabledProtection(forDomain: String) {}
}

final class MockInternalUserStoring: InternalUserStoring {
    var isInternalUser: Bool = false
}

extension DefaultInternalUserDecider {
    convenience init(mockedStore: MockInternalUserStoring = MockInternalUserStoring()) {
        self.init(store: mockedStore)
    }
}

extension TDSExperimentType {
    static func value(at index: Int) -> TDSExperimentType? {
        guard index >= 0 && index < allCases.count else { return nil }
        return allCases[index]
    }
}
