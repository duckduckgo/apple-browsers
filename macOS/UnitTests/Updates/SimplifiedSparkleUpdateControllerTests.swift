//
//  SimplifiedSparkleUpdateControllerTests.swift
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

#if SPARKLE

import XCTest
import PrivacyConfig
import FeatureFlags
@testable import DuckDuckGo_Privacy_Browser

final class SimplifiedSparkleUpdateControllerTests: XCTestCase {

    var mockBuildType: ApplicationBuildTypeMock!
    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockBuildType = ApplicationBuildTypeMock()
        mockFeatureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        mockBuildType = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    // MARK: - DEBUG Build Tests

    func testResolveAutoDownload_debugBuild_flagOff_preferenceOn_returnsFalse() {
        mockBuildType.isDebugBuild = true
        // Flag OFF = not in enabledFeatureFlags array

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertFalse(result)
    }

    func testResolveAutoDownload_debugBuild_flagOn_preferenceOn_returnsTrue() {
        mockBuildType.isDebugBuild = true
        mockFeatureFlagger.enabledFeatureFlags = [.autoUpdateInDEBUG]

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertTrue(result)
    }

    func testResolveAutoDownload_debugBuild_flagOn_preferenceOff_returnsFalse() {
        mockBuildType.isDebugBuild = true
        mockFeatureFlagger.enabledFeatureFlags = [.autoUpdateInDEBUG]

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: false
        )

        XCTAssertFalse(result)
    }

    // MARK: - REVIEW Build Tests

    func testResolveAutoDownload_reviewBuild_flagOff_preferenceOn_returnsFalse() {
        mockBuildType.isReviewBuild = true
        // Flag OFF = not in enabledFeatureFlags array

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertFalse(result)
    }

    func testResolveAutoDownload_reviewBuild_flagOn_preferenceOn_returnsTrue() {
        mockBuildType.isReviewBuild = true
        mockFeatureFlagger.enabledFeatureFlags = [.autoUpdateInREVIEW]

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertTrue(result)
    }

    func testResolveAutoDownload_reviewBuild_flagOn_preferenceOff_returnsFalse() {
        mockBuildType.isReviewBuild = true
        mockFeatureFlagger.enabledFeatureFlags = [.autoUpdateInREVIEW]

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: false
        )

        XCTAssertFalse(result)
    }

    // MARK: - Release Build Tests

    func testResolveAutoDownload_releaseBuild_preferenceOn_returnsTrue() {
        // Neither debug nor review - flags don't matter
        mockBuildType.isDebugBuild = false
        mockBuildType.isReviewBuild = false

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertTrue(result)
    }

    func testResolveAutoDownload_releaseBuild_preferenceOff_returnsFalse() {
        mockBuildType.isDebugBuild = false
        mockBuildType.isReviewBuild = false

        let result = SimplifiedSparkleUpdateController.resolveAutoDownloadEnabled(
            buildType: mockBuildType,
            featureFlagger: mockFeatureFlagger,
            userPreference: false
        )

        XCTAssertFalse(result)
    }
}

#endif
