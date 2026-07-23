//
//  MonthlyFreeTrialExperimentTests.swift
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
import PrivacyConfig
import Testing
@testable import Core
@testable import DuckDuckGo

@Suite("Monthly Free Trial Experiment – purchase URL cohort parameter")
struct MonthlyFreeTrialExperimentTests {

    private let baseURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!

    private func cohortValue(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "experiment_mobileannualtrials_ios" }?
            .value
    }

    @Test("Control cohort is appended as experiment_mobileannualtrials_ios=control")
    func controlCohortAppendedToURL() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.MonthlyFreeTrialExperimentCohort.control)

        let result = MonthlyFreeTrialExperiment.appendingCohortParameter(to: baseURL, resolvedBy: featureFlagger)

        #expect(cohortValue(in: result) == "control")
    }

    @Test("Treatment cohort is appended as experiment_mobileannualtrials_ios=treatment")
    func treatmentCohortAppendedToURL() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.MonthlyFreeTrialExperimentCohort.treatment)

        let result = MonthlyFreeTrialExperiment.appendingCohortParameter(to: baseURL, resolvedBy: featureFlagger)

        #expect(cohortValue(in: result) == "treatment")
    }

    @Test("An unenrolled user gets no experiment parameter and the URL is unchanged")
    func unenrolledUserLeavesURLUnchanged() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil)

        let result = MonthlyFreeTrialExperiment.appendingCohortParameter(to: baseURL, resolvedBy: featureFlagger)

        #expect(cohortValue(in: result) == nil)
        #expect(result == baseURL)
    }
}
