//
//  RemoteMessagingActionHandlerTests.swift
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

@Suite("RMF - Remote Action Handling")
struct RemoteMessagingActionHandlerTests {

    @Test(
        "Check Share Action Asks Presenter To Present Activity Sheet With Expected Values",
        arguments: [
            ("https://example.com", "Example Title"),
            ("https://example.com", nil)
        ] as [(String, String?)]

    )
    func shareActionPresentsActivitySheet(value: String, title: String?) async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let sut = RemoteMessagingActionHandler()
        let shareAction = RemoteAction.share(value: value, title: title)

        // WHEN
        await sut.handleAction(shareAction, context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockPresenter.didCallPresentActivitySheet)
        #expect(mockPresenter.capturedActivitySheetValue == value)
        #expect(mockPresenter.capturedActivitySheetTitle == title)
    }


    @Test("Check URL Action Asks Browser Tab To Open URL")
    func urlActionOpensTab() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let mockTabOpener = MockBrowserTabURLOpener()
        let sut = RemoteMessagingActionHandler(browserTabUrlOpener: mockTabOpener.open)
        let urlAction = RemoteAction.url(value: "https://example.com")

        // WHEN
        await sut.handleAction(urlAction, context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockTabOpener.openedURL == "https://example.com")
    }

    @Test("Check URL In Context Action With Valid URL Asks Presenter To Present Embedded Web View")
    func urlInContextActionWithValidURLPresentsEmbeddedWebView() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let sut = RemoteMessagingActionHandler()
        let urlInContextAction = RemoteAction.urlInContext(value: "https://example.com")

        // WHEN
        await sut.handleAction(urlInContextAction, context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockPresenter.didCallPresentEmbeddedWebView)
        #expect(mockPresenter.capturedEmbeddedWebViewURL?.absoluteString == "https://example.com")
    }

    @Test("Check URL In Context Action With Invalid URL Does Not Ask Presenter To Present Embedded Web View")
    func urlInContextActionWithInvalidURLDoesNothing() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let sut = RemoteMessagingActionHandler()
        let urlInContextAction = RemoteAction.urlInContext(value: "not a valid url")

        // WHEN
        await sut.handleAction(urlInContextAction, context: .init(presenter: mockPresenter))

        // THEN
        #expect(!mockPresenter.didCallPresentEmbeddedWebView)
        #expect(mockPresenter.capturedEmbeddedWebViewURL == nil)
    }

    @Test("Check App Store Action Asks URL Opener to Open App Store URL When URL Can Be Opened")
    func appStoreActionOpensAppStore() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let mockURLOpener = MockURLOpener()
        mockURLOpener.canOpenURL = true
        let sut = RemoteMessagingActionHandler(urlOpener: mockURLOpener)

        // WHEN
        await sut.handleAction(.appStore, context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockURLOpener.didCallCanOpenURL)
        #expect(mockURLOpener.didCallOpenURL)
        #expect(mockURLOpener.capturedURL == URL.appStore)
    }

    @Test("Check App Store Action Does Not Ask To Open App Store URL When URL Cannot Be Opened")
    func appStoreActionDoesNotOpenWhenUnavailable() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let mockURLOpener = MockURLOpener()
        mockURLOpener.canOpenURL = false
        let sut = RemoteMessagingActionHandler(urlOpener: mockURLOpener)

        // WHEN
        await sut.handleAction(.appStore, context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockURLOpener.didCallCanOpenURL)
        #expect(!mockURLOpener.didCallOpenURL)
    }

    @Test("Check Survey Action Refreshes Last Search State And Opens Browser Tab")
    func surveyActionRefreshesSearchStateAndOpensTab() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let mockLastSearchStateRefresher = MockLastSearchStateRefresher()
        let mockTabOpener = MockBrowserTabURLOpener()
        let sut = RemoteMessagingActionHandler(
            lastSearchStateRefresher: mockLastSearchStateRefresher,
            browserTabUrlOpener: mockTabOpener.open
        )
        let surveyAction = RemoteAction.survey(value: "https://survey.example.com?param=value")

        // WHEN
        await sut.handleAction(surveyAction, context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockLastSearchStateRefresher.didCallRefreshLastSearchState)
        #expect(mockLastSearchStateRefresher.capturedURLPath == "https://survey.example.com?param=value")
        #expect(mockTabOpener.openedURL == "https://survey.example.com?param=value&refreshed=true")
    }

    @Test(
        "Check Navigation Action Asks Message Navigator To Handle Navigation Action",
        arguments: [
            .sync,
            .settings,
            .duckAISettings,
            .feedback,
            .duckAISettings,
            .importPasswords
        ] as [NavigationTarget]

    )
    func navigationActionHandlesDifferentTargets(navigationTarget: NavigationTarget) async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let mockNavigator = MockMessageNavigator()
        let sut = RemoteMessagingActionHandler()
        sut.messageNavigator = mockNavigator

        // WHEN
        await sut.handleAction(.navigation(value: navigationTarget), context: .init(presenter: mockPresenter))

        // THEN
        #expect(mockNavigator.didCallNavigateToNavigationTarget)
        #expect(mockNavigator.capturedNavigationTarget == navigationTarget)
    }

    @Test("Check Dismiss Action Does Nothing")
    func dismissActionDoesNothing() async throws {
        // GIVEN
        let mockPresenter = MockRemoteMessagingPresenter()
        let mockRefresher = MockLastSearchStateRefresher()
        let mockTabOpener = MockBrowserTabURLOpener()
        let mockURLOpener = MockURLOpener()
        let sut = RemoteMessagingActionHandler(
            lastSearchStateRefresher: mockRefresher,
            urlOpener: mockURLOpener,
            browserTabUrlOpener: mockTabOpener.open
        )

        // WHEN
        await sut.handleAction(.dismiss, context: .init(presenter: mockPresenter))

        // THEN
        #expect(!mockRefresher.didCallRefreshLastSearchState)
        #expect(!mockPresenter.didCallPresentActivitySheet)
        #expect(!mockPresenter.didCallPresentEmbeddedWebView)
        #expect(!mockURLOpener.didCallCanOpenURL)
        #expect(!mockURLOpener.didCallOpenURL)
        #expect(mockURLOpener.capturedURL == nil)
        #expect(mockTabOpener.openedURL == nil)
    }
}

private extension PresentationContext {

    init(presenter: RemoteMessagingPresenter) {
        self.init(presenter: presenter, presentationStyle: .dismissModalsAndPresentFromRoot)
    }
}
