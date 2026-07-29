//
//  AIChatContextualFloatingInputFeatureTests.swift
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

final class AIChatContextualFloatingInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        var mockIsIphone: Bool = true
        static var isIphone: Bool {
            shared.mockIsIphone
        }
        static let shared = MockDevicePlatform()
    }

    private struct MockUnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {
        var isAvailable: Bool
        var isToggleHiddenOnDuckAITab: Bool = false
        var isAttachmentPasteEnabled: Bool = false
    }

    // MARK: - Helpers

    private func makeFeature(
        enabledFlags: [FeatureFlag] = [.aiChatContextualFloatingInput],
        isIphone: Bool = true,
        isUnifiedToggleInputAvailable: Bool = true
    ) -> AIChatContextualFloatingInputFeature {
        MockDevicePlatform.shared.mockIsIphone = isIphone
        return AIChatContextualFloatingInputFeature(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFlags),
            devicePlatform: MockDevicePlatform.self,
            unifiedToggleInputFeature: MockUnifiedToggleInputFeature(isAvailable: isUnifiedToggleInputAvailable)
        )
    }

    // MARK: - Tests

    func testWhenIphoneAndFlagOnAndUnifiedToggleInputAvailableThenIsAvailable() {
        XCTAssertTrue(makeFeature().isAvailable)
    }

    func testWhenFlagOffThenIsNotAvailable() {
        XCTAssertFalse(makeFeature(enabledFlags: []).isAvailable)
    }

    func testWhenIpadThenIsNotAvailable() {
        XCTAssertFalse(makeFeature(isIphone: false).isAvailable)
    }

    func testWhenUnifiedToggleInputUnavailableThenIsNotAvailable() {
        XCTAssertFalse(makeFeature(isUnifiedToggleInputAvailable: false).isAvailable)
    }
}
