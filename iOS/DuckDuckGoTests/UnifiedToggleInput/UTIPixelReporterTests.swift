//
//  UTIPixelReporterTests.swift
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

import AIChat
import Core
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIPixelReporterTests: XCTestCase {

    private var pixelKitMock: PixelKitMock!

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
        pixelKitMock = PixelKitMock()
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
        pixelKitMock = nil
        super.tearDown()
    }

    private func makeReporter(context: @escaping () -> UTIPixelContext?) -> UTIPixelReporter {
        UTIPixelReporter(firing: UTIPixelFiring(pixel: PixelFiringMock.self,
                                                daily: PixelFiringMock.self,
                                                pixelKit: { [unowned self] in pixelKitMock }),
                         context: context)
    }

    private func context(surface: UnifiedToggleInputPixelSurface = .addressBar,
                         isDuckAISurfaceForAttribution: Bool = false,
                         inputMode: TextEntryMode = .search,
                         isToggleVisible: Bool = false,
                         pageType: UnifiedToggleInputPromptPageType = .unknown,
                         duckAIEntrySource: AIChatEntryPointSource? = nil) -> UTIPixelContext {
        UTIPixelContext(surface: surface,
                        isDuckAISurfaceForAttribution: isDuckAISurfaceForAttribution,
                        inputMode: inputMode,
                        isToggleVisible: isToggleVisible,
                        pageType: pageType,
                        duckAIEntrySource: duckAIEntrySource)
    }

    // MARK: - Omnibar surface shown (toggle visibility from live context)

    func testWhenOmnibarSurfaceShownWithToggleVisibleThenPixelReportsToggleVisibleTrue() {
        let reporter = makeReporter { self.context(isToggleVisible: true) }

        reporter.reportOmnibarInputSurfaceShown()

        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 2)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.name, "m_aichat_experimental_omnibar_shown_daily")
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.frequency, .legacyDailyNoSuffix)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, "m_aichat_experimental_omnibar_shown_count")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.frequency, .standard)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters, ["toggle_visible": "true"])
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.parameters, ["toggle_visible": "true"])
    }

    func testWhenOmnibarSurfaceShownWithToggleHiddenThenPixelReportsToggleVisibleFalse() {
        let reporter = makeReporter { self.context(isToggleVisible: false) }

        reporter.reportOmnibarInputSurfaceShown()

        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters, ["toggle_visible": "false"])
    }

    // MARK: - Mode switch (non-trivial params, passed per call)

    func testReportModeSwitchedResolvesDirectionTextAndDefaultPositionLive() {
        let reporter = makeReporter { self.context() }

        reporter.reportModeSwitched(to: .aiChat, currentText: "hello", defaultOmnibarMode: .duckAI)

        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.pixelName, Pixel.Event.aiChatExperimentalOmnibarModeSwitched.name)
        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.params, [
            "direction": "to_duckai",
            "had_text": "true",
            "default_position": "duckAI"
        ])
    }

    func testReportModeSwitchedToSearchWithBlankTextReportsNoText() {
        let reporter = makeReporter { self.context() }

        reporter.reportModeSwitched(to: .search, currentText: "   ", defaultOmnibarMode: .search)

        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.params, [
            "direction": "to_search",
            "had_text": "false",
            "default_position": "search"
        ])
    }

    // MARK: - Prompt submission (daily, non-trivial params)

    func testReportPromptSubmittedFiresDailyWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .duckAI, pageType: .duckAI, duckAIEntrySource: .addressBarIcon) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: "gpt-x",
                                       defaultOmnibarMode: .search,
                                       isFirstEverPrompt: false)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputPromptSubmitted.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [
            "selected_tool": "none",
            "model_id": "gpt-x",
            "reasoning_effort": "none",
            "has_image_attachment": "false",
            "has_file_attachment": "false",
            "has_text": "true",
            "surface": "duck_ai",
            "page_type": "duck_ai",
            "origin": "address_bar_icon",
            "default_mode": "search"
        ])
    }

    func testWhenFirstEverPromptSubmittedThenFirstPromptParamIsTrue() {
        let reporter = makeReporter { self.context(surface: .addressBar, pageType: .ntp) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .search,
                                       isFirstEverPrompt: true)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["first_prompt"], "true")
    }

    func testWhenPromptSubmittedFromAddressBarThenOriginIsAddressBarPrompt() {
        let reporter = makeReporter { self.context(surface: .addressBar, pageType: .serp) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .lastUsed,
                                       isFirstEverPrompt: false)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["origin"], "address_bar_prompt")
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["page_type"], "serp")
    }

    func testWhenPromptSubmittedOnDuckAITabWithUnknownEntryThenOriginIsAbsent() {
        let reporter = makeReporter { self.context(surface: .duckAI, pageType: .duckAI) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .lastUsed,
                                       isFirstEverPrompt: false)

        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo?.params?["origin"])
    }

    // MARK: - Query submission

    func testReportQuerySubmittedFiresDailyWithResolvedSurfacePageTypeAndToggleVisibility() {
        let reporter = makeReporter { self.context(surface: .addressBar, isToggleVisible: true, pageType: .serp) }

        reporter.reportQuerySubmitted(defaultOmnibarMode: .duckAI)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputQuerySubmitted.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [
            "surface": "address_bar",
            "page_type": "serp",
            "toggle_visible": "true",
            "default_mode": "duckAI"
        ])
    }

    func testWhenQuerySubmittedWithToggleHiddenThenToggleVisibleIsFalse() {
        let reporter = makeReporter { self.context(isToggleVisible: false) }

        reporter.reportQuerySubmitted(defaultOmnibarMode: .search)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["toggle_visible"], "false")
    }

    func testQueryAndPromptSubmittedShareTheKeysTheMixIsCutBy() {
        let reporter = makeReporter { self.context(surface: .addressBar, isToggleVisible: true, pageType: .ntp) }

        reporter.reportQuerySubmitted(defaultOmnibarMode: .search)
        let queryParams = PixelFiringMock.lastDailyPixelInfo?.params ?? [:]

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .search,
                                       isFirstEverPrompt: false)
        let promptParams = PixelFiringMock.lastDailyPixelInfo?.params ?? [:]

        for key in ["surface", "page_type", "default_mode"] {
            XCTAssertEqual(queryParams[key], promptParams[key], "\(key) must match across the two submission pixels")
        }
    }

    // MARK: - Regular pixel with surface from context

    func testReportModelSelectedFiresRegularWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .duckAI) }

        reporter.reportModelSelected(modelId: "m1")

        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputModelSelected.name)
        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.params, ["model_id": "m1", "surface": "duck_ai"])
    }

    // MARK: - Daily pixel with surface from context

    func testReportFileAttachedFiresDailyWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .addressBar) }

        reporter.reportFileAttached(source: "file_picker")

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputFileAttached.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, ["surface": "address_bar", "source": "file_picker"])
    }

    func testReportImageAttachedFiresDailyWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .addressBar) }

        reporter.reportImageAttached(source: "paste")

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputImageAttached.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, ["surface": "address_bar", "source": "paste"])
    }

    func testReportFileValidationFailedWithRawReasonFiresDaily() {
        let reporter = makeReporter { self.context(surface: .duckAI) }

        reporter.reportFileValidationFailed(reason: "size_exceeded", source: "paste")

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputFileValidationFailed.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [
            "reason": "size_exceeded",
            "surface": "duck_ai",
            "source": "paste"
        ])
    }

    // MARK: - Voice tap uses `source` (not `surface`) for its surface param

    func testReportVoiceTappedUsesSourceKey() {
        let reporter = makeReporter { self.context(surface: .contextualChat) }

        reporter.reportVoiceTapped(hasPendingPageContext: true)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputVoiceTapped.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [
            "source": "contextual_chat",
            "has_pending_page_context": "true"
        ])
    }

    // MARK: - Model-picker origin resolves from the live attribution flag

    func testReportModelPickerShownOriginDependsOnAttributionState() {
        makeReporter { self.context(isDuckAISurfaceForAttribution: true) }.reportModelPickerShown()
        let duckAIOrigin = PixelFiringMock.lastPixelInfo?.params
        PixelFiringMock.tearDown()

        makeReporter { self.context(isDuckAISurfaceForAttribution: false) }.reportModelPickerShown()
        let addressBarOrigin = PixelFiringMock.lastPixelInfo?.params

        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputModelPickerShown.name)
        XCTAssertNotNil(duckAIOrigin)
        XCTAssertNotNil(addressBarOrigin)
        XCTAssertNotEqual(duckAIOrigin, addressBarOrigin)
    }

    // MARK: - No context (coordinator gone) fires nothing

    func testNilContextFiresNothing() {
        let reporter = makeReporter { nil }

        reporter.reportModelSelected(modelId: "m1")
        reporter.reportFileAttached(source: "file_picker")

        XCTAssertNil(PixelFiringMock.lastPixelInfo)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }
}
