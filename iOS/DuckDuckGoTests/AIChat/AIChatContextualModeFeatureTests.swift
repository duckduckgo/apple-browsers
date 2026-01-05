//
//  AIChatContextualModeFeatureTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo
@testable import Core

final class AIChatContextualModeFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        var mockIsIphone: Bool = false
        static var isIphone: Bool {
            shared.mockIsIphone
        }
        static let shared = MockDevicePlatform()
    }

    // MARK: - Tests

    func testIsAvailableWhenFeatureFlagOnAndIphone() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [.contextualDuckAIMode])
        MockDevicePlatform.shared.mockIsIphone = true

        // When
        let feature = AIChatContextualModeFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertTrue(feature.isAvailable)
    }

    func testIsNotAvailableWhenFeatureFlagOnButNotIphone() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [.contextualDuckAIMode])
        MockDevicePlatform.shared.mockIsIphone = false

        // When
        let feature = AIChatContextualModeFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertFalse(feature.isAvailable)
    }

    func testIsNotAvailableWhenFeatureFlagOffButIsIphone() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.shared.mockIsIphone = true

        // When
        let feature = AIChatContextualModeFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertFalse(feature.isAvailable)
    }

    func testIsNotAvailableWhenFeatureFlagOffAndNotIphone() {
        // Given
        let mockFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        MockDevicePlatform.shared.mockIsIphone = false

        // When
        let feature = AIChatContextualModeFeature(
            featureFlagger: mockFlagger,
            devicePlatform: MockDevicePlatform.self
        )

        // Then
        XCTAssertFalse(feature.isAvailable)
    }

}
