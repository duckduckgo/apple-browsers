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
import BrowserServicesKitTestsUtils
import Core
import Persistence
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIPixelReporterTests: XCTestCase {

    private var pixelKitMock: PixelKitMock!

    override func setUp() {
        super.setUp()
        pixelKitMock = PixelKitMock()
    }

    override func tearDown() {
        pixelKitMock = nil
        super.tearDown()
    }

    private func makeReporter(context: @escaping () -> UTIPixelContext?) -> UTIPixelReporter {
        UTIPixelReporter(firing: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
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

        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 3)
        XCTAssertEqual(pixelKitMock.actualFireCalls[0].pixel.name, Pixel.Event.aiChatInternalSwitchBarDisplayed.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls[1].pixel.name, "m_aichat_experimental_omnibar_shown_daily")
        XCTAssertEqual(pixelKitMock.actualFireCalls[1].frequency, .legacyDailyNoSuffix)
        XCTAssertEqual(pixelKitMock.actualFireCalls[2].pixel.name, "m_aichat_experimental_omnibar_shown_count")
        XCTAssertEqual(pixelKitMock.actualFireCalls[2].frequency, .standard)
        XCTAssertEqual(pixelKitMock.actualFireCalls[1].pixel.parameters, ["toggle_visible": "true"])
        XCTAssertEqual(pixelKitMock.actualFireCalls[2].pixel.parameters, ["toggle_visible": "true"])
    }

    func testWhenOmnibarSurfaceShownWithToggleHiddenThenPixelReportsToggleVisibleFalse() {
        let reporter = makeReporter { self.context(isToggleVisible: false) }

        reporter.reportOmnibarInputSurfaceShown()

        XCTAssertEqual(pixelKitMock.actualFireCalls[1].pixel.parameters, ["toggle_visible": "false"])
    }

    // MARK: - Mode switch (non-trivial params, passed per call)

    func testReportModeSwitchedResolvesDirectionTextAndDefaultPositionLive() {
        let reporter = makeReporter { self.context() }

        reporter.reportModeSwitched(to: .aiChat, currentText: "hello", defaultOmnibarMode: .duckAI)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatExperimentalOmnibarModeSwitched.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
            "direction": "to_duckai",
            "had_text": "true",
            "default_position": "duckAI"
        ])
    }

    func testReportModeSwitchedToSearchWithBlankTextReportsNoText() {
        let reporter = makeReporter { self.context() }

        reporter.reportModeSwitched(to: .search, currentText: "   ", defaultOmnibarMode: .search)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
            "direction": "to_search",
            "had_text": "false",
            "default_position": "search"
        ])
    }

    // MARK: - Prompt origin

    func testCurrentPromptOriginMatchesTheSurfaceTheSubmissionPixelsReport() {
        XCTAssertEqual(makeReporter { self.context(surface: .addressBar) }.currentPromptOrigin(), .addressBarPrompt)
        XCTAssertEqual(makeReporter { self.context(surface: .contextualChat) }.currentPromptOrigin(), .contextualChat)
        XCTAssertEqual(makeReporter { self.context(surface: .duckAI, duckAIEntrySource: .tabSwitcher) }.currentPromptOrigin(),
                       .tabSwitcher)
    }

    func testCurrentPromptOriginIsNilOnADuckAISurfaceWithNoRecordedEntry() {
        XCTAssertNil(makeReporter { self.context(surface: .duckAI, duckAIEntrySource: nil) }.currentPromptOrigin())
    }

    func testCurrentPromptOriginIsNilWhenTheCoordinatorIsGone() {
        XCTAssertNil(makeReporter { nil }.currentPromptOrigin())
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
                                       isFirstPromptNewInstall: false)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputPromptSubmitted.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
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

    func testWhenFirstPromptOnNewInstallSubmittedThenParamIsTrue() {
        let reporter = makeReporter { self.context(surface: .addressBar, pageType: .ntp) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .search,
                                       isFirstPromptNewInstall: true)

        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["first_prompt_new_install"], "true")
    }

    func testWhenPromptSubmittedFromAddressBarThenOriginIsAddressBarPrompt() {
        let reporter = makeReporter { self.context(surface: .addressBar, pageType: .serp) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .lastUsed,
                                       isFirstPromptNewInstall: false)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["origin"], "address_bar_prompt")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["page_type"], "serp")
    }

    func testWhenPromptSubmittedOnDuckAITabWithUnknownEntryThenOriginIsAbsent() {
        let reporter = makeReporter { self.context(surface: .duckAI, pageType: .duckAI) }

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .lastUsed,
                                       isFirstPromptNewInstall: false)

        XCTAssertNil(pixelKitMock.actualFireCalls.last?.additionalParameters?["origin"])
    }

    // MARK: - Query submission

    func testReportQuerySubmittedFiresDailyWithResolvedSurfacePageTypeAndToggleVisibility() {
        let reporter = makeReporter { self.context(surface: .addressBar, isToggleVisible: true, pageType: .serp) }

        reporter.reportQuerySubmitted(defaultOmnibarMode: .duckAI)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputQuerySubmitted.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
            "surface": "address_bar",
            "page_type": "serp",
            "toggle_visible": "true",
            "default_mode": "duckAI"
        ])
    }

    func testWhenQuerySubmittedWithToggleHiddenThenToggleVisibleIsFalse() {
        let reporter = makeReporter { self.context(isToggleVisible: false) }

        reporter.reportQuerySubmitted(defaultOmnibarMode: .search)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["toggle_visible"], "false")
    }

    func testQueryAndPromptSubmittedShareTheKeysTheMixIsCutBy() {
        let reporter = makeReporter { self.context(surface: .addressBar, isToggleVisible: true, pageType: .ntp) }

        reporter.reportQuerySubmitted(defaultOmnibarMode: .search)
        let queryParams = pixelKitMock.actualFireCalls.last?.additionalParameters ?? [:]

        reporter.reportPromptSubmitted(hasText: true,
                                       selectedTool: nil,
                                       attachments: [],
                                       reasoningMode: nil,
                                       modelId: nil,
                                       defaultOmnibarMode: .search,
                                       isFirstPromptNewInstall: false)
        let promptParams = pixelKitMock.actualFireCalls.last?.additionalParameters ?? [:]

        for key in ["surface", "page_type", "default_mode"] {
            XCTAssertEqual(queryParams[key], promptParams[key], "\(key) must match across the two submission pixels")
        }
    }

    // MARK: - Regular pixel with surface from context

    func testReportModelSelectedFiresRegularWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .duckAI) }

        reporter.reportModelSelected(modelId: "m1")

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputModelSelected.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, ["model_id": "m1", "surface": "duck_ai"])
    }

    // MARK: - Daily pixel with surface from context

    func testReportFileAttachedFiresDailyWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .addressBar) }

        reporter.reportFileAttached(source: "file_picker")

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputFileAttached.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, ["surface": "address_bar", "source": "file_picker"])
    }

    func testReportImageAttachedFiresDailyWithResolvedSurface() {
        let reporter = makeReporter { self.context(surface: .addressBar) }

        reporter.reportImageAttached(source: "paste")

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputImageAttached.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, ["surface": "address_bar", "source": "paste"])
    }

    func testReportFileValidationFailedWithRawReasonFiresDaily() {
        let reporter = makeReporter { self.context(surface: .duckAI) }

        reporter.reportFileValidationFailed(reason: "size_exceeded", source: "paste")

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputFileValidationFailed.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
            "reason": "size_exceeded",
            "surface": "duck_ai",
            "source": "paste"
        ])
    }

    // MARK: - Voice tap uses `source` (not `surface`) for its surface param

    func testReportVoiceTappedUsesSourceKey() {
        let reporter = makeReporter { self.context(surface: .contextualChat) }

        reporter.reportVoiceTapped(hasPendingPageContext: true)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputVoiceTapped.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
            "source": "contextual_chat",
            "has_pending_page_context": "true"
        ])
    }

    // MARK: - Model-picker origin resolves from the live attribution flag

    func testReportModelPickerShownOriginDependsOnAttributionState() {
        makeReporter { self.context(isDuckAISurfaceForAttribution: true) }.reportModelPickerShown()
        let duckAIOrigin = pixelKitMock.actualFireCalls.last?.additionalParameters

        makeReporter { self.context(isDuckAISurfaceForAttribution: false) }.reportModelPickerShown()
        let addressBarOrigin = pixelKitMock.actualFireCalls.last?.additionalParameters

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputModelPickerShown.name)
        XCTAssertNotNil(duckAIOrigin)
        XCTAssertNotNil(addressBarOrigin)
        XCTAssertNotEqual(duckAIOrigin, addressBarOrigin)
    }

    // MARK: - No context (coordinator gone) fires nothing

    func testNilContextFiresNothing() {
        let reporter = makeReporter { nil }

        reporter.reportModelSelected(modelId: "m1")
        reporter.reportFileAttached(source: "file_picker")

        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }
}

final class DuckAIFirstPromptNewInstallCohortTests: XCTestCase {

    private var featureDiscovery: MockFeatureDiscovery!
    private var statisticsStore: MockStatisticsStore!
    private var marker: MockKeyValueStore!

    override func setUp() {
        super.setUp()
        featureDiscovery = MockFeatureDiscovery()
        statisticsStore = MockStatisticsStore()
        marker = MockKeyValueStore()
    }

    override func tearDown() {
        featureDiscovery = nil
        statisticsStore = nil
        marker = nil
        super.tearDown()
    }

    private func assignCohort() {
        DuckAIFirstPromptNewInstallCohort.assignIfNeeded(statisticsStore: statisticsStore,
                                                         featureDiscovery: featureDiscovery,
                                                         marker: marker)
    }

    func testWhenInstallHasStatisticsThenExistingInstallIsMarkedAsPrompted() {
        statisticsStore.atb = "v456-7"

        assignCohort()

        XCTAssertTrue(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }

    func testWhenBrandNewInstallThenFlagStaysUnset() {
        assignCohort()

        XCTAssertFalse(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }

    /// A new install's second launch has install statistics; only the marker keeps it in the cohort.
    func testWhenCohortAlreadyAssignedThenLaterLaunchesWithStatisticsDoNotMark() {
        assignCohort()
        statisticsStore.atb = "v456-7"

        assignCohort()

        XCTAssertFalse(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }
}

private final class MockKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
}
