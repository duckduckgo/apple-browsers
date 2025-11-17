//
//  HomeMessageViewModelTests.swift
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
import RemoteMessaging
import Foundation
@testable import DuckDuckGo

@Suite("RMF - Home Message View Model")
struct HomeMessageViewModelTests {
    let mockActionHandler = MockRemoteMessagingActionHandler()
    let mockPresenter = MockRemoteMessagingPresenter()

    func makeSUT(
        modelType: HomeSupportedMessageDisplayType = .small(titleText: "Title", descriptionText: "Description"),
        onDidClose: @escaping (HomeMessageViewModel.ButtonAction?) async -> Void = { _ in }
    ) -> HomeMessageViewModel {
        HomeMessageViewModel(
            messageId: "test-message",
            sendPixels: true,
            modelType: modelType,
            messageActionHandler: mockActionHandler,
            onDidClose: onDidClose,
            onDidAppear: {},
            onAttachAdditionalParameters: nil
        )
    }

    @Test(
        "Check Mapped Action Closure Calls Action Handler And Did Close Closure",
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
    func mapActionToViewModelCallsActionHandlerAndOnDidClose(remoteAction: RemoteAction) async throws {
        // GIVEN
        var onDidCloseCalled = false
        var capturedButtonAction: HomeMessageViewModel.ButtonAction?
        let sut = makeSUT { action in
            onDidCloseCalled = true
            capturedButtonAction = action
        }
        let isShare = remoteAction == .share(value: "Test Value", title: "Test Title")
        let buttonAction = HomeMessageViewModel.ButtonAction.primaryAction(isShare: isShare)

        // WHEN
        let viewModelAction = sut.mapActionToViewModel(
            remoteAction: remoteAction,
            buttonAction: buttonAction,
            onDidClose: sut.onDidClose
        )
        await viewModelAction(mockPresenter)

        // THEN
        #expect(mockActionHandler.didCallHandleAction)
        #expect(mockActionHandler.capturedRemoteAction == remoteAction)
        #expect(onDidCloseCalled)
        #expect(capturedButtonAction == buttonAction)
    }

    @Test(
        "Check Image Property Returns Expected Value For Model Type",
        arguments: [
            (
                .small(titleText: "", descriptionText: ""),
                nil
            ),
            (
                .medium(titleText: "", descriptionText: "", placeholder: .announce),
                RemotePlaceholder.announce.rawValue
            ),
            (
                .bigSingleAction(titleText: "", descriptionText: "", placeholder: .criticalUpdate, primaryActionText: "", primaryAction: .dismiss),
                RemotePlaceholder.criticalUpdate.rawValue
            ),
            (
                .bigTwoAction(titleText: "", descriptionText: "", placeholder: .ddgAnnounce, primaryActionText: "", primaryAction: .dismiss, secondaryActionText: "", secondaryAction: .dismiss),
                RemotePlaceholder.ddgAnnounce.rawValue
            ),
            (
                .promoSingleAction(titleText: "", descriptionText: "", placeholder: .macComputer, actionText: "", action: .dismiss),
                RemotePlaceholder.macComputer.rawValue
            )
        ] as [(HomeSupportedMessageDisplayType, String?)]
    )
    func imagePropertyReturnsCorrectValues(modelType: HomeSupportedMessageDisplayType, expectedImage: String?) throws {
        // GIVEN
        let sut = makeSUT(modelType: modelType)

        // WHEN
        let result = sut.image

        // THEN
        #expect(result == expectedImage)
    }

    @Test(
        "Check Title Property Returns Expected Value For Model Type",
        arguments: [
            (
                .small(titleText: "Small Title", descriptionText: ""),
                "Small Title"
            ),
            (
                .medium(titleText: "Medium Title", descriptionText: "", placeholder: .announce),
                "Medium Title"
            ),
            (
                .bigSingleAction(titleText: "Big Single Title", descriptionText: "", placeholder: .announce, primaryActionText: "", primaryAction: .dismiss),
                "Big Single Title"
            ),
            (
                .bigTwoAction(titleText: "Big Two Title", descriptionText: "", placeholder: .announce, primaryActionText: "", primaryAction: .dismiss, secondaryActionText: "", secondaryAction: .dismiss),
                "Big Two Title"
            ),
            (
                .promoSingleAction(titleText: "Promo Title", descriptionText: "", placeholder: .announce, actionText: "", action: .dismiss),
                "Promo Title"
            )
        ] as [(HomeSupportedMessageDisplayType, String)]
    )
    func titlePropertyReturnsCorrectValues(modelType: HomeSupportedMessageDisplayType, expectedTitle: String) throws {
        // GIVEN
        let sut = makeSUT(modelType: modelType)

        // WHEN
        let result = sut.title

        // THEN
        #expect(result == expectedTitle)
    }

    @Test(
        "Subtitle property transforms HTML bold tags to markdown",
        arguments: [
            (
                .small(titleText: "", descriptionText: "<b>Small</b> Description"),
                "**Small** Description"
            ),
            (
                .medium(titleText: "", descriptionText: "<b>Medium</b> Description", placeholder: .announce),
                "**Medium** Description"
            ),
            (
                .bigSingleAction(titleText: "", descriptionText: "<b>Big Single</b> Description", placeholder: .announce, primaryActionText: "", primaryAction: .dismiss),
                "**Big Single** Description"
            ),
            (
                .bigTwoAction(titleText: "", descriptionText: "<b>Big Two</b> Description", placeholder: .announce, primaryActionText: "", primaryAction: .dismiss, secondaryActionText: "", secondaryAction: .dismiss),
                "**Big Two** Description"
            ),
            (
                .promoSingleAction(titleText: "", descriptionText: "<b>Promo</b> Description", placeholder: .announce, actionText: "", action: .dismiss),
                "**Promo** Description"
            )
        ] as [(HomeSupportedMessageDisplayType, String)]

    )
    func subtitlePropertyTransformsHTMLToMarkdown(modelType: HomeSupportedMessageDisplayType, expectedSubtitle: String) throws {
        // GIVEN
        let sut = makeSUT(modelType: modelType)

        // WHEN
        let subtitle = sut.subtitle

        // THEN
        #expect(subtitle == expectedSubtitle)
    }

    @Test(
        "Check Mapped Action Always Passes Dismiss Modals Presentation Style",
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
    func mapActionToViewModelAlwaysPassesDismissModalsPresentationStyle(remoteAction: RemoteAction) async throws {
        // GIVEN
        let sut = makeSUT()
        let buttonAction = HomeMessageViewModel.ButtonAction.primaryAction(isShare: false)

        // WHEN
        let viewModelAction = sut.mapActionToViewModel(
            remoteAction: remoteAction,
            buttonAction: buttonAction,
            onDidClose: sut.onDidClose
        )
        await viewModelAction(mockPresenter)

        // THEN
        #expect(mockActionHandler.capturedPresentationContext?.presentationStyle == .dismissModalsAndPresentFromRoot)
        #expect(mockActionHandler.capturedPresentationContext?.presenter != nil)
    }
}
