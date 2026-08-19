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
import CoreData
import FeatureFlags_iOS
import Onboarding
import Persistence
import RemoteMessaging
import RemoteMessagingTestsUtils
import SubscriptionTestingUtilities
import Suggestions
import SwiftUI
import UIKit
import XCTest
@testable import Core
@testable import DuckDuckGo

@MainActor
final class UnifiedInputContentContainerViewControllerTests: XCTestCase {

    func testWhenConstructingEmbeddedNTPThenMessagesRefreshOnceWithAuthoritativeOpenedAfterIdle() async {
        let environment = makeEnvironment(hasFavorites: true, openedAfterIdle: true)

        XCTAssertEqual(environment.messagesConfiguration.refreshCallCount, 0)

        environment.viewController.setEscapeHatch(makeEscapeHatch())
        environment.viewController.loadViewIfNeeded()
        environment.viewController.setActive(true)
        await settleUI()

        XCTAssertEqual(environment.messagesConfiguration.refreshCallCount, 1)
        XCTAssertEqual(environment.messagesConfiguration.lastRefreshOpenedAfterIdle, true)
    }

    func testWhenOnlyMessageContentExistsThenExactlyOnePinnedHatchIsPresented() async {
        for floatingUIEnabled in [false, true] {
            let environment = makeEnvironment(hasFavorites: false,
                                              homeMessages: [.placeholder],
                                              floatingUIEnabled: floatingUIEnabled)

            await activate(environment)

            XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [.pinned])
        }
    }

    func testWhenFirstAndLastFavoriteChangeThenHatchMovesBetweenOwnersWithoutDuplicating() async {
        for floatingUIEnabled in [false, true] {
            let environment = makeEnvironment(hasFavorites: true, floatingUIEnabled: floatingUIEnabled)
            await activate(environment)

            XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [.embedded])

            environment.favorites.favorites = []
            environment.favoritesUpdates.send()
            await settleUI()

            XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [.pinned])

            environment.favorites.favorites = [makeFavorite(in: environment.context)]
            environment.favoritesUpdates.send()
            await settleUI()

            XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [.embedded])
        }
    }

    func testWhenTypingOrUsingFireTabThenNoHatchIsPresented() async {
        let environment = makeEnvironment(hasFavorites: true)
        await activate(environment)

        environment.switchBarHandler.updateCurrentText("query")
        await settleUI()

        XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [])

        environment.switchBarHandler.clearText()
        environment.switchBarHandler.isFireTab = true
        environment.viewController.refreshFireMode(fireMode: true)
        await settleUI()

        XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [])
    }

    func testWhenDuckAIIsIdleThenHatchIsPinned() async {
        let environment = makeEnvironment(hasFavorites: true)
        await activate(environment)

        environment.viewController.setInputMode(.aiChat, animated: false)
        await settleUI()

        XCTAssertEqual(escapeHatchOwners(in: environment.viewController), [.pinned])
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

    private func makeEnvironment(hasFavorites: Bool,
                                 homeMessages: [HomeMessage] = [],
                                 floatingUIEnabled: Bool = false,
                                 openedAfterIdle: Bool = false) -> TestEnvironment {
        let favorites = MockFavoritesListInteracting()
        let favoritesUpdates = PassthroughSubject<Void, Never>()
        favorites.localUpdates = favoritesUpdates.eraseToAnyPublisher()

        let database = CoreDataDatabase.bookmarksMock
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BookmarkUtils.prepareFoldersStructure(in: context)
        if hasFavorites {
            favorites.favorites = [makeFavorite(in: context)]
        }

        let switchBarHandler = MockUnifiedInputSwitchBarHandler()
        let appSettings = AppSettingsMock()
        let enabledFlags: [FeatureFlag] = floatingUIEnabled ? [.floatingUIAugust2026] : []
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: enabledFlags)
        let messagesConfiguration = TestHomePageMessagesConfiguration(homeMessages: homeMessages)
        let tabsModel = TabsModel(desktop: false)
        tabsModel.currentTab?.openedAfterIdle = openedAfterIdle
        let newTabPageDependencies = SuggestionTrayViewController.NewTabPageDependencies(
            favoritesModel: favorites,
            homePageMessagesConfiguration: messagesConfiguration,
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
            bookmarksDatabase: database,
            historyManager: MockHistoryManager(),
            tabsModelProvider: { tabsModel },
            featureFlagger: featureFlagger,
            appSettings: appSettings,
            aiChatSettings: MockAIChatSettingsProvider(),
            featureDiscovery: DefaultFeatureDiscovery(),
            newTabPageDependencies: newTabPageDependencies,
            productSurfaceTelemetry: MockProductSurfaceTelemetry())
        let viewController = UnifiedInputContentContainerViewController(
            switchBarHandler: switchBarHandler,
            appSettings: appSettings,
            featureFlagger: featureFlagger,
            aiChatSettings: MockAIChatSettingsProvider())
        viewController.suggestionTrayDependencies = dependencies

        return TestEnvironment(viewController: viewController,
                               switchBarHandler: switchBarHandler,
                               favorites: favorites,
                               favoritesUpdates: favoritesUpdates,
                               context: context,
                               messagesConfiguration: messagesConfiguration)
    }

    private func activate(_ environment: TestEnvironment) async {
        environment.viewController.loadViewIfNeeded()
        environment.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        environment.viewController.setActive(true)
        environment.viewController.setEscapeHatch(makeEscapeHatch())
        await settleUI()
    }

    private func settleUI() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func makeFavorite(in context: NSManagedObjectContext) -> BookmarkEntity {
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            fatalError("Missing bookmarks root folder")
        }
        return BookmarkEntity.makeBookmark(title: UUID().uuidString,
                                           url: "https://example.com/\(UUID().uuidString)",
                                           parent: root,
                                           context: context)
    }

    private func makeEscapeHatch() -> EscapeHatchModel {
        let tab = DuckDuckGo.Tab()
        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        return .preview(title: "Return to Example",
                        subtitle: "example.com",
                        tabType: .regular,
                        domain: "example.com",
                        targetTab: tab,
                        tabCount: 2,
                        keyValueStore: userDefaults)
    }

    private func escapeHatchOwners(in viewController: UnifiedInputContentContainerViewController) -> [EscapeHatchOwner] {
        let descendants = descendantViewControllers(of: viewController)
        var owners: [EscapeHatchOwner] = []
        if descendants
            .compactMap({ $0 as? UIHostingController<FocusedChromeView> })
            .contains(where: { $0.rootView.hatchModel != nil }) {
            owners.append(.pinned)
        }
        if viewController.isShowingEmbeddedEscapeHatch {
            owners.append(.embedded)
        }
        return owners
    }

    private func descendantViewControllers(of viewController: UIViewController) -> [UIViewController] {
        viewController.children.flatMap { [$0] + descendantViewControllers(of: $0) }
    }
}

private struct TestEnvironment {
    let viewController: UnifiedInputContentContainerViewController
    let switchBarHandler: MockUnifiedInputSwitchBarHandler
    let favorites: MockFavoritesListInteracting
    let favoritesUpdates: PassthroughSubject<Void, Never>
    let context: NSManagedObjectContext
    let messagesConfiguration: TestHomePageMessagesConfiguration
}

private enum EscapeHatchOwner: Equatable {
    case pinned
    case embedded
}

private final class TestHomePageMessagesConfiguration: HomePageMessagesConfiguration {
    let homeMessages: [HomeMessage]
    private(set) var refreshCallCount = 0
    private(set) var lastRefreshOpenedAfterIdle: Bool?

    init(homeMessages: [HomeMessage]) {
        self.homeMessages = homeMessages
    }

    func refresh(openedAfterIdle: Bool) {
        refreshCallCount += 1
        lastRefreshOpenedAfterIdle = openedAfterIdle
    }
    func dismissHomeMessage(_ homeMessage: HomeMessage) async {}
    func didAppear(_ homeMessage: HomeMessage) {}
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
    var currentText: String = "" {
        didSet { currentTextSubject.send(currentText) }
    }
    var currentToggleState: TextEntryMode = .search {
        didSet { toggleStateSubject.send(currentToggleState) }
    }
    var isVoiceSearchEnabled = false
    var isAIVoiceChatEnabled = false
    var hasUserInteractedWithText = false {
        didSet { hasUserInteractedWithTextSubject.send(hasUserInteractedWithText) }
    }
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

    private let currentTextSubject = CurrentValueSubject<String, Never>("")
    private let toggleStateSubject = CurrentValueSubject<TextEntryMode, Never>(.search)
    private let hasUserInteractedWithTextSubject = CurrentValueSubject<Bool, Never>(false)

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { currentTextSubject.eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { toggleStateSubject.eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { hasUserInteractedWithTextSubject.eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }

    func updateCurrentText(_ text: String) { currentText = text }
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) { currentToggleState = state }
    func clearText() { currentText = "" }
    func microphoneButtonTapped() {}
    func markUserInteraction() { hasUserInteractedWithText = true }
    func clearButtonTapped() {}
    func updateBarPosition(isTop: Bool) {}
}
