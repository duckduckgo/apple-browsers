//
//  ContentScopePrivacyConfigurationJSONGeneratorTests.swift
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

import XCTest
@testable import ContentScopeScripts
import BrowserServicesKit
import Combine

final class ContentScopePrivacyConfigurationJSONGeneratorTests: XCTestCase {

    private var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!
    private var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration(), internalUserDecider: DefaultInternalUserDecider(mockedStore: MockInternalUserStoring()))
        mockFeatureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockPrivacyConfigurationManager = nil
        super.tearDown()
    }

    let config = """
        {
            "features": {
                "fingerprintingCanvas": {
                    "state": "disabled"
                },
                "contentScopeExperiments": {
                    "exceptions": [],
                    "state": "enabled",
                    "features": {
                        "fingerprintingCanvas": {
                            "state": "enabled",
                            "cohorts": [
                                {
                                    "name": "treatment",
                                    "weight": 1
                                }
                            ]
                        }
                    },
                    "hash": "042cc21dcd61460ea41c394d02c9b2b8"
                }
            }
        }

    """

    func testGeneratorEnablesFeatureForTreatmentCohort() {
        // GIVEN
        mockFeatureFlagger.cohort = ContentScopeExperimentsFeatureFlag.ContentScopeExperimentsCohort.treatment
        mockPrivacyConfigurationManager.currentConfigString = config
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigurationManager
        )

        // WHEN
        guard let data = generator.privacyConfiguration,
              let updatedConfig = try? PrivacyConfigurationData(data: data) else {
            XCTFail("Failed to generate configuration JSON")
            return
        }

        // THEN
        XCTAssertEqual(updatedConfig.features["fingerprintingCanvas"]?.state, "enabled")
    }

    func testGeneratorKeepsFeatureDisabledFeatureForControlCohort() {
        // GIVEN
        mockFeatureFlagger.cohort = ContentScopeExperimentsFeatureFlag.ContentScopeExperimentsCohort.control
        mockPrivacyConfigurationManager.currentConfigString = config
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigurationManager
        )

        // WHEN
        guard let data = generator.privacyConfiguration,
              let updatedConfig = try? PrivacyConfigurationData(data: data) else {
            XCTFail("Failed to generate configuration JSON")
            return
        }

        // THEN
        XCTAssertEqual(updatedConfig.features["fingerprintingCanvas"]?.state, "disabled")
    }

}

final class MockFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var disabledFlags: [String] = []
    var cohort: (any FeatureFlagCohortDescribing)?

    var allActiveExperiments: Experiments {
        return [:]
    }

    func isFeatureOn<Flag>(for featureFlag: Flag, allowOverride: Bool) -> Bool where Flag: FeatureFlagDescribing {
        if disabledFlags.contains(featureFlag.rawValue) {
            return false
        }
        return true
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return cohort
    }

}
