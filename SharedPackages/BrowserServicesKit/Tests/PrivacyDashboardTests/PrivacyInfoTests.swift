//
//  PrivacyInfoTests.swift
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

import XCTest
import BrowserServicesKit
@testable import PrivacyDashboard

final class PrivacyInfoTests: XCTestCase {

    func testPrivacyExperimentCohortsWithNoExperiments() {
        let privacyInfo = PrivacyInfo(url: URL(string: "https://example.com")!,
                                    parentEntity: nil,
                                      protectionStatus: .init(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false),
                                    allActiveContentScopeExperiments: [:])

        XCTAssertEqual(privacyInfo.privacyExperimentCohorts, "")
    }

    func testPrivacyExperimentCohortsWithSingleExperiment() {
        let experiments: Experiments = [
            "experiment1": ExperimentData(parentID: "parent", cohortID: "cohort1", enrollmentDate: Date())
        ]

        let privacyInfo = PrivacyInfo(url: URL(string: "https://example.com")!,
                                    parentEntity: nil,
                                    protectionStatus: .init(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false),
                                    allActiveContentScopeExperiments: experiments)

        XCTAssertEqual(privacyInfo.privacyExperimentCohorts, "experiment1:cohort1")
    }

    func testPrivacyExperimentCohortsWithMultipleExperiments() {
        let experiments: Experiments = [
            "experimentC": ExperimentData(parentID: "parent", cohortID: "cohort3", enrollmentDate: Date()),
            "experimentA": ExperimentData(parentID: "parent", cohortID: "cohort1", enrollmentDate: Date()),
            "experimentB": ExperimentData(parentID: "parent", cohortID: "cohort2", enrollmentDate: Date())
        ]

        let privacyInfo = PrivacyInfo(url: URL(string: "https://example.com")!,
                                    parentEntity: nil,
                                    protectionStatus: .init(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false),
                                    allActiveContentScopeExperiments: experiments)

        // Verify experiments are sorted alphabetically by key and properly formatted
        XCTAssertEqual(privacyInfo.privacyExperimentCohorts, "experimentA:cohort1,experimentB:cohort2,experimentC:cohort3")
    }
}
