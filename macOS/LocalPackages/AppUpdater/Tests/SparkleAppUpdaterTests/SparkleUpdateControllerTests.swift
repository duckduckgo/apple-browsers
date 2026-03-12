//
//  SparkleUpdateControllerTests.swift
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

import AppUpdaterShared
import AppUpdaterTestHelpers
import FeatureFlags
import PrivacyConfig
import SparkleAppUpdater
import XCTest

final class SparkleUpdateControllerTests: XCTestCase {

    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        super.tearDown()
    }

    // MARK: - Custom Feed Enabled

    func testResolveAutoDownload_customFeedEnabled_flagOff_preferenceOn_returnsFalse() {
        // Flag OFF = not in enabledUpdateFeatureFlags array

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertFalse(result)
    }

    func testResolveAutoDownload_customFeedEnabled_debugFlagOn_preferenceOn_returnsTrue() {
        mockFeatureFlagger.enabledUpdateFeatureFlags = [.autoUpdateInDEBUG]

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

#if DEBUG
        XCTAssertTrue(result)
#else
        XCTAssertFalse(result)
#endif
    }

    func testResolveAutoDownload_customFeedEnabled_debugFlagOn_preferenceOff_returnsFalse() {
        mockFeatureFlagger.enabledUpdateFeatureFlags = [.autoUpdateInDEBUG]

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger,
            userPreference: false
        )

        XCTAssertFalse(result)
    }

    // MARK: - Non-Debug Flag Handling

    func testResolveAutoDownload_customFeedEnabled_nonDebugFlagOff_preferenceOn_returnsFalse() {
        // Flag OFF = not in enabledUpdateFeatureFlags array.

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertFalse(result)
    }

    func testResolveAutoDownload_customFeedEnabled_nonDebugFlagOn_preferenceOn_matchesBuild() {
        mockFeatureFlagger.enabledUpdateFeatureFlags = [.autoUpdateInREVIEW]

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

#if DEBUG
        XCTAssertFalse(result)
#else
        XCTAssertTrue(result)
#endif
    }

    func testResolveAutoDownload_customFeedEnabled_nonDebugFlagOn_preferenceOff_returnsFalse() {
        mockFeatureFlagger.enabledUpdateFeatureFlags = [.autoUpdateInREVIEW]

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger,
            userPreference: false
        )

        XCTAssertFalse(result)
    }

    // MARK: - Custom Feed Disabled

    func testResolveAutoDownload_customFeedDisabled_preferenceOn_returnsTrue() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: false,
            featureFlagger: mockFeatureFlagger,
            userPreference: true
        )

        XCTAssertTrue(result)
    }

    func testResolveAutoDownload_customFeedDisabled_preferenceOff_returnsFalse() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: false,
            featureFlagger: mockFeatureFlagger,
            userPreference: false
        )

        XCTAssertFalse(result)
    }
}
