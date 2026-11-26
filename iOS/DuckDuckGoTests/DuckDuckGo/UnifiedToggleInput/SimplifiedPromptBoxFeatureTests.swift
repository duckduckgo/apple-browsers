//
//  SimplifiedPromptBoxFeatureTests.swift
//  DuckDuckGo
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

import Common
import FeatureFlags_iOS
import XCTest
@testable import DuckDuckGo

final class SimplifiedPromptBoxFeatureTests: XCTestCase {

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = true
    }

    private func makeFeature(enabledFlags: [FeatureFlag] = [.unifiedToggleInputSimplifiedPromptBox],
                             isIphone: Bool = true) -> SimplifiedPromptBoxFeature {
        MockDevicePlatform.isIphone = isIphone
        return SimplifiedPromptBoxFeature(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFlags),
                                          devicePlatform: MockDevicePlatform.self)
    }

    func testWhenIphoneAndFlagOnThenIsAvailable() {
        XCTAssertTrue(makeFeature().isAvailable)
    }

    func testWhenFlagOffThenIsNotAvailable() {
        XCTAssertFalse(makeFeature(enabledFlags: []).isAvailable)
    }

    func testWhenIpadThenIsNotAvailable() {
        XCTAssertFalse(makeFeature(isIphone: false).isAvailable)
    }

    func testWhenTheFlagChangesThenAvailabilityFollowsIt() {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.isIphone = true
        let feature = SimplifiedPromptBoxFeature(featureFlagger: featureFlagger, devicePlatform: MockDevicePlatform.self)
        XCTAssertFalse(feature.isAvailable)

        featureFlagger.enabledFeatureFlags = [.unifiedToggleInputSimplifiedPromptBox]

        XCTAssertTrue(feature.isAvailable)
    }
}
