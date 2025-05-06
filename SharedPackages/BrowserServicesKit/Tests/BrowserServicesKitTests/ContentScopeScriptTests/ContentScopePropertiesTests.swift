//
//  ContentScopePropertiesTests.swift
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

import XCTest
import WebKit
@testable import BrowserServicesKit

class ContentScopePropertiesTests: XCTestCase {
    func testContentScopePropertiesInitializeCorrectly() throws {
        let testExperimentData = ExperimentData(
            parentID: "parent",
            cohortID: "aCohort",
            enrollmentDate: Date()
        )

        let experimentManager = MockContentScopeExperimentManager()
        experimentManager.experiments = ["test": testExperimentData]

        let properties = ContentScopeProperties(
            gpcEnabled: true,
            sessionKey: "123456",
            messageSecret: "123456",
            featureToggles: ContentScopeFeatureToggles.allTogglesOn,
            experimentManager: experimentManager
        )

        // ensure the properties can be encoded to valid JSON
        let encodedProperties = try XCTUnwrap(JSONEncoder().encode(properties))

        // ensure the platform.name key exists, as this will be expected in the output JSON
        XCTAssertEqual(properties.platform.name, ContentScopePlatform().name)

        // ensure encoded strings contain expected cohorts
        let decodedJSON = try JSONSerialization.jsonObject(with: encodedProperties, options: []) as? [String: Any]
        let currentCohorts = decodedJSON?["currentCohorts"] as? [[String: String]]

        XCTAssertNotNil(currentCohorts)

        // Assert that the expected cohort data is present
        let expectedCohort: [String: String] = [
            "subfeature": "test",
            "feature": "parent",
            "cohort": "aCohort"
        ]

        XCTAssertTrue(currentCohorts!.contains { $0 == expectedCohort })
    }
}
