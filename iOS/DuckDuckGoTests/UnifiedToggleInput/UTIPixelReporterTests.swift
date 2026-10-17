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

    func testAttachmentPrivacyPixelsReportNamesKindsSurfacesAndFrequency() {
        let cases: [(AttachmentPrivacyPixel.Action, String)] = [
            (.shown, "aichat_unified_input_attachment_privacy_shown"),
            (.learnMoreTapped, "aichat_unified_input_attachment_privacy_learn_more_tapped")
        ]
        for surface in [UnifiedToggleInputPixelSurface.addressBar, .duckAI, .contextualChat] {
            let reporter = makeReporter { self.context(surface: surface) }
            for kind in [AttachmentPrivacyPixel.Kind.image, .file] {
                for (action, name) in cases {
                    reporter.reportAttachmentPrivacy(action, kind: kind)
                    let call = pixelKitMock.actualFireCalls.last
                    XCTAssertEqual(call?.pixel.name, name.replacingOccurrences(of: "privacy_", with: "privacy_\(kind.rawValue)_"))
                    XCTAssertEqual(call?.pixel.parameters, ["surface": surface.rawValue])
                    XCTAssertEqual(call?.frequency, .dailyAndCount)
                }
            }
        }
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 12)
    }

    func testWhenTabsAreSentThenCountUsesPrivacyBuckets() {
        let reporter = makeReporter { self.context(surface: .contextualChat) }
        reporter.makeTabSubmissionReporter(requestedTabCount: 0)(.init(totalTabCount: 0, additionalTabCount: 0))
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)

        for (count, bucket) in [(1, "one"), (2, "some"), (3, "some"), (4, "many"), (20, "many")] {
            reporter.makeTabSubmissionReporter(requestedTabCount: count)(.init(totalTabCount: count, additionalTabCount: count))
            let call = pixelKitMock.actualFireCalls.last
            XCTAssertEqual(call?.pixel.name, "aichat_unified_input_tabs_sent")
            XCTAssertEqual(call?.pixel.parameters, ["surface": "contextual_chat", "payload_tab_count": bucket])
            XCTAssertEqual(call?.frequency, .dailyAndCount)
        }
    }

    func testWhenReporterIsReleasedThenSubmissionKeepsOriginalSurface() throws {
        var liveContext: UTIPixelContext? = context(surface: .contextualChat)
        var reporter: UTIPixelReporter? = makeReporter { liveContext }
        weak var weakReporter = reporter
        let report = try XCTUnwrap(reporter).makeTabSubmissionReporter(requestedTabCount: 1)
        liveContext = context(surface: .addressBar)
        reporter = nil
        XCTAssertNil(weakReporter)
        liveContext = nil

        report(.init(totalTabCount: 2, additionalTabCount: 1))

        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters, ["surface": "contextual_chat", "payload_tab_count": "some"])
    }

    func testWhenSomeRequestedTabsAreMissingThenReportsPartialFailureAndSentCount() {
        let reporter = makeReporter { self.context(surface: .contextualChat) }
        reporter.makeTabSubmissionReporter(requestedTabCount: 3)(.init(totalTabCount: 2, additionalTabCount: 1))
        XCTAssertEqual(pixelKitMock.actualFireCalls.map(\.pixel.name), [
            "aichat_unified_input_tabs_sent", "aichat_unified_input_tabs_submission_incomplete"
        ])
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.parameters, ["surface": "contextual_chat", "outcome": "partial"])
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.frequency, .dailyAndCount)
    }

    func testWhenAllAdditionalTabsAreMissingThenCurrentPageDoesNotMaskFailure() {
        let reporter = makeReporter { self.context(surface: .contextualChat) }
        reporter.makeTabSubmissionReporter(requestedTabCount: 2)(.init(totalTabCount: 1, additionalTabCount: 0))
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.name, "aichat_unified_input_tabs_submission_incomplete")
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters, ["surface": "contextual_chat", "outcome": "all"])
    }

    func testWhenTabChipIsRemovedThenReportsOriginalSource() {
        let reporter = makeReporter { self.context(surface: .contextualChat) }
        let attachment = UnifiedToggleInputAttachment.tab(.init(
            tabId: "private-id", title: "Private title", url: URL(string: "https://example.com/private")!, source: .mention))

        reporter.reportAttachmentRemoved(attachment)

        XCTAssertEqual(pixelKitMock.actualFireCalls.map(\.pixel.name), [
            "aichat_unified_input_tab_removed"
        ])
        for call in pixelKitMock.actualFireCalls {
            XCTAssertEqual(call.pixel.parameters, ["surface": "contextual_chat", "source": "mention"])
            XCTAssertEqual(call.frequency, .dailyAndCount)
        }
    }

    func testWhenPickerSessionClosesThenReportsCancellationOnceOnlyWithoutChoice() {
        var actions: [MultiTabAttachmentPixel.Action] = []
        let session = MultiTabPickerPixelSession(surfaceProvider: { .contextualChat }) { action, _ in actions.append(action) }
        session.finish()
        session.show()
        session.show()
        session.finish()
        session.finish()
        XCTAssertEqual(actions, [.pickerShown, .pickerCanceled])

        session.show()
        session.finish(didChoose: true)
        session.finish()
        XCTAssertEqual(actions, [.pickerShown, .pickerCanceled, .pickerShown])
    }

    func testWhenPickerSurfaceChangesThenCancellationKeepsShownSurfaceAndNextSessionRefreshesIt() {
        for source in [TabAttachmentOrigin.mention, .tabPicker] {
            var liveContext: UTIPixelContext? = context(surface: .addressBar)
            let reporter = makeReporter { liveContext }
            let session = MultiTabPickerPixelSession(surfaceProvider: { liveContext?.surface }) {
                reporter.reportTabAttachment($0, source: source, surface: $1)
            }
            let fireCount = pixelKitMock.actualFireCalls.count

            liveContext = context(surface: .contextualChat)
            session.show()
            liveContext = context(surface: .duckAI)
            session.show()
            session.finish()
            session.finish()

            session.show()
            liveContext = nil
            session.finish()

            let calls = Array(pixelKitMock.actualFireCalls.dropFirst(fireCount))
            XCTAssertEqual(calls.map(\.pixel.name), [
                "aichat_unified_input_tab_picker_shown", "aichat_unified_input_tab_picker_canceled",
                "aichat_unified_input_tab_picker_shown", "aichat_unified_input_tab_picker_canceled"
            ])
            XCTAssertEqual(calls.compactMap { $0.pixel.parameters?["surface"] }, ["contextual_chat", "contextual_chat", "duck_ai", "duck_ai"])
            for call in calls {
                XCTAssertEqual(call.pixel.parameters?["source"], source == .mention ? "mention" : "tab_picker")
                XCTAssertEqual(call.frequency, .dailyAndCount)
            }
        }
    }

    func testWhenPickerChoiceSucceedsThenNextSessionUsesNewSurface() {
        var surface: UnifiedToggleInputPixelSurface = .contextualChat
        let reporter = makeReporter { self.context(surface: surface) }
        let session = MultiTabPickerPixelSession(surfaceProvider: { surface }) {
            reporter.reportTabAttachment($0, source: .mention, surface: $1)
        }

        session.show()
        session.finish(didChoose: true)
        surface = .addressBar
        session.show()
        session.finish()

        XCTAssertEqual(pixelKitMock.actualFireCalls.map(\.pixel.name), [
            "aichat_unified_input_tab_picker_shown", "aichat_unified_input_tab_picker_shown", "aichat_unified_input_tab_picker_canceled"
        ])
        XCTAssertEqual(pixelKitMock.actualFireCalls.compactMap { $0.pixel.parameters?["surface"] }, ["contextual_chat", "address_bar", "address_bar"])
    }

    func testWhenPickerHasNoSurfaceAtShowThenDoesNotReportAnUnmatchedCancellation() {
        var surface: UnifiedToggleInputPixelSurface?
        let reporter = makeReporter { self.context(surface: .addressBar) }
        let session = MultiTabPickerPixelSession(surfaceProvider: { surface }) {
            reporter.reportTabAttachment($0, source: .mention, surface: $1)
        }

        session.show()
        surface = .contextualChat
        session.show()
        session.finish()
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)

        session.show()
        session.finish()
        XCTAssertEqual(pixelKitMock.actualFireCalls.map(\.pixel.name), [
            "aichat_unified_input_tab_picker_shown", "aichat_unified_input_tab_picker_canceled"
        ])
        XCTAssertEqual(pixelKitMock.actualFireCalls.compactMap { $0.pixel.parameters?["surface"] }, ["contextual_chat", "contextual_chat"])
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

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["first_prompt_new_install"], "true")
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
