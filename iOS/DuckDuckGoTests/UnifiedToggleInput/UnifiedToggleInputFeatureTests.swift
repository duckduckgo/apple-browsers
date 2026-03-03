//
//  UnifiedToggleInputFeatureTests.swift
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

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    // MARK: - Helpers

    private func makeFeature(flagEnabled: Bool, isIphone: Bool) -> UnifiedToggleInputFeature {
        MockDevicePlatform.isIphone = isIphone
        let flags: [FeatureFlag] = flagEnabled ? [.unifiedToggleInput] : []
        return UnifiedToggleInputFeature(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: flags),
            devicePlatform: MockDevicePlatform.self
        )
    }

    // MARK: - Tests

    func test_isAvailable_whenFlagOnAndIphone() {
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOnButNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: true, isIphone: false).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffButIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffAndNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: false).isAvailable)
    }
}
