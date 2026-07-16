//
//  UnifiedToggleInputReasoningTests.swift
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
import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputReasoningTests: XCTestCase {

    private var sut: UnifiedToggleInputCoordinator!
    private var mockDelegate: MockUnifiedToggleInputReasoningDelegate!
    private var mockPreferences: MockAIChatReasoningPreferences!

    override func setUp() {
        super.setUp()
        mockPreferences = MockAIChatReasoningPreferences()
        sut = UnifiedToggleInputCoordinator(host: .omnibar, isToggleEnabled: true, preferences: mockPreferences)
        mockDelegate = MockUnifiedToggleInputReasoningDelegate()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        sut = nil
        mockDelegate = nil
        mockPreferences = nil
        super.tearDown()
    }

    func testSubmitAIChatWithoutBoundScriptPassesResolvedReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-5.2"
        mockPreferences.selectedReasoningMode = .extendedReasoning
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertEqual(mockDelegate.submittedReasoningEffort, .medium)
    }

    func testUpdateSelectedModelWhenReasoningModelShowsReasoningButton() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.updateSelectedModel("gpt-5.2")

        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)
    }

    func testUpdateSelectedReasoningModeUpdatesVisibleReasoningMode() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.updateSelectedModel("gpt-5.2")
        sut.updateSelectedReasoningMode(.extendedReasoning)

        XCTAssertEqual(sut.viewController.selectedReasoningMode, .extendedReasoning)
    }

    func testReasoningPickerMenuOrdersModesFastReasoningExtended() {
        sut.viewController.cardPosition = .top
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.medium, .low, .none])]

        sut.updateSelectedModel("gpt-5.2")

        let actions = sut.viewController.reasoningPickerMenu?.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(actions?.map(\.title), ["Fast", "Reasoning", "Extended Reasoning"])
    }

    func testReasoningPickerMenuKeepsStaticOrderWhenBottomAnchored() {
        sut.viewController.cardPosition = .bottom
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.medium, .low, .none])]

        sut.updateSelectedModel("gpt-5.2")

        let actions = sut.viewController.reasoningPickerMenu?.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(actions?.map(\.title), ["Fast", "Reasoning", "Extended Reasoning"])
    }

    func testUpdateSelectedModelWhenOnlyOneReasoningModeHidesReasoningButton() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])]

        sut.updateSelectedModel("gpt-oss")

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden)
        XCTAssertNil(sut.viewController.reasoningPickerMenu)
    }

    func testUpdateSelectedModelWhenReasoningModeUnavailableClearsPersistedSelection() {
        mockPreferences.selectedReasoningMode = .extendedReasoning
        sut.modelStore.models = [makeReasoningModel(id: "claude-opus-4-6", provider: .anthropic, supportedReasoningEffort: [.none, .low])]

        sut.updateSelectedModel("claude-opus-4-6")

        XCTAssertNil(mockPreferences.selectedReasoningMode)
        XCTAssertEqual(sut.viewController.selectedReasoningMode, .fast)
        XCTAssertEqual(sut.persistedReasoningEffort, AIChatReasoningEffort.none)
    }

    func testUpdateSelectedModelWhenReasoningModeUnavailableDoesNotRestoreStaleMode() {
        mockPreferences.selectedReasoningMode = .extendedReasoning
        sut.modelStore.models = [
            makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "claude-opus-4-6", provider: .anthropic, supportedReasoningEffort: [.none, .low])
        ]

        sut.updateSelectedModel("claude-opus-4-6")

        XCTAssertNil(mockPreferences.selectedReasoningMode)
        XCTAssertEqual(sut.viewController.selectedReasoningMode, .fast)
        XCTAssertEqual(sut.persistedReasoningEffort, AIChatReasoningEffort.none)

        sut.updateSelectedModel("gpt-5.2")

        XCTAssertNil(mockPreferences.selectedReasoningMode)
        XCTAssertEqual(sut.viewController.selectedReasoningMode, .fast)
        XCTAssertEqual(sut.persistedReasoningEffort, AIChatReasoningEffort.none)
    }

    func testUpdateSelectedReasoningModeWhenModeUnavailableDoesNotPersistInvalidSelection() {
        mockPreferences.selectedReasoningMode = .fast
        sut.modelStore.models = [makeReasoningModel(id: "claude-opus-4-6", provider: .anthropic, supportedReasoningEffort: [.none, .low])]
        sut.updateSelectedModel("claude-opus-4-6")

        sut.updateSelectedReasoningMode(.extendedReasoning)

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .fast)
        XCTAssertEqual(sut.persistedReasoningEffort, AIChatReasoningEffort.none)
    }

    func testHandleReasoningModeSelectionWhenFreeUserSelectsGPT52ExtendedReasoningRoutesPurchaseWithoutChangingSelection() {
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]
        sut.updateSelectedModel("gpt-5.2")
        sut.updateSelectedReasoningMode(.reasoning)
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__reasoningpicker")
        }

        sut.handleReasoningModeSelection(.extendedReasoning)

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedReasoningMode, .reasoning)
    }

    func testHandleReasoningModeSelectionWhenPlusUserSelectsGPT52ExtendedReasoningRoutesUpgradeWithoutChangingSelection() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]
        sut.updateSelectedModel("gpt-5.2")
        sut.updateSelectedReasoningMode(.reasoning)
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__reasoningpicker")
        }

        sut.handleReasoningModeSelection(.extendedReasoning)

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedReasoningMode, .reasoning)
    }

    func testHandleReasoningModeSelectionWhenGatedReasoningBecomesAccessibleAfterSubscriptionRefresh_selectsPendingReasoningMode() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]
        sut.updateSelectedModel("gpt-5.2")
        sut.updateSelectedReasoningMode(.reasoning)
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow = deepLink else {
                return false
            }
            return true
        }

        sut.handleReasoningModeSelection(.extendedReasoning)
        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedReasoningMode, .reasoning)

        sut.modelStore.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        // After subscription change, /models is re-fetched and the per-effort gating
        // metadata reflects the new tier — replace the model in the store accordingly.
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumAccessibleForPro()
            )
        ]
        sut.modelStore.onModelsUpdated?()

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .extendedReasoning)
    }

    func testHandleReasoningModeSelectionWhenProUserSelectsGPT52ExtendedReasoningThenModeIsSelected() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
        sut.updateSelectedModel("gpt-5.2")

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .extendedReasoning)
    }

    func testHandleReasoningModeSelectionWhenGPT52NonExtendedReasoningThenModeIsSelected() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
        sut.updateSelectedModel("gpt-5.2")

        sut.handleReasoningModeSelection(.reasoning)

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .reasoning)
    }

    func testHandleReasoningModeSelectionWhenOtherModelExtendedReasoningThenModeIsSelected() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.1", supportedReasoningEffort: [.none, .low, .medium])]
        sut.updateSelectedModel("gpt-5.1")

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .extendedReasoning)
    }

    func testSubmitAIChatWhenOnlyOneReasoningModeAndNoSelectionOmitsReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-oss"
        sut.modelStore.models = [makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])]

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertNil(mockDelegate.submittedReasoningEffort)
    }

    func testSubmitAIChatWhenNoReasoningModeIsPersistedPassesDisplayedDefaultReasoningEffort() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low, .medium])]
        sut.updateSelectedModel("gpt-oss")

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertEqual(sut.viewController.selectedReasoningMode, .reasoning)
        XCTAssertEqual(mockDelegate.submittedReasoningEffort, .low)
    }

    func testSubmitAIChatWhenOnlyOneReasoningModeAndSelectionIsValidPassesReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-oss"
        mockPreferences.selectedReasoningMode = .reasoning
        sut.modelStore.models = [makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])]

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertEqual(mockDelegate.submittedReasoningEffort, .low)
    }

    func testSubmitAIChatAfterFirstPromptStillPassesReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-5.2"
        mockPreferences.selectedReasoningMode = .reasoning
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "first", mode: .aiChat)
        mockDelegate.submittedReasoningEffort = nil

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "second", mode: .aiChat)

        XCTAssertEqual(mockDelegate.submittedReasoningEffort, .low)
        XCTAssertNil(mockDelegate.submittedModelId)
    }

    func testPrepareExternalPromptSubmissionPassesResolvedReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-5.2"
        mockPreferences.selectedReasoningMode = .extendedReasoning
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        let submission = sut.prepareExternalPromptSubmission()

        XCTAssertEqual(submission.reasoningEffort, .medium)
    }

    func testVoicePromptSubmissionConfigurationOmitsReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-5.2"
        mockPreferences.selectedReasoningMode = .reasoning
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        let configuration = sut.voicePromptSubmissionConfiguration

        XCTAssertEqual(sut.persistedReasoningEffort, .low)
        XCTAssertEqual(configuration.modelId, "gpt-5.2")
        XCTAssertNil(configuration.reasoningEffort)
    }

    func testSubmitAIChatAfterChangingToFastPassesNoReasoningEffort() {
        mockPreferences.selectedModelId = "gpt-5.2"
        mockPreferences.selectedReasoningMode = .reasoning
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "first", mode: .aiChat)
        sut.updateSelectedReasoningMode(.fast)
        mockDelegate.submittedReasoningEffort = nil

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "second", mode: .aiChat)

        XCTAssertEqual(mockDelegate.submittedReasoningEffort, AIChatReasoningEffort.none)
    }

    // MARK: - reasoningEffortAccess

    /// `gpt-5.2` returns `supportedReasoningEffort: [none, low, medium]` but `reasoningEffortAccess`
    /// gates every effort behind a tier the current (Free) user doesn't have. With nothing
    /// accessible, the picker must be hidden — even though the model technically supports
    /// three modes (no `count > 1` fallback).
    func testWhenAllReasoningEffortsAreGated_ThenReasoningPickerIsHidden() {
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["pro", "internal"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["pro", "internal"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
                ]
            )
        ]

        sut.updateSelectedModel("gpt-5.2")

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden)
        XCTAssertNil(sut.viewController.reasoningPickerMenu)
    }

    /// In the "model accessible, every effort gated" case the BE must NOT receive a
    /// `reasoning_effort` value. Otherwise the BE would attempt to run a reasoning mode
    /// the user can't actually use.
    func testWhenAllReasoningEffortsAreGated_ThenReasoningEffortIsOmittedFromPayload() {
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["pro", "internal"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["pro", "internal"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
                ]
            )
        ]
        sut.updateSelectedModel("gpt-5.2")

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertNil(mockDelegate.submittedReasoningEffort)
        XCTAssertNil(sut.persistedReasoningEffort)
    }

    /// Previously persisted mode was `.extendedReasoning`, but on the new model `.medium`
    /// (the effort backing Extended Reasoning) is gated for the Plus user. Fallback must
    /// pick the first accessible effort (`.fast` → `.none`), not blindly keep the gated
    /// preference or default to `.fast` only when the mode is *unsupported*.
    func testWhenPersistedReasoningModeIsGated_ThenFallbackUsesFirstAccessibleMode() {
        mockPreferences.selectedReasoningMode = .extendedReasoning
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]

        sut.updateSelectedModel("gpt-5.2")

        XCTAssertFalse(sut.viewController.isReasoningButtonHidden, "Picker should still be visible — 2 of 3 modes accessible")
        XCTAssertEqual(sut.viewController.selectedReasoningMode, .fast, "Fallback should land on the first accessible mode")
        XCTAssertEqual(sut.persistedReasoningEffort, AIChatReasoningEffort.none, "Effort for .fast on this model is .none")
    }

    /// Hide-picker convergence.
    /// The two ways the picker can be hidden — model has no reasoning support at all
    /// (`supportedReasoningEffort: []`), and model has reasoning but every effort is
    /// gated for the user — must produce the same end state: button hidden, menu nil.
    func testHidePickerConvergence_NoReasoningSupportVsAllEffortsGated_ProduceSamePickerState() {
        sut.modelStore.models = [makeReasoningModel(id: "no-reasoning", supportedReasoningEffort: [])]
        sut.updateSelectedModel("no-reasoning")
        let noSupportButtonHidden = sut.viewController.isReasoningButtonHidden
        let noSupportMenuIsNil = sut.viewController.reasoningPickerMenu == nil

        sut.modelStore.models = [
            makeReasoningModel(
                id: "all-gated",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["pro"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["pro"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
                ]
            )
        ]
        sut.updateSelectedModel("all-gated")
        let allGatedButtonHidden = sut.viewController.isReasoningButtonHidden
        let allGatedMenuIsNil = sut.viewController.reasoningPickerMenu == nil

        XCTAssertTrue(noSupportButtonHidden)
        XCTAssertTrue(noSupportMenuIsNil)
        XCTAssertEqual(noSupportButtonHidden, allGatedButtonHidden)
        XCTAssertEqual(noSupportMenuIsNil, allGatedMenuIsNil)
    }

    /// Backwards compatibility — payloads that omit `reasoningEffortAccess` (today's BE,
    /// and any model the BE chooses not to gate per-effort) must still go through the
    /// "all efforts inherit model access" path. No regression for current users.
    func testWhenReasoningEffortAccessIsAbsent_ThenAllSupportedEffortsAreTreatedAsAccessible() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium], reasoningEffortAccess: nil)
        ]

        sut.updateSelectedModel("gpt-5.2")
        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .extendedReasoning, "Without per-effort metadata, mode is freely selectable")
        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)
    }

    func testHandleReasoningModeSelectionWhenSingleModeHasMixedGating_SelectsModeWithoutUpsell() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeReasoningModel(
                id: "future-model",
                supportedReasoningEffort: [.high, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .high, accessTier: ["pro", "internal"], entityHasAccess: false),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro", "internal"], entityHasAccess: true)
                ]
            )
        ]
        sut.updateSelectedModel("future-model")

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(mockPreferences.selectedReasoningMode, .extendedReasoning,
                       "Mode is reachable via accessible .medium — must be selected, not gated")
        XCTAssertEqual(sut.persistedReasoningEffort, AIChatReasoningEffort.medium,
                       "Payload must carry the accessible .medium effort, not the gated .high")
    }

    func testBindToExistingChatWhenReasoningModelKeepsReasoningButtonAvailable() {
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
        mockPreferences.selectedModelId = "gpt-5.2"

        sut.bindToTab(makeTestUserScript(), hasExistingChat: true)

        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)
    }
}

private extension UnifiedToggleInputReasoningTests {
    func hasQueryItem(in components: URLComponents?, name: String, value: String) -> Bool {
        components?.queryItems?.contains { $0.name == name && $0.value == value } == true
    }

    func makeReasoningModel(
        id: String,
        provider: AIChatModel.ModelProvider = .openAI,
        supportedReasoningEffort: [AIChatReasoningEffort],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: provider,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }

    /// `reasoningEffortAccess` shape that mirrors the production "GPT-5.2 + Plus" scenario:
    /// `none` and `low` are accessible to Plus/Pro/internal; `medium` is Pro/internal only.
    /// Used by tests that need to exercise per-effort gating via the API path (not hardcode).
    func gpt52MediumGatedForPlus() -> [AIChatReasoningEffortAccess] {
        [
            AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
        ]
    }

    /// As above, but `medium.entityHasAccess` is `true` — used after a subscription upgrade
    /// where the BE would re-issue per-effort metadata reflecting the new tier.
    func gpt52MediumAccessibleForPro() -> [AIChatReasoningEffortAccess] {
        [
            AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: true)
        ]
    }
}

@MainActor
private final class MockUnifiedToggleInputReasoningDelegate: UnifiedToggleInputDelegate {
    var submittedPrompt: String?
    var submittedModelId: String?
    var submittedReasoningEffort: AIChatReasoningEffort?
    var submittedImages: [AIChatNativePrompt.NativePromptImage]?
    var submittedFiles: [AIChatNativePrompt.NativePromptFile]?

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?) {
        submittedPrompt = prompt
        submittedModelId = modelId
        submittedReasoningEffort = reasoningEffort
        submittedImages = images
        submittedFiles = files
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {}
    func unifiedToggleInputDidRequestAIVoiceChat() {}
    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {}
    func unifiedToggleInputDidChangeHeight() {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {}
    func unifiedToggleInputDidRequestFire() {}
    func unifiedToggleInputDidRequestAppMenu() {}
}

private final class MockAIChatReasoningPreferences: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningEffort: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}
