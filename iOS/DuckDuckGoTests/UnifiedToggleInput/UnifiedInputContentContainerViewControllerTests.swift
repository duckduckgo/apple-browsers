//
//  UnifiedInputContentContainerViewControllerTests.swift
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
import Bookmarks
import BrowserServicesKit
import Combine
import Common
import Core
import FeatureFlags_iOS
import Onboarding
import Persistence
import RemoteMessaging
import Suggestions
import SubscriptionTestingUtilities
import SwiftUI
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedInputContentContainerViewControllerTests: XCTestCase {

    func testWhenResolvingEscapeHatchPlacementThenUsesCurrentInputs() {
        typealias Placement = UnifiedInputContentContainerViewController.EscapeHatchPlacement
        let cases: [(String, Bool, Bool, Bool, TextEntryMode, Bool, Placement)] = [
            ("no hatch", false, false, false, .search, true, .none),
            ("Fire Tab", true, true, false, .search, true, .none),
            ("typing", true, false, true, .search, true, .none),
            ("idle Search with favorites", true, false, false, .search, true, .embedded),
            ("idle Search without favorites", true, false, false, .search, false, .pinned),
            ("message-only Search", true, false, false, .search, false, .pinned),
            ("idle Duck.ai", true, false, false, .aiChat, true, .pinned)
        ]

        for (name, hasEscapeHatch, isFireTab, isTyping, inputMode, hasFavorites, expected) in cases {
            let result = Placement.resolve(hasEscapeHatch: hasEscapeHatch,
                                           isFireTab: isFireTab,
                                           isTyping: isTyping,
                                           inputMode: inputMode,
                                           hasFavorites: hasFavorites)
            XCTAssertEqual(result, expected, name)
        }
    }

    func testWhenRefreshingFireModeThenPinnedHatchLayoutReconcilesImmediately() throws {
        let switchBarHandler = MockUnifiedInputSwitchBarHandler()
        let viewController = makeLayoutTestSubject(switchBarHandler: switchBarHandler)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.setActive(true)
        viewController.setEscapeHatch(makeEscapeHatch())
        viewController.view.layoutIfNeeded()

        let chromeController = try XCTUnwrap(viewController.children.compactMap { $0 as? UIHostingController<FocusedChromeView> }.first)
        let suggestionsController = try XCTUnwrap(viewController.children.compactMap { $0 as? UIHostingController<UnifiedSuggestionsView> }.first)
        let initialChromeHeight = chromeController.view.bounds.height
        let initialHostTopInset = suggestionsController.additionalSafeAreaInsets.top

        XCTAssertNotNil(chromeController.rootView.hatchModel)
        XCTAssertGreaterThan(initialChromeHeight, 0)
        XCTAssertEqual(initialHostTopInset, initialChromeHeight, accuracy: 0.001)

        switchBarHandler.isFireTab = true
        viewController.refreshFireMode(fireMode: true)
        viewController.view.layoutIfNeeded()

        XCTAssertNil(chromeController.rootView.hatchModel)
        XCTAssertEqual(chromeController.view.bounds.height, 0, accuracy: 0.001)
        XCTAssertEqual(suggestionsController.additionalSafeAreaInsets.top, 0, accuracy: 0.001)

        switchBarHandler.isFireTab = false
        viewController.refreshFireMode(fireMode: false)
        viewController.view.layoutIfNeeded()

        XCTAssertNotNil(chromeController.rootView.hatchModel)
        XCTAssertEqual(chromeController.view.bounds.height, initialChromeHeight, accuracy: 0.001)
        XCTAssertEqual(suggestionsController.additionalSafeAreaInsets.top, initialHostTopInset, accuracy: 0.001)
    }

    func testDuckAISuggestionsDidRequestSyncSetup_RequestsSyncSetupOnDelegate() {
        let delegate = MockUnifiedInputContentContainerDelegate()
        let viewController = UnifiedInputContentContainerViewController(
            switchBarHandler: MockUnifiedInputSwitchBarHandler()
        )
        viewController.delegate = delegate

        viewController.duckAISuggestionsDidRequestSyncSetup()

        XCTAssertEqual(delegate.syncSetupRequestCount, 1)
    }

    private func makeLayoutTestSubject(switchBarHandler: MockUnifiedInputSwitchBarHandler) -> UnifiedInputContentContainerViewController {
        let favorites = MockFavoritesListInteracting()
        let appSettings = AppSettingsMock()
        let featureFlagger = MockFeatureFlagger()
        let aiChatSettings = MockAIChatSettingsProvider()
        let tabsModel = TabsModel(desktop: false)
        let newTabPageDependencies = SuggestionTrayViewController.NewTabPageDependencies(
            favoritesModel: favorites,
            homePageMessagesConfiguration: HomePageMessagesConfigurationMock(homeMessages: []),
            subscriptionDataReporting: nil,
            newTabDialogFactory: TestNewTabDaxDialogFactory(),
            newTabDaxDialogManager: MockDaxDialogsManager(),
            onboardingFlowProvider: TestOnboardingFlowProvider(),
            faviconLoader: EmptyFaviconLoading(),
            faviconsCache: TestFavoritesFaviconCache(),
            remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
            remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
            remoteMessagingPixelReporter: nil,
            appSettings: appSettings,
            subscriptionManager: SubscriptionManagerMock(),
            internalUserCommands: TestURLBasedDebugCommands())
        let dependencies = SuggestionTrayDependencies(
            favoritesViewModel: favorites,
            bookmarksDatabase: .bookmarksMock,
            historyManager: MockHistoryManager(),
            tabsModelProvider: { tabsModel },
            featureFlagger: featureFlagger,
            appSettings: appSettings,
            aiChatSettings: aiChatSettings,
            featureDiscovery: DefaultFeatureDiscovery(),
            newTabPageDependencies: newTabPageDependencies,
            productSurfaceTelemetry: MockProductSurfaceTelemetry())
        let viewController = UnifiedInputContentContainerViewController(
            switchBarHandler: switchBarHandler,
            appSettings: appSettings,
            featureFlagger: featureFlagger,
            aiChatSettings: aiChatSettings)
        viewController.suggestionTrayDependencies = dependencies
        return viewController
    }

    private func makeEscapeHatch() -> EscapeHatchModel {
        .preview(title: "Return to Example",
                 subtitle: "example.com",
                 tabType: .regular,
                 domain: "example.com",
                 targetTab: Tab(),
                 tabCount: 2)
    }
}

private struct TestNewTabDaxDialogFactory: NewTabDaxDialogProviding {
    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec,
                         onCompletion: @escaping (_ activateSearch: Bool) -> Void,
                         onManualDismiss: @escaping () -> Void) -> some View {
        EmptyView()
    }

    func createDuckAIFireOnboardingCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func createEndOfJourneyDialog(content: OnboardingEndOfJourneyContent,
                                  onAction: @escaping (OnboardingEndOfJourneyAction) -> Void) -> AnyView {
        AnyView(EmptyView())
    }
}

private struct TestOnboardingFlowProvider: OnboardingFlowProviding {
    let currentOnboardingFlow: OnboardingFlowType = .default
}

private struct TestFavoritesFaviconCache: FavoritesFaviconCaching {
    func populateFavicon(for domain: String, intoCache: FaviconsCacheType, fromCache: FaviconsCacheType?) {}
}

private struct TestURLBasedDebugCommands: URLBasedDebugCommands {
    func handle(url: URL) -> Bool { false }
}

private final class MockUnifiedInputContentContainerDelegate: UnifiedInputContentContainerViewControllerDelegate {
    private(set) var syncSetupRequestCount = 0

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {}
    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {}
    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity) {}
    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity) {}
    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion) {}
    func unifiedInputEditingStateDidRequestTextUpdate(_ text: String) {}
    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {}
    func unifiedInputEditingStateDidSelectViewAllChats() {}
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: DuckDuckGo.Tab) {}
    func unifiedInputEditingStateDidRequestTabSwitcher() {}
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {}

    func unifiedInputEditingStateDidRequestSyncSetup() {
        syncSetupRequestCount += 1
    }
}

private final class MockUnifiedInputSwitchBarHandler: SwitchBarHandling {
    var currentText: String = ""
    var currentToggleState: TextEntryMode = .search
    var isVoiceSearchEnabled = false
    var isAIVoiceChatEnabled = false
    var hasUserInteractedWithText = false
    var isCurrentTextValidURL = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition = true
    var isToggleEnabled = true
    var isFireTab = false
    var isUsingExpandedBottomBarHeight = false
    var isUsingFadeOutAnimation = false
    var shouldDisableAutocorrectOnEmpty = false
    var hidesVoiceButton = false
    var hasSubmittedPrompt = false
    var modeParameters: [String: String] = [:]

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { Empty().eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }

    func updateCurrentText(_ text: String) {}
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) {}
    func clearText() {}
    func microphoneButtonTapped() {}
    func markUserInteraction() {}
    func clearButtonTapped() {}
    func updateBarPosition(isTop: Bool) {}
}
