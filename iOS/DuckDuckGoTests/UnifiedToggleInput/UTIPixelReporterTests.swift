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
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIPixelReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    private func makeReporter(context: @escaping () -> UTIPixelContext?) -> UTIPixelReporter {
        UTIPixelReporter(firing: UTIPixelFiring(pixel: PixelFiringMock.self, daily: PixelFiringMock.self),
                         context: context)
    }

    private func context(surface: UnifiedToggleInputPixelSurface = .addressBar,
                         isDuckAISurfaceForAttribution: Bool = false,
                         inputMode: TextEntryMode = .search) -> UTIPixelContext {
        UTIPixelContext(surface: surface,
                        isDuckAISurfaceForAttribution: isDuckAISurfaceForAttribution,
                        inputMode: inputMode)
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
        let reporter = makeReporter { self.context(surface: .duckAI) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: "gpt-x")

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputPromptSubmitted.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [
            "selected_tool": "none",
            "model_id": "gpt-x",
            "reasoning_effort": "none",
            "has_image_attachment": "false",
            "has_file_attachment": "false",
            "has_text": "true",
            "surface": "duck_ai"
        ])
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
