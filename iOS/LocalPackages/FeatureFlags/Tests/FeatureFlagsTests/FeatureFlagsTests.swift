//
//  FeatureFlagsTests.swift
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

import FeatureFlags
import Foundation
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest

final class FeatureFlagsTests: XCTestCase {

    func testWhenSubfeatureIsMissingThenProvidedDefaultValueIsReturned() {
        let configData = """
        {
            "features": {},
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
        let manager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: MockEmbeddedDataProvider(data: configData, etag: "test"),
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider())
        let config = manager.privacyConfig
        let subfeature = iOSBrowserConfigSubfeature.intentionallyLocalOnlySubfeatureForTests

        XCTAssertFalse(config.isSubfeatureEnabled(subfeature, defaultValue: false))
        XCTAssertTrue(config.isSubfeatureEnabled(subfeature, defaultValue: true))
    }

    func testWhenReadingIOSBrowserConfigSubfeatureThenParentAndRawValueAreStable() {
        let subfeature = iOSBrowserConfigSubfeature.searchTokenExperimentV2

        XCTAssertEqual(subfeature.parent, .iOSBrowserConfig)
        XCTAssertEqual(subfeature.rawValue, "searchTokenExperimentV2")
    }

    func testWhenReadingSearchTokenFeatureFlagThenSourceAndCohortUseSearchTokenConfiguration() {
        guard case let .remoteReleasable(subfeature) = FeatureFlag.searchTokenExperimentV2.source else {
            XCTFail("Expected remote-releasable source")
            return
        }

        XCTAssertEqual((subfeature as? iOSBrowserConfigSubfeature)?.rawValue,
                       iOSBrowserConfigSubfeature.searchTokenExperimentV2.rawValue)
        XCTAssertEqual(FeatureFlag.searchTokenExperimentV2.cohortType.map(ObjectIdentifier.init),
                       ObjectIdentifier(FeatureFlag.SearchTokenExperimentCohort.self))
    }
}
