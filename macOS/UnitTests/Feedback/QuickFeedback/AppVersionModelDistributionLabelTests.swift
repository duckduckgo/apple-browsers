//
//  AppVersionModelDistributionLabelTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class AppVersionModelDistributionLabelTests: XCTestCase {

    // MARK: - Alpha Build

    func testWhenAlphaBuildThenDistributionLabelContainsAlpha() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAlphaBuild = true

        let model = AppVersionModel(buildType: buildType)

        XCTAssertTrue(model.distributionLabel.contains("Alpha"),
                      "Alpha builds should include 'Alpha' in the distribution label")
    }

    // MARK: - Non-Alpha Build

    func testWhenNotAlphaBuildThenDistributionLabelDoesNotContainAlpha() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAlphaBuild = false

        let model = AppVersionModel(buildType: buildType)

        XCTAssertFalse(model.distributionLabel.contains("Alpha"),
                       "Non-alpha builds should not include 'Alpha' in the distribution label")
    }

    // MARK: - Distribution Channel

    func testWhenNotAlphaBuildThenDistributionLabelIsDMGOrAppStore() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAlphaBuild = false

        let model = AppVersionModel(buildType: buildType)

        let validLabels = ["DMG", "App Store"]
        XCTAssertTrue(validLabels.contains(model.distributionLabel),
                      "Non-alpha label should be exactly 'DMG' or 'App Store', got '\(model.distributionLabel)'")
    }

    func testWhenAlphaBuildThenDistributionLabelIsDMGAlphaOrAppStoreAlpha() {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAlphaBuild = true

        let model = AppVersionModel(buildType: buildType)

        let validLabels = ["DMG Alpha", "App Store Alpha"]
        XCTAssertTrue(validLabels.contains(model.distributionLabel),
                      "Alpha label should be 'DMG Alpha' or 'App Store Alpha', got '\(model.distributionLabel)'")
    }
}
