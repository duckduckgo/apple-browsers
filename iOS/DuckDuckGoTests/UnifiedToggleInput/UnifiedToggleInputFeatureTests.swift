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
import PrivacyConfig
import FeatureFlags_iOS

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    func test_isAvailable_onIphone() {
        MockDevicePlatform.isIphone = true
        let feature = UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)

        XCTAssertTrue(feature.isAvailable)
    }

    func test_isNotAvailable_onIPad() {
        MockDevicePlatform.isIphone = false
        let feature = UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)

        XCTAssertFalse(feature.isAvailable)
    }

    func test_resolve_snapshotsRemainingFlags() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatTabHideToggle, .unifiedToggleInputAttachmentPaste])
        UnifiedToggleInputFeature.resolve(using: flagger)
        let feature = UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
        XCTAssertTrue(feature.isToggleHiddenOnDuckAITab)
        XCTAssertTrue(feature.isAttachmentPasteEnabled)

        flagger.enabledFeatureFlags = []
        XCTAssertTrue(feature.isToggleHiddenOnDuckAITab)
        XCTAssertTrue(feature.isAttachmentPasteEnabled)

        UnifiedToggleInputFeature.resolve(using: flagger)
        XCTAssertFalse(feature.isToggleHiddenOnDuckAITab)
        XCTAssertFalse(feature.isAttachmentPasteEnabled)
    }
}
