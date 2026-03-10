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

    // MARK: - Helpers

    private static let duckAIURL = URL(string: "https://duck.ai")!
    private static let nonDuckAIURL = URL(string: "https://duckduckgo.com")!

    private func makeFeature(
        enabledFlags: [FeatureFlag] = [.contextualDuckAIMode, .pageContextFeature],
        isIphone: Bool = true,
        aiChatURL: URL = duckAIURL
    ) -> AIChatContextualModeFeature {
        MockDevicePlatform.shared.mockIsIphone = isIphone
        return AIChatContextualModeFeature(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFlags),
            devicePlatform: MockDevicePlatform.self,
            aiChatURLProvider: { aiChatURL }
        )
    }

    // MARK: - iPhone Tests

    func testWhenIphoneAndAllConditionsMetThenIsAvailable() {
        let feature = makeFeature()
        XCTAssertTrue(feature.isAvailable)
    }

    func testWhenIphoneAndContextualDuckAIModeDisabledThenIsNotAvailable() {
        let feature = makeFeature(enabledFlags: [.pageContextFeature])
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenIphoneAndPageContextFeatureDisabledThenIsNotAvailable() {
        let feature = makeFeature(enabledFlags: [.contextualDuckAIMode])
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenIphoneAndURLDomainIsNotDuckAIThenIsNotAvailable() {
        let feature = makeFeature(aiChatURL: Self.nonDuckAIURL)
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenIphoneAndOnlyIPadPageContextEnabledThenIsNotAvailable() {
        let feature = makeFeature(
            enabledFlags: [.contextualDuckAIMode, .iPadPageContext],
            isIphone: true
        )
        XCTAssertFalse(feature.isAvailable)
    }

    // MARK: - iPad Tests

    func testWhenIPadAndIpadPageContextEnabledThenIsAvailable() {
        let feature = makeFeature(
            enabledFlags: [.contextualDuckAIMode, .iPadPageContext],
            isIphone: false
        )
        XCTAssertTrue(feature.isAvailable)
    }

    func testWhenIPadAndIpadPageContextDisabledThenIsNotAvailable() {
        let feature = makeFeature(
            enabledFlags: [.contextualDuckAIMode],
            isIphone: false
        )
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenIPadAndOnlyIphonePageContextEnabledThenIsNotAvailable() {
        let feature = makeFeature(
            enabledFlags: [.contextualDuckAIMode, .pageContextFeature],
            isIphone: false
        )
        XCTAssertFalse(feature.isAvailable)
    }

    func testWhenIPadAndURLDomainIsNotDuckAIThenIsNotAvailable() {
        let feature = makeFeature(
            enabledFlags: [.contextualDuckAIMode, .iPadPageContext],
            isIphone: false,
            aiChatURL: Self.nonDuckAIURL
        )
        XCTAssertFalse(feature.isAvailable)
    }

}
