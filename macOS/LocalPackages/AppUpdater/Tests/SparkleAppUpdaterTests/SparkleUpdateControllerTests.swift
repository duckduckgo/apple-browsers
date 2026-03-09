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

    // MARK: - Custom Feed Enabled (DEBUG/REVIEW builds)

    func testResolveAutoDownload_customFeedEnabled_flagOff_returnsFalse() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger
        )

        XCTAssertFalse(result)
    }

    func testResolveAutoDownload_customFeedEnabled_debugFlagOn_matchesBuild() {
        mockFeatureFlagger.enabledUpdateFeatureFlags = [.autoUpdateInDEBUG]

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger
        )

#if DEBUG
        XCTAssertTrue(result)
#else
        XCTAssertFalse(result)
#endif
    }

    func testResolveAutoDownload_customFeedEnabled_reviewFlagOn_matchesBuild() {
        mockFeatureFlagger.enabledUpdateFeatureFlags = [.autoUpdateInREVIEW]

        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: true,
            featureFlagger: mockFeatureFlagger
        )

#if DEBUG
        XCTAssertFalse(result)
#else
        XCTAssertTrue(result)
#endif
    }

    // MARK: - Custom Feed Disabled (production builds)

    func testResolveAutoDownload_customFeedDisabled_alwaysReturnsTrue() {
        let result = SparkleUpdateController.resolveAutoDownloadEnabled(
            allowCustomUpdateFeed: false,
            featureFlagger: mockFeatureFlagger
        )

        XCTAssertTrue(result)
    }
}
