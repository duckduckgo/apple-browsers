//
//  AnimationsAvailabilityDeciderTests.swift
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

@testable import DuckDuckGo_Privacy_Browser
import PrivacyConfig
import XCTest

final class AnimationsAvailabilityDeciderTests: XCTestCase {

    func testAnimationsAreDisabledBelowMacOs12() {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.tabAnimations]

        for majorVersion in [10, 11] {
            let decider = AnimationsAvailabilityDecider(featureFlagger: flagger, osVersion: OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0))
            XCTAssertFalse(decider.displaysTabsAnimations)
        }
    }

    func testAnimationsAreDisabledWhenFeatureFlagIsOffOnOrAboveMacOs12() {
        let flagger = MockFeatureFlagger()

        for majorVersion in [12, 13, 14, 15, 26] {
            let decider = AnimationsAvailabilityDecider(featureFlagger: flagger, osVersion: OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0))
            XCTAssertFalse(decider.displaysTabsAnimations)
        }
    }

    func testAnimationsAreEnabledOnOrAboveMacOs12() {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.tabAnimations]

        for majorVersion in [12, 13, 14, 15, 26] {
            let decider = AnimationsAvailabilityDecider(featureFlagger: flagger, osVersion: OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0))
            XCTAssertTrue(decider.displaysTabsAnimations)
        }
    }
}
