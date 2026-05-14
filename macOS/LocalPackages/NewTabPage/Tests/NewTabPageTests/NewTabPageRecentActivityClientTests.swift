//
//  NewTabPageRecentActivityClientTests.swift
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

import Combine
import PersistenceTestingUtils
import PrivacyStats
import TrackerRadarKit
import XCTest
@testable import NewTabPage

final class NewTabPageRecentActivityClientTests: XCTestCase {
    private var client: NewTabPageRecentActivityClient!
    private var model: NewTabPageRecentActivityModel!

    private var activityProvider: CapturingNewTabPageRecentActivityProvider!
    private var actionsHandler: CapturingRecentActivityActionsHandler!

    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageRecentActivityClient.MessageName>!

    override func setUp() async throws {
        try await super.setUp()

        activityProvider = CapturingNewTabPageRecentActivityProvider()
        actionsHandler = CapturingRecentActivityActionsHandler()

        model = NewTabPageRecentActivityModel(activityProvider: activityProvider, actionsHandler: actionsHandler)

        client = NewTabPageRecentActivityClient(model: model)

        userScript = NewTabPageUserScript()
        messageHelper = .init(userScript: userScript)
        client.registerMessageHandlers(for: userScript)
    }

    // MARK: - getData

    func testThatGetDataCallsReturnsDataFromRefreshActivityCallOnTheModel() async throws {
        activityProvider.refreshActivityReturnValue = [
            .init(
                id: "abcd",
                title: "Example.com",
                url: "https://example.com",
                etldPlusOne: "example.com",
                favicon: .init(maxAvailableSize: 32, src: "duck://favicon/http%3A//example.com"),
                favorite: false,
                trackersFound: true,
                cookiePopUpBlocked: false,
                trackingStatus: .init(totalCount: 5, trackerCompanies: [.init(displayName: "Facebook")]),
                history: [
                    .init(relativeTime: "Just now", title: "/index.html", url: "https://example.com/index.html"),
                    .init(relativeTime: "5 minutes ago", title: "/index2.html", url: "https://example.com/index2.html")
                ]
            )
        ]

        let data: NewTabPageDataModel.ActivityData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data, .init(activity: activityProvider.refreshActivityReturnValue))
        XCTAssertEqual(activityProvider.refreshActivityCallCount, 1)
    }

    func testWhenActivityIsEmptyThenRefreshActivityReturnsEmptyArray() async throws {
        activityProvider.refreshActivityReturnValue = []

        let data: NewTabPageDataModel.ActivityData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data, .init(activity: activityProvider.refreshActivityReturnValue))
        XCTAssertEqual(activityProvider.refreshActivityCallCount, 1)
    }

    func testThatGetDataIncludesCookiePopUpBlockedWhenTrue() async throws {
        activityProvider.refreshActivityReturnValue = [
            .init(
                id: "abcd",
                title: "Example.com",
                url: "https://example.com",
                etldPlusOne: "example.com",
                favicon: .init(maxAvailableSize: 32, src: "duck://favicon/http%3A//example.com"),
                favorite: false,
                trackersFound: true,
                cookiePopUpBlocked: true,
                trackingStatus: .init(totalCount: 5, trackerCompanies: [.init(displayName: "Facebook")]),
                history: [.init(relativeTime: "Just now", title: "/index.html", url: "https://example.com/index.html")]
            )
        ]

        let data: NewTabPageDataModel.ActivityData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data.activity.count, 1)
        XCTAssertTrue(data.activity[0].cookiePopUpBlocked, "cookiePopUpBlocked should be true when cookie popup was blocked")
    }

    func testThatGetDataIncludesCookiePopUpBlockedWhenFalse() async throws {
        activityProvider.refreshActivityReturnValue = [
            .init(
                id: "abcd",
                title: "Example.com",
                url: "https://example.com",
                etldPlusOne: "example.com",
                favicon: .init(maxAvailableSize: 32, src: "duck://favicon/http%3A//example.com"),
                favorite: false,
                trackersFound: false,
                cookiePopUpBlocked: false,
                trackingStatus: .init(totalCount: 0, trackerCompanies: []),
                history: [.init(relativeTime: "Just now", title: "/index.html", url: "https://example.com/index.html")]
            )
        ]

        let data: NewTabPageDataModel.ActivityData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data.activity.count, 1)
        XCTAssertFalse(data.activity[0].cookiePopUpBlocked, "cookiePopUpBlocked should be false when no cookie popup was blocked")
    }

    func testThatGetDataHandlesMultipleSitesWithDifferentCookiePopUpBlockedValues() async throws {
        activityProvider.refreshActivityReturnValue = [
            .init(
                id: "site1",
                title: "Site with blocked popup",
                url: "https://example1.com",
                etldPlusOne: "example1.com",
                favicon: nil,
                favorite: false,
                trackersFound: true,
                cookiePopUpBlocked: true,
                trackingStatus: .init(totalCount: 3, trackerCompanies: []),
                history: []
            ),
            .init(
                id: "site2",
                title: "Site without blocked popup",
                url: "https://example2.com",
                etldPlusOne: "example2.com",
                favicon: nil,
                favorite: true,
                trackersFound: false,
                cookiePopUpBlocked: false,
                trackingStatus: .init(totalCount: 0, trackerCompanies: []),
                history: []
            )
        ]

        let data: NewTabPageDataModel.ActivityData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data.activity.count, 2)
        XCTAssertTrue(data.activity[0].cookiePopUpBlocked, "First site should have cookie popup blocked")
        XCTAssertFalse(data.activity[1].cookiePopUpBlocked, "Second site should not have cookie popup blocked")
    }

    // MARK: - addFavorite

    func testThatAddFavoriteIsPassedToTheModel() async throws {
        let url = try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/index.html"))
        let action: NewTabPageDataModel.ActivityItemAction = .init(url: url.absoluteString)

        try await messageHelper.handleMessageExpectingNilResponse(named: .addFavorite, parameters: action)
        XCTAssertEqual(actionsHandler.addFavoriteCalls, [url])
    }

    // MARK: - removeFavorite

    func testThatRemoveFavoriteIsPassedToTheModel() async throws {
        let url = try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/index.html"))
        let action: NewTabPageDataModel.ActivityItemAction = .init(url: url.absoluteString)

        try await messageHelper.handleMessageExpectingNilResponse(named: .removeFavorite, parameters: action)
        XCTAssertEqual(actionsHandler.removeFavoriteCalls, [url])
    }

    // MARK: - confirmBurn

    func testWhenConfirmBurnReturnsTrueThenResponseContainsBurnAction() async throws {
        let url = try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/index.html"))
        let action: NewTabPageDataModel.ActivityItemAction = .init(url: url.absoluteString)

        actionsHandler._confirmBurn = { _ in true }

        let response: NewTabPageDataModel.ConfirmBurnResponse = try await messageHelper.handleMessage(named: .confirmBurn, parameters: action)
        XCTAssertEqual(actionsHandler.confirmBurnCalls, [url])
        XCTAssertEqual(response.action, .burn)
    }

    func testWhenConfirmBurnReturnsFalseThenResponseContainsBurnAction() async throws {
        let url = try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/index.html"))
        let action: NewTabPageDataModel.ActivityItemAction = .init(url: url.absoluteString)

        actionsHandler._confirmBurn = { _ in false }

        let response: NewTabPageDataModel.ConfirmBurnResponse = try await messageHelper.handleMessage(named: .confirmBurn, parameters: action)
        XCTAssertEqual(actionsHandler.confirmBurnCalls, [url])
        XCTAssertEqual(response.action, .none)
    }

    // MARK: - open

    func testThatOpenIsPassedToTheModel() async throws {
        let url = try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/index.html"))
        let action: NewTabPageDataModel.ActivityOpenAction = .init(id: "abcd", url: url.absoluteString, target: .sameTab)

        try await messageHelper.handleMessageExpectingNilResponse(named: .open, parameters: action)
        XCTAssertEqual(actionsHandler.openCalls, [.init(url: url, sender: .userScript, target: .current)])
    }
}
