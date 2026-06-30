//
//  IPadDuckAIControlsFeatureTests.swift
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

import XCTest
@testable import DuckDuckGo
@testable import Core

final class IPadDuckAIControlsFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    // MARK: - Tests

    func testWhenFeatureOnAndNotIphoneThenIsAvailable() {
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadDuckAIBarControls])
        MockDevicePlatform.isIphone = false

        let feature = IPadDuckAIControlsFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        XCTAssertTrue(feature.isAvailable)
    }

    func testWhenFeatureOnAndIphoneThenIsNotAvailable() {
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadDuckAIBarControls])
        MockDevicePlatform.isIphone = true

        let feature = IPadDuckAIControlsFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenFeatureOffAndNotIphoneThenIsNotAvailable() {
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.isIphone = false

        let feature = IPadDuckAIControlsFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenFeatureOffAndIphoneThenIsNotAvailable() {
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.isIphone = true

        let feature = IPadDuckAIControlsFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        XCTAssertFalse(feature.isAvailable)
    }
}
