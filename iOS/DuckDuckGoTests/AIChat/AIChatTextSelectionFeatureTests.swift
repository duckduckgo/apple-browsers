//
//  AIChatTextSelectionFeatureTests.swift
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
import Core
import FeatureFlags_iOS

final class AIChatTextSelectionFeatureTests: XCTestCase {

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = true
    }

    private func makeFeature(textActions: Bool = true,
                             contextualUnifiedToggleInput: Bool = true,
                             unifiedToggleInputAvailable: Bool = true,
                             aiChatEnabled: Bool = true,
                             isIphone: Bool = true) -> AIChatTextSelectionFeature {
        var flags: [FeatureFlag] = []
        if textActions { flags.append(.aiChatTextActions) }
        if contextualUnifiedToggleInput { flags.append(.aiChatContextualUnifiedToggleInput) }
        MockDevicePlatform.isIphone = isIphone

        return AIChatTextSelectionFeature(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: flags),
            aiChatSettings: MockAIChatSettingsProvider(isAIChatEnabled: aiChatEnabled),
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: unifiedToggleInputAvailable),
            devicePlatform: MockDevicePlatform.self
        )
    }

    // MARK: - Ask Duck.ai

    func testWhenEveryConditionHoldsThenAskIsAvailable() {
        XCTAssertTrue(makeFeature().isAskAvailable)
    }

    func testWhenTextActionsFlagIsOffThenAskIsNotAvailable() {
        XCTAssertFalse(makeFeature(textActions: false).isAskAvailable)
    }

    func testWhenContextualUnifiedToggleInputFlagIsOffThenAskIsNotAvailable() {
        XCTAssertFalse(makeFeature(contextualUnifiedToggleInput: false).isAskAvailable)
    }

    func testWhenUnifiedToggleInputIsUnavailableThenAskIsNotAvailable() {
        XCTAssertFalse(makeFeature(unifiedToggleInputAvailable: false).isAskAvailable)
    }

    func testWhenDuckAIIsDisabledThenAskIsNotAvailable() {
        XCTAssertFalse(makeFeature(aiChatEnabled: false).isAskAvailable)
    }

    // MARK: - Search with DuckDuckGo

    func testWhenTextActionsFlagIsOnThenSearchIsAvailable() {
        XCTAssertTrue(makeFeature().isSearchAvailable)
    }

    func testWhenTextActionsFlagIsOffThenSearchIsNotAvailable() {
        XCTAssertFalse(makeFeature(textActions: false).isSearchAvailable)
    }

    func testWhenNotIphoneThenSearchIsNotAvailable() {
        XCTAssertFalse(makeFeature(isIphone: false).isSearchAvailable)
    }

    /// The point of splitting the gate: turning Duck.ai off must not take Search with it.
    func testWhenDuckAIIsDisabledThenSearchIsStillAvailable() {
        let feature = makeFeature(aiChatEnabled: false)
        XCTAssertFalse(feature.isAskAvailable)
        XCTAssertTrue(feature.isSearchAvailable)
    }

    func testWhenUnifiedToggleInputIsUnavailableThenSearchIsStillAvailable() {
        let feature = makeFeature(unifiedToggleInputAvailable: false)
        XCTAssertFalse(feature.isAskAvailable)
        XCTAssertTrue(feature.isSearchAvailable)
    }
}

/// Covers the per-tab half of the gate, which the feature type deliberately does not own.
final class TabViewControllerTextSelectionMenuTests: XCTestCase {

    private struct MockTextSelectionFeature: AIChatTextSelectionFeatureProviding {
        let isAskAvailable: Bool
        let isSearchAvailable: Bool
    }

    private func makeTab(isDuckAI: Bool, askAvailable: Bool = true, searchAvailable: Bool = true) -> TabViewController {
        let url = isDuckAI ? URL(string: "https://duck.ai")! : URL(string: "https://example.com")!
        let tab = TabViewController.fake(link: Link(title: nil, url: url))
        tab.aiChatTextSelectionFeature = MockTextSelectionFeature(isAskAvailable: askAvailable,
                                                                  isSearchAvailable: searchAvailable)
        return tab
    }

    func testWhenWebTabAndFeatureAvailableThenBothItemsAreAvailable() {
        let tab = makeTab(isDuckAI: false)
        XCTAssertTrue(tab.isAskAIChatSelectionItemAvailable)
        XCTAssertTrue(tab.isSearchSelectionItemAvailable)
    }

    func testWhenAskIsUnavailableThenSearchIsStillOffered() {
        let tab = makeTab(isDuckAI: false, askAvailable: false)
        XCTAssertFalse(tab.isAskAIChatSelectionItemAvailable)
        XCTAssertTrue(tab.isSearchSelectionItemAvailable)
    }

    func testWhenTabIsDuckAIThenNeitherItemIsOffered() {
        let tab = makeTab(isDuckAI: true)
        XCTAssertFalse(tab.isAskAIChatSelectionItemAvailable)
        XCTAssertFalse(tab.isSearchSelectionItemAvailable)
    }
}
