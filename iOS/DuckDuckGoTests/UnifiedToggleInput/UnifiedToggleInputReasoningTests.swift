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
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
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
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
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
        sut.modelStore.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
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
        supportedReasoningEffort: [AIChatReasoningEffort]
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: provider,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort
        )
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
