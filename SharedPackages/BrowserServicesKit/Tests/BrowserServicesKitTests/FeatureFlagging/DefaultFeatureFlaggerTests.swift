//
//  DefaultFeatureFlaggerTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import XCTest

final class CapturingFeatureFlagOverriding: FeatureFlagLocalOverriding {

    var overrideCalls: [any FeatureFlagDescribing] = []
    var toggleOverrideCalls: [any FeatureFlagDescribing] = []
    var clearOverrideCalls: [any FeatureFlagDescribing] = []
    var clearAllOverrideCallCount: Int = 0

    var override: (any FeatureFlagDescribing) -> Bool? = { _ in nil }
    var experimentOverride: (any FeatureFlagDescribing) -> CohortID? = { _ in nil }

    var actionHandler: any FeatureFlagLocalOverridesHandling = CapturingFeatureFlagLocalOverridesHandler()
    weak var featureFlagger: FeatureFlagger?

    func override<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool? {
        overrideCalls.append(featureFlag)
        return override(featureFlag)
    }

    func toggleOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag) {
        toggleOverrideCalls.append(featureFlag)
    }

    func clearOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag) {
        clearOverrideCalls.append(featureFlag)
    }

    func clearAllOverrides<Flag: FeatureFlagDescribing>(for flagType: Flag.Type) {
        clearAllOverrideCallCount += 1
    }

    func experimentOverride<Flag>(for featureFlag: Flag) -> CohortID? where Flag: FeatureFlagDescribing {
        overrideCalls.append(featureFlag)
        return experimentOverride(featureFlag)
    }

    func setExperimentCohortOverride<Flag>(for featureFlag: Flag, cohort: CohortID) where Flag: FeatureFlagDescribing {
        return
    }

    func currentValue<Flag>(for featureFlag: Flag) -> Bool? where Flag: FeatureFlagDescribing {
        return nil
    }

    func currentExperimentCohort<Flag>(for featureFlag: Flag) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return nil
    }
}

final class DefaultFeatureFlaggerTests: XCTestCase {
    var internalUserDeciderStore: MockInternalUserStoring!
    var experimentManager: MockExperimentManager!
    var overrides: CapturingFeatureFlagOverriding!

    override func setUp() {
        super.setUp()
        internalUserDeciderStore = MockInternalUserStoring()
        experimentManager = MockExperimentManager()
    }

    override func tearDown() {
        internalUserDeciderStore = nil
        experimentManager = nil
        super.tearDown()
    }

    func testWhenDisabled_sourceDisabled_returnsFalse() {
        let featureFlagger = createFeatureFlagger()
        XCTAssertFalse(featureFlagger.isFeatureOn(for: FeatureFlagSource.disabled))
    }

    func testWhenEnabled_sourceEnabled_returnsTrue() {
        let featureFlagger = createFeatureFlagger()
        XCTAssertTrue(featureFlagger.isFeatureOn(for: FeatureFlagSource.enabled))
    }

    func testWhenInternalOnly_returnsIsInternalUserValue() {
        let featureFlagger = createFeatureFlagger()
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(featureFlagger.isFeatureOn(for: FeatureFlagSource.internalOnly()))
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(featureFlagger.isFeatureOn(for: FeatureFlagSource.internalOnly()))
    }

    func testWhenRemoteDevelopment_isNOTInternalUser_returnsFalse() {
        internalUserDeciderStore.isInternalUser = false
        let embeddedData = Self.embeddedConfig(autofillState: "enabled")
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertFalse(featureFlagger.isFeatureOn(for: FeatureFlagSource.remoteDevelopment(.feature(.autofill))))
    }

    func testWhenRemoteDevelopment_isInternalUser_whenFeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let sourceProvider = FeatureFlagSource.remoteDevelopment(.feature(.autofill))

        var embeddedData = Self.embeddedConfig(autofillState: "enabled")
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillState: "disabled")
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteDevelopment_isInternalUser_whenSubfeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        let sourceProvider = FeatureFlagSource.remoteDevelopment(.subfeature(subfeature))

        var embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "disabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteReleasable_isNOTInternalUser_whenFeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = false
        let sourceProvider = FeatureFlagSource.remoteReleasable(.feature(.autofill))

        var embeddedData = Self.embeddedConfig(autofillState: "enabled")
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillState: "disabled")
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteReleasable_isInternalUser_whenFeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let sourceProvider = FeatureFlagSource.remoteReleasable(.feature(.autofill))

        var embeddedData = Self.embeddedConfig(autofillState: "enabled")
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillState: "disabled")
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteReleasable_isInternalUser_whenSubfeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        let sourceProvider = FeatureFlagSource.remoteReleasable(.subfeature(subfeature))

        var embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "disabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    // MARK: - Experiments

    func testWhenResolveCohort_andSourceDisabled_returnsNil() {
        let featureFlagger = createFeatureFlagger()
        let flag = FakeExperimentFlags.disabledFlag
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andSourceInternal_returnsPassedCohort() {
        let featureFlagger = createFeatureFlagger()
        let flag = FakeExperimentFlags.internalFlag
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertEqual(cohort?.rawValue, FakeExperimentFlagsCohort.blue.rawValue)
    }

    func testWhenResolveCohort_andRemoteInternal_andInternalStateTrue_and_cohortAssigned_returnsAssignedCohort() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = FakeExperimentFlagsCohort.control.rawValue
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteDeveloperFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertEqual(cohort?.rawValue, FakeExperimentFlagsCohort.control.rawValue)
    }

    func testWhenResolveCohort_andRemoteInternal_andInternalStateFalse_and_cohortAssigned_returnsNil() {
        internalUserDeciderStore.isInternalUser = false
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = FakeExperimentFlagsCohort.control.rawValue
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteDeveloperFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andRemoteInternal_andInternalStateTrue_and_cohortAssigned_andFeaturePassed_returnsNil() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = FakeExperimentFlagsCohort.control.rawValue
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteDevelopmentFeature
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andRemoteInternal_andInternalStateTrue_and_cohortNotAssigned_returnsNil() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = nil
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteDeveloperFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andRemoteInternal_andInternalStateTrue_and_cohortAssignedButNorMatchingEnum_returnsNil() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = "some"
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteDeveloperFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andRemoteReleasable_and_cohortAssigned_returnsAssignedCohort() {
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = FakeExperimentFlagsCohort.control.rawValue
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteReleasableFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertEqual(cohort?.rawValue, FakeExperimentFlagsCohort.control.rawValue)
    }

    func testWhenResolveCohort_andRemoteReleasable_and_cohortAssigned_andFeaturePassed_returnsNil() {
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = FakeExperimentFlagsCohort.control.rawValue
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteReleasableFeature
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andRemoteReleasable_and_cohortNotAssigned_andFeaturePassed_returnsNil() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = nil
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteReleasableFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    func testWhenResolveCohort_andRemoteReleasable_and_cohortAssignedButNotMatchingEnum_returnsNil() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        experimentManager.cohortToReturn = "some"
        let embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))

        let flag = FakeExperimentFlags.remoteReleasableFlag
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        let cohort = featureFlagger.resolveCohort(for: flag, allowOverride: true)
        XCTAssertNil(cohort)
    }

    // MARK: - Overrides

    func testWhenFeatureFlaggerIsInitializedWithLocalOverridesAndUserIsNotInternalThenAllFlagsAreCleared() throws {
        internalUserDeciderStore.isInternalUser = false
        _ = createFeatureFlaggerWithLocalOverrides()
        XCTAssertEqual(overrides.clearAllOverrideCallCount, 1)
    }

    func testWhenLocalOverridesIsSetUpAndUserIsInternalThenLocalOverrideTakesPrecedenceWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = true

        overrides.override = { _ in return true }

        XCTAssertTrue(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableFlagDisabledByDefault))
        XCTAssertEqual(overrides.overrideCalls.count, 1)
        XCTAssertEqual(try XCTUnwrap(overrides.overrideCalls.first as? TestFeatureFlag), .overridableFlagDisabledByDefault)
    }

    func testWhenLocalExperimentOverridesIsSetUpAndUserIsInternalThenLocalOverrideTakesPrecedenceWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = true

        overrides.experimentOverride = { _ in return TestFeatureFlag.FakeExperimentCohort.cohortA.rawValue }
        let actualCohort = featureFlagger.resolveCohort(for: TestFeatureFlag.overridableExperimentFlagWithCohortBByDefault, allowOverride: true)

        XCTAssertEqual(actualCohort?.rawValue, TestFeatureFlag.FakeExperimentCohort.cohortA.rawValue)
        XCTAssertEqual(overrides.overrideCalls.count, 1)
        XCTAssertEqual(try XCTUnwrap(overrides.overrideCalls.first as? TestFeatureFlag), .overridableExperimentFlagWithCohortBByDefault)
    }

    func testWhenLocalOverridesIsSetUpAndUserIsInternalAndAllowOverrideIsFalseThenLocalOverrideIsNotCheckedWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = true

        XCTAssertFalse(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableFlagDisabledByDefault, allowOverride: false))
        XCTAssertTrue(overrides.overrideCalls.isEmpty)
    }

    func testWhenLocalExperimentOverridesIsSetUpAndUserIsInternalAndAllowOverrideIsFalseThenLocalOverrideIsNotCheckedWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = true
        overrides.experimentOverride = { _ in return TestFeatureFlag.FakeExperimentCohort.cohortA.rawValue }
        let actualCohort = featureFlagger.resolveCohort(for: TestFeatureFlag.overridableExperimentFlagWithCohortBByDefault, allowOverride: false)

        XCTAssertEqual(actualCohort?.rawValue, TestFeatureFlag.FakeExperimentCohort.cohortB.rawValue)
        XCTAssertTrue(overrides.overrideCalls.isEmpty)
    }

    func testWhenLocalOverridesIsSetUpAndUserIsNotInternalThenLocalOverrideIsNotCheckedWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = false

        XCTAssertFalse(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableFlagDisabledByDefault))
        XCTAssertTrue(overrides.overrideCalls.isEmpty)
    }

    func testWhenLocalExperimentOverridesIsSetUpAndUserIsNotInternalThenLocalOverrideIsNotCheckedWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = false
        overrides.experimentOverride = { _ in return TestFeatureFlag.FakeExperimentCohort.cohortA.rawValue }

        XCTAssertFalse(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableExperimentFlagWithCohortBByDefault))
        XCTAssertTrue(overrides.overrideCalls.isEmpty)
    }

    // MARK: - Helpers

    private func createFeatureFlagger(withMockedConfigData data: Data = DefaultFeatureFlaggerTests.embeddedConfig()) -> DefaultFeatureFlagger {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: data, etag: "embeddedConfigETag")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)
        return DefaultFeatureFlagger(internalUserDecider: internalUserDecider, privacyConfigManager: manager, experimentManager: experimentManager)
    }

    private func createFeatureFlaggerWithLocalOverrides(withMockedConfigData data: Data = DefaultFeatureFlaggerTests.embeddedConfig()) -> DefaultFeatureFlagger {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: data, etag: "embeddedConfigETag")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)

        overrides = CapturingFeatureFlagOverriding()
        return DefaultFeatureFlagger(
            internalUserDecider: internalUserDecider,
            privacyConfigManager: manager,
            localOverrides: overrides,
            experimentManager: nil,
            for: TestFeatureFlag.self
        )
    }

    private static func embeddedConfig(autofillState: String = "enabled",
                                       autofillSubfeatureForState: (subfeature: AutofillSubfeature, state: String) = (.credentialsAutofill, "enabled")) -> Data {
        """
        {
            "features": {
                "autofill": {
                    "state": "\(autofillState)",
                    "features": {
                        "\(autofillSubfeatureForState.subfeature)": {
                            "state": "\(autofillSubfeatureForState.state)"
                        }
                    },
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
    }

    private func assertFeatureFlagger(with embeddedData: Data,
                                      willReturn bool: Bool,
                                      for sourceProvider: any FeatureFlagDescribing,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertEqual(featureFlagger.isFeatureOn(for: sourceProvider), bool, file: file, line: line)
    }
}

extension FeatureFlagSource: FeatureFlagDescribing {
    public var cohortType: (any FeatureFlagCohortDescribing.Type)? { nil }
    public static let allCases: [FeatureFlagSource]  = []
    public var supportsLocalOverriding: Bool { false }
    public var rawValue: String { "rawValue" }
    public var source: FeatureFlagSource { self }
}

class MockExperimentManager: ExperimentCohortsManaging {
    var cohortToReturn: CohortID?
    var experiments: BrowserServicesKit.Experiments?

    func resolveCohort(for experiment: BrowserServicesKit.ExperimentSubfeature, allowCohortAssignment: Bool) -> CohortID? {
        return cohortToReturn
    }
}
private enum FakeExperimentFlags: String, CaseIterable {
    case disabledFlag
    case internalFlag
    case remoteDeveloperFlag
    case remoteDevelopmentFeature
    case remoteReleasableFlag
    case remoteReleasableFeature
}

extension  FakeExperimentFlags: FeatureFlagDescribing {
    var supportsLocalOverriding: Bool { true }

    var cohortType: (any FeatureFlagCohortDescribing.Type)? { FakeExperimentFlagsCohort.self}

    var source: FeatureFlagSource {
        switch self {
        case .disabledFlag:
                .disabled
        case .internalFlag:
                .internalOnly(FakeExperimentFlagsCohort.blue)
        case .remoteDeveloperFlag:
                .remoteDevelopment(.subfeature(AutofillSubfeature.credentialsAutofill))
        case .remoteDevelopmentFeature:
                .remoteDevelopment(.feature(.autofill))
        case .remoteReleasableFlag:
                .remoteReleasable(.subfeature(AutofillSubfeature.credentialsAutofill))
        case .remoteReleasableFeature:
                .remoteReleasable(.feature(.autofill))
        }
    }
}

private enum FakeExperimentFlagsCohort: String, FeatureFlagCohortDescribing {
    case control
    case blue
}
