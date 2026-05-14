//
//  AIChatIPadTabFeatureTests.swift
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

final class AIChatIPadTabFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    // MARK: - Tests

    func testWhenFeatureOnAndNotIphoneThenIsAvailable() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadDuckaiOnTab])
        MockDevicePlatform.isIphone = false

        // When
        let feature = AIChatIPadTabFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertTrue(feature.isAvailable)
    }

    func testWhenFeatureOnAndIphoneThenIsNotAvailable() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadDuckaiOnTab])
        MockDevicePlatform.isIphone = true

        // When
        let feature = AIChatIPadTabFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenFeatureOffAndNotIphoneThenIsNotAvailable() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.isIphone = false

        // When
        let feature = AIChatIPadTabFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenFeatureOffAndIphoneThenIsNotAvailable() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.isIphone = true

        // When
        let feature = AIChatIPadTabFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertFalse(feature.isAvailable)
    }
}
