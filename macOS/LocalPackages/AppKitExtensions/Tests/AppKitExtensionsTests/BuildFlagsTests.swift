//
//  BuildFlagsTests.swift
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
@testable import AppKitExtensions

final class BuildFlagsTests: XCTestCase {

    func testReleaseBuildWithProductionBundleIdentifierIsProduction() {
        let productionIdentifiers = [
            "com.duckduckgo.macos.browser",
            "com.duckduckgo.mobile.ios",
            "com.duckduckgo.mobile.ios.vpn.agent",
            "com.duckduckgo.mobile.ios.vpn.agent.network-extension",
            "com.duckduckgo.mobile.ios.vpn.agent.network-protection-extension",
            "com.duckduckgo.mobile.ios.DBP.backgroundAgent",
        ]

        for identifier in productionIdentifiers {
            XCTAssertTrue(BuildFlags.isProductionBuild(buildType: MockBuildType(), bundleIdentifier: identifier), identifier)
        }
    }

    func testDebugReviewAndAlphaBuildsAreNotProduction() {
        let identifier = "com.duckduckgo.macos.browser"

        XCTAssertFalse(BuildFlags.isProductionBuild(buildType: MockBuildType(isDebugBuild: true), bundleIdentifier: identifier))
        XCTAssertFalse(BuildFlags.isProductionBuild(buildType: MockBuildType(isReviewBuild: true), bundleIdentifier: identifier))
        XCTAssertFalse(BuildFlags.isProductionBuild(buildType: MockBuildType(isAlphaBuild: true), bundleIdentifier: identifier))
    }

    func testDebugBundleIdentifierIsNotProductionEvenWhenPackageCompiledWithoutDebug() {
        let ciIdentifiers = [
            "com.duckduckgo.macos.browser.debug",
            "com.duckduckgo.mobile.ios.debug",
            "com.duckduckgo.macos.vpn.debug",
            "com.duckduckgo.macos.vpn.network-extension.debug",
            "com.duckduckgo.mobile.ios.vpn.agent.debug.network-protection-extension",
            "com.duckduckgo.mobile.ios.DBP.backgroundAgent.debug",
        ]

        for identifier in ciIdentifiers {
            XCTAssertFalse(BuildFlags.isProductionBuild(buildType: MockBuildType(), bundleIdentifier: identifier), identifier)
        }
    }

    func testMissingBundleIdentifierFallsBackToBuildType() {
        XCTAssertTrue(BuildFlags.isProductionBuild(buildType: MockBuildType(), bundleIdentifier: nil))
        XCTAssertFalse(BuildFlags.isProductionBuild(buildType: MockBuildType(isDebugBuild: true), bundleIdentifier: nil))
    }
}

private struct MockBuildType: ApplicationBuildType {
    var isSparkleBuild: Bool = true
    var isAppStoreBuild: Bool = false
    var isDebugBuild: Bool = false
    var isReviewBuild: Bool = false
    var isAlphaBuild: Bool = false
}
