//
//  UnifiedToggleInputFeatureTests.swift
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

import XCTest
@testable import DuckDuckGo
@testable import Core
import PrivacyConfig

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    private enum ExperimentID {
        static let duckAIQuery = AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue
        static let duckAIQueryTrackersDemo = AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: []))
        MockDevicePlatform.isIphone = false
    }

    override func tearDown() {
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: []))
        MockDevicePlatform.isIphone = false
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFeature(flagEnabled: Bool, isIphone: Bool, activeExperiments: Experiments = [:]) -> UnifiedToggleInputFeature {
        MockDevicePlatform.isIphone = isIphone
        let flags: [FeatureFlag] = flagEnabled ? [.unifiedToggleInput] : []
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: flags)
        featureFlagger.mockActiveExperiments = activeExperiments
        UnifiedToggleInputFeature.resolve(using: featureFlagger)
        return UnifiedToggleInputFeature(featureFlagger: featureFlagger, devicePlatform: MockDevicePlatform.self)
    }

    private func makeExperimentData(for subfeature: AIChatSubfeature, cohortID: CohortID) -> ExperimentData {
        ExperimentData(parentID: subfeature.parent.rawValue,
                       cohortID: cohortID,
                       enrollmentDate: Date())
    }

    // MARK: - Tests

    func test_isAvailable_whenFlagOnAndIphone() {
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOnButNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: true, isIphone: false).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffButIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffAndNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: false).isAvailable)
    }

    func test_isAvailable_whenEnrolledInControlCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.control.rawValue
                                      ),
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.control.rawValue
                                      )
                                  ])

        XCTAssertTrue(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTreatmentACohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentA.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTreatmentBCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentB.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInUnknownNonControlCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: "treatmentC"
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTrackersDemoTreatmentACohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentA.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTrackersDemoTreatmentBCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentB.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTrackersDemoUnknownNonControlCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: "treatmentC"
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isAvailable_whenTreatmentCohortBelongsToAnotherExperiment() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      "otherExperiment": ExperimentData(parentID: "aiChat", cohortID: "treatment", enrollmentDate: Date())
                                  ])

        XCTAssertTrue(feature.isAvailable)
    }

    func test_isAvailable_doesNotResolveExperimentCohort() {
        MockDevicePlatform.isIphone = true
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput])
        UnifiedToggleInputFeature.resolve(using: featureFlagger)
        let feature = UnifiedToggleInputFeature(featureFlagger: featureFlagger, devicePlatform: MockDevicePlatform.self)

        XCTAssertTrue(feature.isAvailable)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    // MARK: - Snapshot semantics

    /// Mid-session flag flips must not change availability. Resolve writes the launch-time flag
    /// value into UserDefaults, while readers still apply the device availability gate.
    func test_isAvailable_usesLaunchResolvedFlagSnapshot() {
        MockDevicePlatform.isIphone = true
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput])
        UnifiedToggleInputFeature.resolve(using: flagger)
        let feature = UnifiedToggleInputFeature(featureFlagger: flagger, devicePlatform: MockDevicePlatform.self)
        XCTAssertTrue(feature.isAvailable, "Precondition: availability is ON after resolve")

        flagger.enabledFeatureFlags = []
        XCTAssertFalse(flagger.isFeatureOn(.unifiedToggleInput),
                       "Sanity: the live flagger now reports the flag as off")
        XCTAssertTrue(feature.isAvailable,
                      "Snapshot must ignore the post-resolve mutation on the same instance")
        XCTAssertTrue(UnifiedToggleInputFeature(featureFlagger: flagger, devicePlatform: MockDevicePlatform.self).isAvailable,
                      "A fresh instance must read the same snapshot, not the mutated live flagger")

        UnifiedToggleInputFeature.resolve(using: flagger)
        XCTAssertFalse(feature.isAvailable,
                       "After re-resolving the snapshot must flip — otherwise resolve isn't doing its job")
    }
}
