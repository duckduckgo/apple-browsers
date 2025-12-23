//
//  WhatsNewModalPromptProviderTests.swift
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

import UIKit
import Foundation
import Testing
import RemoteMessaging
import RemoteMessagingTestsUtils
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - What's New Coordinator")
final class WhatsNewCoordinatorTests {

    @Test("Check Modal Is Provided When Scheduled Message Exists")
    func whenScheduledMessageExistsThenModalConfigurationIsReturned() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration != nil)
        #expect(mockRepository.didCallFetchScheduledMessage)
        #expect(!mockRepository.didCallFetchLastShownMessage)
    }

    @Test(
        "Check View Controller Sets Page Sheet Presentation Style On iPhone",
        arguments: [.scheduled, .onDemand] as [WhatsNewCoordinator.DisplayContext]
    )
    func whenIsIPadFalseThenViewControllerUsesPageSheetPresentationStyle(displayContext: WhatsNewCoordinator.DisplayContext) {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: displayContext,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == .pageSheet)
        #expect(configuration?.viewController.modalTransitionStyle == .coverVertical)
        #expect(configuration?.animated == true)
        #expect(configuration?.viewController is WhatsNewViewController)
    }

    @Test(
        "Check View Controller Sets Form Sheet Presentation Style On iPad",
        arguments: [.scheduled, .onDemand] as [WhatsNewCoordinator.DisplayContext]
    )
    func whenIsIPadTrueThenViewControllerUsesFormSheetPresentationStyle(displayContext: WhatsNewCoordinator.DisplayContext) {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: displayContext,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: true,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == .formSheet)
        #expect(configuration?.viewController.modalTransitionStyle == .coverVertical)
        #expect(configuration?.animated == true)
        #expect(configuration?.viewController is WhatsNewViewController)
    }

    @Test("Check No Modal Is Provided When No Scheduled Message")
    func whenNoScheduledMessageThenNilIsReturned() {
        // GIVEN
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: nil)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration == nil)
        #expect(mockRepository.didCallFetchScheduledMessage)
        #expect(!mockRepository.didCallFetchLastShownMessage)
    }

    @Test(
        "Check No Modal Is Provided When Message Has Wrong Content Type",
        arguments: [.scheduled, .onDemand] as [WhatsNewCoordinator.DisplayContext]
    )
    func whenMessageIsNotCardsListThenNilIsReturned(displayContext: WhatsNewCoordinator.DisplayContext) {
        // GIVEN
        let message = RemoteMessageModel(
            id: "test-message-id",
            surfaces: .modal,
            content: .small(titleText: "Title", descriptionText: "Description"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: displayContext,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration == nil)
    }

    @Test("Check Message Is Marked As Shown When Modal Is Presented")
    func whenModalIsPresentedThenUpdateRemoteMessageWithCorrectIdIsCalled() async {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "specific-message-id")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        coordinator.didPresentModal()

        // THEN - verify the correct message ID was used
        // Yield to let the unstructured Task execute (mock is sync, completes instantly)
        await Task.yield()
        #expect(mockRepository.didCallMarkMessageShown)
    }

}

@MainActor
@Suite("Modal Prompt Coordination - What's New Coordinator Action Handling")
struct WhatsNewCoordinatorActionHandlingTests {

    @Test(
        "Check Present Embedded Web View Pushes View Controller",
        arguments: [.scheduled, .onDemand] as [WhatsNewCoordinator.DisplayContext]
    )
    func whenPresentEmbeddedWebViewThenViewControllerIsPushed(_ context: WhatsNewCoordinator.DisplayContext) async throws {
        // GIVEN
        let testURL = URL(string: "https://example.com/help")!
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        let configuration = try #require(coordinator.provideModalPrompt())
        let navController = try #require(configuration.viewController as? WhatsNewViewController)

        // WHEN
        await coordinator.presentEmbeddedWebView(url: testURL)

        // THEN
        let lastViewController = try #require(navController.viewControllers.last as? EmbeddedWebViewController)
        #expect(navController.viewControllers.count == 2)
        #expect(lastViewController.url == testURL)
    }

    @Test(
        "Check Handle Action Always Passes Within Current Context Presentation Style",
        arguments: [
            .share(value: "Test Value", title: "Test Title"),
            .url(value: "https://example.com"),
            .urlInContext(value: "https://example.com"),
            .survey(value: "Test"),
            .navigation(value: .duckAISettings),
            .appStore,
            .dismiss
        ] as [RemoteAction],
        [
            .scheduled,
            .onDemand
        ] as [WhatsNewCoordinator.DisplayContext]
    )
    func handleActionAlwaysPassesWithinCurrentContextPresentationStyle(action: RemoteAction, displayContext: WhatsNewCoordinator.DisplayContext) async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()

        let coordinator = WhatsNewCoordinator(
            displayContext: displayContext,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: MockRemoteMessagingPixelReporter(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        await coordinator.handleAction(action)

        // THEN
        #expect(mockHandler.didCallHandleAction)
        #expect(mockHandler.capturedPresentationContext?.presentationStyle == .withinCurrentContext)
        #expect(mockHandler.capturedPresentationContext?.presenter != nil)
    }

}

@MainActor
@Suite("Modal Prompt Coordination - What's New Coordinator Pixel")
struct WhatsNewCoordinatorPixelTrackingTests {

    // MARK: - Message Appeared Pixels

    @Test("Check Message Appeared Pixel Fires When Message Appears")
    func whenMessageAppearsCallbackInvokedThenMessageAppearedPixelFires() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        mockMapper.capturedOnMessageAppear?()

        // THEN
        #expect(mockPixelReporter.didCallMeasureRemoteMessageAppeared)
        #expect(mockPixelReporter.capturedAppearedMessage?.id == "test-message")
    }

    @Test("Check Has Already Seen Message Is Passed Correctly For First Time")
    func whenMessageShownForFirstTimeThenHasAlreadySeenMessageIsFalse() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        mockMapper.capturedOnMessageAppear?()

        // THEN
        #expect(mockPixelReporter.capturedHasAlreadySeenMessage == false)
    }

    @Test("Check Has Already Seen Message Is Passed Correctly For Subsequent Times")
    func whenMessageShownAgainThenHasAlreadySeenMessageIsTrue() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message, hasShownMessage: true)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        mockMapper.capturedOnMessageAppear?()

        // THEN
        #expect(mockPixelReporter.capturedHasAlreadySeenMessage == true)
    }

    // MARK: - Primary Action

    @Test("Check Primary Action Dismiss Callback Fires Primary Action Clicked Pixel")
    func whenPrimaryActionDismissCallbackInvokedThenPrimaryActionClickedPixelFires() async {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        // WHEN - called after primary action completes
        await mockMapper.capturedOnPrimaryAction?(.dismiss)

        // THEN
        #expect(mockPixelReporter.didCallMeasureRemoteMessagePrimaryActionClicked)
        #expect(mockPixelReporter.capturedPrimaryActionClickedMessage?.id == "test-message")
    }

    // MARK: - Card Pixel Tests

    @Test("Check Item Appear Callback Fires Card Shown Pixel")
    func whenItemAppearsCallbackInvokedThenCardShownPixelFires() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        mockMapper.capturedOnItemAppear?("card-123")

        // THEN
        #expect(mockPixelReporter.didCallMeasureRemoteMessageCardShown)
        #expect(mockPixelReporter.capturedCardShownMessage?.id == "test-message")
        #expect(mockPixelReporter.capturedCardShownCardId == "card-123")
    }

    @Test("Check Item Action Callback Fires Card Clicked Pixel")
    func whenItemActionCallbackInvokedThenCardClickedPixelFiresAndActionHandled() async {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        let testAction = RemoteAction.urlInContext(value: "https://example.com")

        // WHEN
        await mockMapper.capturedOnItemAction?(testAction, "card-123")

        // THEN - Verify pixel fired
        #expect(mockPixelReporter.didCallMeasureRemoteMessageCardClicked)
        #expect(mockPixelReporter.capturedCardClickedMessage?.id == "test-message")
        #expect(mockPixelReporter.capturedCardClickedCardId == "card-123")
    }

    // MARK: - Dismiss Pixel Tests

    @Test("Check Primary Action Dismiss Callback Fires Dismiss Pixel with Primary Action Type")
    func whenPrimaryActionCallbackInvokedThenDismissPixelFiresWithPrimaryActionType() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()
        let mockMapper = MockWhatsNewDisplayModelMapper()
        mockMapper.displayModelToReturn = .mock

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            displayModelMapper: mockMapper
        )
        _ = coordinator.provideModalPrompt()

        // WHEN - called after primary action completes
        mockMapper.capturedOnDismiss?()

        // THEN
        #expect(mockPixelReporter.didCallMeasureRemoteMessageDismissed)
        #expect(mockPixelReporter.capturedDismissedMessage?.id == "test-message")
        #expect(mockPixelReporter.capturedDismissType == .primaryAction)
    }

    @Test("Check Pull Down Gesture Fires Dismiss Pixel With Pull Down Type")
    func whenModalPulledDownThenDismissPixelFiresWithPullDownType() throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let mockPixelReporter = MockRemoteMessagingPixelReporter()

        let coordinator = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: mockPixelReporter,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )
        let configuration = try #require(coordinator.provideModalPrompt())

        // WHEN - Simulate pull down gesture via presentation controller delegate
        coordinator.presentationControllerDidDismiss(configuration.viewController.presentationController!)

        // THEN
        #expect(mockPixelReporter.didCallMeasureRemoteMessageDismissed)
        #expect(mockPixelReporter.capturedDismissedMessage?.id == "test-message")
        #expect(mockPixelReporter.capturedDismissType == .pullDown)
    }

}

@MainActor
@Suite("Modal Prompt Coordination - What's New Coordinator - On-Demand Display Context")
final class WhatsNewCoordinatorOnDemandTests {

    @Test("Check Provide Modal Prompt Fetches From Last Shown Message For onDemand Context")
    func whenOnDemandContextThenFetchesFromLastShownMessage() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "last-shown-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: nil,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration != nil)
        #expect(mockRepository.didCallFetchLastShownMessage)
        #expect(!mockRepository.didCallFetchScheduledMessage)
    }

    @Test("Check Provide Modal Prompt Returns Nil When No Last Shown Message Message Exists")
    func whenOnDemandContextAndNoLastShownMessageThenReturnsNil() {
        // GIVEN
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: nil)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: nil,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration == nil)
        #expect(mockRepository.didCallFetchLastShownMessage)
        #expect(!mockRepository.didCallFetchScheduledMessage)
    }

    @Test("Check Provide Modal Prompt Returns Configuration When Last Shown Message Exists")
    func whenOnDemandContextAndLastShownMessageExistsThenReturnsConfiguration() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "stored-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: nil,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration != nil)
        #expect(configuration?.viewController is WhatsNewViewController)
        #expect(mockRepository.didCallFetchLastShownMessage)
    }

    @Test("Check Message Is Not Marked As Shown For onDemand Context")
    func whenOnDemandContextThenDidPresentModalDoesNotMarkAsShown() async {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "on-demand-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: nil,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        coordinator.didPresentModal()

        // THEN - Yield to ensure Task would execute if scheduled
        await Task.yield()
        #expect(!mockRepository.didCallMarkMessageShown)
    }

}

@MainActor
@Suite("Modal Prompt Coordination - What's New Coordinator - OnDemandModalPromptProvider Protocol")
final class WhatsNewCoordinatorOnDemandProtocolTests {

    @Test("Check Can Show Prompt On Demand Returns True When Fetch Last Shown Message Returns Message")
    func whenLastShownMessageExistsThenCanShowPromptOnDemandIsTrue() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "available-message")
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: nil,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let canShow = coordinator.canShowPromptOnDemand

        // THEN
        #expect(canShow == true)
        #expect(mockRepository.didCallFetchLastShownMessage)
    }

    @Test("Check Can Show Prompt On Demand Returns False When Fetch Last Shown Message Returns Nil")
    func whenNoLastShownMessageThenCanShowPromptOnDemandIsFalse() {
        // GIVEN
        let mockRepository = MockWhatsNewMessageRepository(scheduledRemoteMessage: nil)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: mockRepository,
            remoteMessageActionHandler: mockHandler,
            isIPad: false,
            pixelReporter: nil,
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock()
        )

        // WHEN
        let canShow = coordinator.canShowPromptOnDemand

        // THEN
        #expect(canShow == false)
        #expect(mockRepository.didCallFetchLastShownMessage)
    }

}

private extension RemoteMessagingUI.CardsListDisplayModel {

    static let mock = RemoteMessagingUI.CardsListDisplayModel(
        screenTitle: "Test",
        icon: nil,
        items: [],
        onAppear: {},
        primaryAction: (title: "OK", action: {})
    )

}
