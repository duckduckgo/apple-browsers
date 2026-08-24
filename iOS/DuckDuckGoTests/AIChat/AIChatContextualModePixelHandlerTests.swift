//
//  AIChatContextualModePixelHandlerTests.swift
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

import Testing
import BrowserServicesKitTestsUtils
import Core
import PixelKit
@testable import DuckDuckGo

@Suite("AI Chat Contextual Mode Pixel Handler Tests", .serialized)
final class AIChatContextualModePixelHandlerTests {

    deinit {
        PixelFiringMock.tearDown()
    }

    // MARK: - Sheet Lifecycle Pixels

    @Test("Sheet opened pixel fires correctly")
    func testSheetOpenedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireSheetOpened()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualSheetOpened.name)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sheet dismissed pixel fires correctly", .timeLimit(.minutes(1)), arguments: [true, false])
    func testSheetDismissedPixel(hadUnsubmittedSelections: Bool) {
        // GIVEN
        var firedEventName: String?
        var firedParameters: [String: String]?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { event, parameters in
                firedEventName = event.name
                firedParameters = parameters
            })

        // WHEN
        sut.fireSheetDismissed(hadUnsubmittedSelections: hadUnsubmittedSelections)

        // THEN
        #expect(firedEventName == Pixel.Event.aiChatContextualSheetDismissed.name)
        #expect(firedParameters == ["had_unsubmitted_selections": String(hadUnsubmittedSelections)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Floating input dismissed pixel includes unsubmitted selection state", .timeLimit(.minutes(1)), arguments: [true, false])
    func floatingInputDismissedPixel(hadUnsubmittedSelections: Bool) {
        var firedEventName: String?
        var firedParameters: [String: String]?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { event, parameters in
                firedEventName = event.name
                firedParameters = parameters
            })

        sut.fireFloatingInputDismissedWithoutSubmission(hadUnsubmittedSelections: hadUnsubmittedSelections)

        #expect(firedEventName == Pixel.Event.aiChatContextualFloatingInputDismissedWithoutSubmission.name)
        #expect(firedParameters == ["had_unsubmitted_selections": String(hadUnsubmittedSelections)])
    }

    @Test("Session restored pixel fires correctly")
    func testSessionRestoredPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireSessionRestored()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualSessionRestored.name)
    }

    // MARK: - Sheet Action Pixels

    @Test("Expand button tapped pixel fires correctly")
    func testExpandButtonTappedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireExpandButtonTapped()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualExpandButtonTapped.name)
    }

    @Test("New chat button tapped pixel fires correctly")
    func testNewChatButtonTappedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireNewChatButtonTapped()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualNewChatButtonTapped.name)
    }

    @Test("Quick action summarize selected pixel fires correctly")
    func testQuickActionSummarizeSelectedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireQuickActionSummarizeSelected()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualQuickActionSummarizeSelected.name)
    }

    // MARK: - Suggested Prompt Pixels

    @available(iOS 16, macOS 13, *)
    @Test("Suggestion selected includes suggestion id and page type", .timeLimit(.minutes(1)))
    func suggestion_selected_includes_suggestion_id_and_page_type() {
        var firedEventName: String?
        var firedParameters: [String: String]?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { event, parameters in
                firedEventName = event.name
                firedParameters = parameters
            })

        sut.fireSuggestionSelected(suggestionId: "shopping-list", pageType: .recipe)

        #expect(firedEventName == Pixel.Event.aiChatContextualSuggestionSelected.name)
        #expect(firedParameters == ["suggestionId": "shopping-list", "pageType": "recipe"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ask about page uses the cross-platform suggestion id", .timeLimit(.minutes(1)))
    func ask_about_page_uses_cross_platform_suggestion_id() {
        var firedEventName: String?
        var firedParameters: [String: String]?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { event, parameters in
                firedEventName = event.name
                firedParameters = parameters
            })

        sut.fireAskAboutPageSuggestionSelected(pageType: .article)

        #expect(firedEventName == Pixel.Event.aiChatContextualSuggestionSelected.name)
        #expect(firedParameters == ["suggestionId": "ask-about-page", "pageType": "article"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Suggestions viewed includes smartness, page type, scope, and surface", .timeLimit(.minutes(1)))
    func suggestions_viewed_includes_smartness_page_type_scope_and_surface() {
        var firedEventName: String?
        var firedParameters: [String: String]?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { event, parameters in
                firedEventName = event.name
                firedParameters = parameters
            })

        sut.fireSuggestionsViewed(isSmart: true, pageType: .video, scope: .selection, surface: .floatingInput)

        #expect(firedEventName == Pixel.Event.aiChatContextualSuggestionsViewed.name)
        #expect(firedParameters == [
            "isSmart": "true",
            "pageType": "video",
            "suggestion_scope": "selection",
            "surface": "floating_input"
        ])
    }

    // MARK: - Page Context Attachment Pixels

    @Test("Page context auto attached pixel fires correctly")
    func testPageContextAutoAttachedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextAutoAttached()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextAutoAttached.name)
    }

    @Test("Page context manually attached native pixel fires correctly")
    func testPageContextManuallyAttachedNativePixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextManuallyAttachedNative()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextManuallyAttachedNative.name)
    }

    @Test("Page context manually attached frontend pixel fires correctly")
    func testPageContextManuallyAttachedFrontendPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextManuallyAttachedFrontend()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextManuallyAttachedFrontend.name)
    }

    // MARK: - Navigation Pixel with Deduplication

    @Test("Page context updated on navigation fires for new URL")
    func testPageContextUpdatedOnNavigationFirstTime() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextUpdatedOnNavigation.name)
    }

    @Test("Page context updated on navigation fires for different URL")
    func testPageContextUpdatedOnNavigationDifferentURLs() {
        // GIVEN
        var pixelCount = 0
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in
            pixelCount += 1
        })

        // WHEN
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")
        sut.firePageContextUpdatedOnNavigation(url: "https://different.com")

        // THEN
        #expect(pixelCount == 2)
    }

    // MARK: - Page Context Removal Pixels

    @Test("Page context removed native pixel fires correctly")
    func testPageContextRemovedNativePixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextRemovedNative()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextRemovedNative.name)
    }

    @Test("Page context removed frontend pixel fires correctly")
    func testPageContextRemovedFrontendPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextRemovedFrontend()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextRemovedFrontend.name)
    }

    // MARK: - Prompt Submission Pixels

    private static func returningUserFeatureDiscovery() -> MockFeatureDiscovery {
        let featureDiscovery = MockFeatureDiscovery()
        featureDiscovery.setReturnValue(true, for: .duckAIPrompt)
        return featureDiscovery
    }

    @Test("Prompt submitted with context pixel fires correctly")
    func testPromptSubmittedWithContextPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        }, featureDiscovery: Self.returningUserFeatureDiscovery())

        // WHEN
        sut.firePromptSubmittedWithContext()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPromptSubmittedWithContextNative.name)
    }

    @Test("Prompt submitted without context pixel fires correctly")
    func testPromptSubmittedWithoutContextPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        }, featureDiscovery: Self.returningUserFeatureDiscovery())

        // WHEN
        sut.firePromptSubmittedWithoutContext()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPromptSubmittedWithoutContextNative.name)
    }

    @Test("First prompt on a new install carries first_prompt_new_install and marks the flag")
    func testFirstEverPromptSubmissionCarriesFirstPromptParam() {
        // GIVEN
        var firedEventName: String?
        var firedParameters: [String: String]?
        let featureDiscovery = MockFeatureDiscovery()
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { event, parameters in
                firedEventName = event.name
                firedParameters = parameters
            },
            featureDiscovery: featureDiscovery)

        // WHEN
        sut.firePromptSubmittedWithContext()

        // THEN
        #expect(firedEventName == Pixel.Event.aiChatContextualPromptSubmittedWithContextNative.name)
        #expect(firedParameters == ["first_prompt_new_install": "true"])
        #expect(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }

    @Test("Returning-user prompt submission omits first_prompt_new_install")
    func testReturningUserPromptSubmissionOmitsFirstPromptParam() {
        // GIVEN
        var firedParameters: [String: String]?
        var firedEventName: String?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { event in firedEventName = event.name },
            firePixelWithParameters: { _, parameters in firedParameters = parameters },
            featureDiscovery: Self.returningUserFeatureDiscovery())

        // WHEN
        sut.firePromptSubmittedWithoutContext()

        // THEN
        #expect(firedEventName == Pixel.Event.aiChatContextualPromptSubmittedWithoutContextNative.name)
        #expect(firedParameters == nil)
    }

    // MARK: - Manual Attach State Management

    @Test("Manual attach state begins correctly")
    func testBeginManualAttach() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        sut.beginManualAttach()

        // THEN
        #expect(sut.isManualAttachInProgress == true)
    }

    @Test("Manual attach state ends correctly")
    func testEndManualAttach() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        sut.beginManualAttach()
        sut.endManualAttach()

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    @Test("Manual attach state is initially false")
    func testManualAttachStateInitiallyFalse() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    // MARK: - Reset Functionality

    @Test("Reset clears navigation URL")
    func testResetClearsNavigationURL() {
        // GIVEN
        var pixelCount = 0
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in
            pixelCount += 1
        })

        // WHEN
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")
        sut.reset()
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")

        // THEN
        #expect(pixelCount == 2)
    }

    @Test("Reset clears manual attach state")
    func testResetClearsManualAttachState() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        sut.beginManualAttach()
        sut.reset()

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    // MARK: - Thread Safety Tests

    @Test("Concurrent access to manual attach state is thread-safe")
    func testConcurrentManualAttachAccess() async {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    sut.beginManualAttach()
                    _ = sut.isManualAttachInProgress
                    sut.endManualAttach()
                }
            }
        }

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Prompt submitted with selections carries a bucketed count", .timeLimit(.minutes(1)), arguments: [
        (1, "1"),
        (2, "2"),
        (3, "3-5"),
        (4, "3-5"),
        (5, "3-5")
    ])
    func prompt_submitted_with_selections_carries_bucketed_count(count: Int, expectedBucket: String) {
        var firedEventName: String?
        var firedParameters: [String: String]?
        var firedFrequency: PixelKit.Frequency?
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { _, _ in },
            fireSelectionPixel: { event, frequency in
                firedEventName = event.name
                firedParameters = event.parameters
                firedFrequency = frequency
            })

        sut.firePromptSubmittedWithSelections(count: count)

        #expect(firedEventName == AIChatContextualSelectionPixel.promptSubmitted(selectionCount: expectedBucket).name)
        #expect(firedParameters == ["selection_count": expectedBucket])
        #expect(firedFrequency == .dailyAndCount)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Prompt submitted with selections drops out-of-contract counts", .timeLimit(.minutes(1)), arguments: [0, 6])
    func prompt_submitted_with_selections_drops_out_of_contract_counts(count: Int) {
        var didFire = false
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            firePixelWithParameters: { _, _ in },
            fireSelectionPixel: { _, _ in didFire = true }
        )

        sut.firePromptSubmittedWithSelections(count: count)

        #expect(!didFire)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parameterless selection pixels fire under their own names", .timeLimit(.minutes(1)))
    func parameterless_selection_pixels_fire_under_their_own_names() {
        var firedEventNames: [String] = []
        let sut = AIChatContextualModePixelHandler(
            firePixel: { _ in },
            fireSelectionPixel: { event, frequency in
                #expect(frequency == .dailyAndCount)
                firedEventNames.append(event.name)
            }
        )

        sut.fireSelectionAttached()
        sut.fireSelectionLimitReached()
        sut.fireSelectionRemoved()
        sut.fireSelectionToolDeliveryTimedOut()

        #expect(firedEventNames == [
            AIChatContextualSelectionPixel.attached.name,
            AIChatContextualSelectionPixel.limitReached.name,
            AIChatContextualSelectionPixel.removed.name,
            AIChatContextualSelectionPixel.toolDeliveryTimedOut.name
        ])
        #expect(AIChatContextualSelectionPixel.attached.namePrefix == .none)
    }

    @Test("Concurrent reset and navigation calls are thread-safe")
    func testConcurrentResetAndNavigation() async {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 2 == 0 {
                        sut.reset()
                    } else {
                        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")
                    }
                }
            }
        }

        // THEN - Should complete without crashing
        #expect(true)
    }
}
