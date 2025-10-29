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
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration != nil)
        #expect(mockStore.fetchScheduledRemoteMessageCalls == 1)
        #expect(mockStore.capturedSurfaces == .modal)
    }

    @Test("Check Modal Configuration Has Correct Properties")
    func whenModalIsProvidedThenConfigurationHasCorrectProperties() {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration?.presentationStyle == .pageSheet)
        #expect(configuration?.transitionStyle == .coverVertical)
        #expect(configuration?.shouldDisablePullDownToDismiss == false)
        #expect(configuration?.animated == true)
        #expect(configuration?.viewController is WhatsNewViewController)
    }

    @Test("Check No Modal Is Provided When No Scheduled Message")
    func whenNoScheduledMessageThenNilIsReturned() {
        // GIVEN
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: nil)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration == nil)
        #expect(mockStore.fetchScheduledRemoteMessageCalls == 1)
    }

    @Test("Check No Modal Is Provided When Message Has Wrong Content Type")
    func whenMessageIsNotCardsListThenNilIsReturned() {
        // GIVEN
        let message = RemoteMessageModel(
            id: "test-message-id",
            surfaces: .modal,
            content: .small(titleText: "Title", descriptionText: "Description"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )

        // WHEN
        let configuration = coordinator.provideModalPrompt()

        // THEN
        #expect(configuration == nil)
    }

    @Test("Check Message Is Marked As Shown When Modal Is Presented")
    func whenModalIsProvidedThenCurrentMessageIdIsStored() async {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "specific-message-id")
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )
        _ = coordinator.provideModalPrompt()

        // WHEN
        coordinator.didPresentModal()

        // THEN - verify the correct message ID was used
        // Yield to let the unstructured Task execute (mock is sync, completes instantly)
        await Task.yield()
        #expect(mockStore.updateRemoteMessageCalls == 1)
        #expect(mockStore.shownRemoteMessagesIDs.contains("specific-message-id"))
    }

    @Test("Check Message Is Not Marked As Shown When No Current Message ID")
    func whenDidPresentModalIsCalledWithoutCurrentMessageIdThenMessageIsNotMarked() async {
        // GIVEN
        let mockStore = MockRemoteMessagingStore()
        let mockHandler = MockRemoteMessagingActionHandler()
        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )

        // WHEN - Call didPresentModal without calling provideModalPrompt first
        coordinator.didPresentModal()

        // THEN
        // Yield to let the unstructured Task execute
        await Task.yield()
        #expect(mockStore.updateRemoteMessageCalls == 0)
    }

}

@MainActor
@Suite("Modal Prompt Coordination - What's New Coordinator Action Handling")
struct WhatsNewCoordinatorActionHandlingTests {

    @Test("Check Present Embedded Web View Pushes View Controller")
    func whenPresentEmbeddedWebViewThenViewControllerIsPushed() async throws {
        // GIVEN
        let testURL = URL(string: "https://example.com/help")!
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()

        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
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
        ] as [RemoteAction]
    )
    func handleActionAlwaysPassesWithinCurrentContextPresentationStyle(action: RemoteAction) async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let mockHandler = MockRemoteMessagingActionHandler()

        let coordinator = WhatsNewCoordinator(
            remoteMessageStore: mockStore,
            remoteMessageActionHandler: mockHandler
        )

        // WHEN
        await coordinator.handleAction(action)

        // THEN
        #expect(mockHandler.didCallHandleAction)
        #expect(mockHandler.capturedPresentationContext?.presentationStyle == .withinCurrentContext)
        #expect(mockHandler.capturedPresentationContext?.presenter != nil)
    }

}
