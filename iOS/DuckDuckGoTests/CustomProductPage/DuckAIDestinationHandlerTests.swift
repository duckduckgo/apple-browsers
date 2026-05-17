//
//  DuckAIDestinationHandlerTests.swift
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

import Foundation
import Testing
import AIChat
import Core
@testable import DuckDuckGo

@MainActor
@Suite("Custom Product Page - Duck AI Destination Handler")
struct DuckAIDestinationHandlerTests {
    let mockAIChatDeepLinkHandler: MockAIChatDeepLinkHandler
    let mockPresenter: MockAppStoreCustomProductPagePresenter
    let mockFeatureFlagger: MockFeatureFlagger
    let sut: DuckAIDestinationHandler

    init() {
        PixelFiringMock.tearDown()
        mockAIChatDeepLinkHandler = MockAIChatDeepLinkHandler()
        mockPresenter = MockAppStoreCustomProductPagePresenter()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.customProductPageDuckAiChat])
        sut = DuckAIDestinationHandler(
            aiChatDeepLinkHandler: mockAIChatDeepLinkHandler,
            pixelFiring: PixelFiringMock.self,
            featureFlagger: mockFeatureFlagger
        )
    }

    // MARK: - Feature Flag Enabled

    @Test("Forwards URL and presenter to the AI Chat deep link handler when feature flag is enabled")
    func forwardsURLAndPresenterToAIChatDeepLinkHandler() throws {
        // GIVEN
        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        sut.handle(url: url, on: mockPresenter)

        // THEN
        #expect(mockAIChatDeepLinkHandler.didHandleDeepLinkCalled)
        #expect(mockAIChatDeepLinkHandler.capturedURL == url)
        #expect(mockAIChatDeepLinkHandler.capturedPresenter === mockPresenter)
        #expect(mockAIChatDeepLinkHandler.capturedVoiceMode == false)
    }

    @Test("Fires the opened AI Chat daily pixel when feature flag is enabled")
    func firesOpenedAIChatDailyPixel() throws {
        // GIVEN
        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        sut.handle(url: url, on: mockPresenter)

        // THEN
        #expect(PixelFiringMock.lastDailyPixelInfo?.pixelName == Pixel.Event.customProductPageDuckAIOpenedAIChat.name)
        #expect(PixelFiringMock.lastDailyPixelInfo?.params?.isEmpty == true)
        #expect(PixelFiringMock.lastDailyPixelInfo?.error == nil)
    }

    // MARK: - Feature Flag Disabled

    @Test("Does not forward to the AI Chat deep link handler when feature flag is disabled")
    func doesNotForwardWhenFeatureFlagDisabled() throws {
        // GIVEN
        mockFeatureFlagger.enabledFeatureFlags = []
        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        sut.handle(url: url, on: mockPresenter)

        // THEN
        #expect(!mockAIChatDeepLinkHandler.didHandleDeepLinkCalled)
    }

    @Test("Does not fire the pixel when feature flag is disabled")
    func doesNotFirePixelWhenFeatureFlagDisabled() throws {
        // GIVEN
        mockFeatureFlagger.enabledFeatureFlags = []
        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        sut.handle(url: url, on: mockPresenter)

        // THEN
        #expect(PixelFiringMock.lastDailyPixelInfo == nil)
    }
}
