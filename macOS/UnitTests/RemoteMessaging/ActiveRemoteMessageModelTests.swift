//
//  ActiveRemoteMessageModelTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
import RemoteMessaging
import RemoteMessagingTestsUtils
@testable import DuckDuckGo_Privacy_Browser

final class ActiveRemoteMessageModelTests: XCTestCase {

    var model: ActiveRemoteMessageModel!
    private var store: MockRemoteMessagingStore!
    var message: RemoteMessageModel!

    override func setUp() {
        store = MockRemoteMessagingStore()
        message = RemoteMessageModel(
            id: "1",
            surfaces: .newTabPage,
            content: .small(titleText: "test", descriptionText: "desc"), matchingRules: [], exclusionRules: [], isMetricsEnabled: false
        )
    }

    override func tearDown() {
        model = nil
        store = nil
        message = nil
    }

    func testWhenNoMessageIsScheduledThenRemoteMessageIsNil() throws {
        store.scheduledRemoteMessage = nil
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        XCTAssertNil(model.newTabPageRemoteMessage)
    }

    func testWhenMessageIsScheduledThenItIsLoadedToModel() throws {
        store.scheduledRemoteMessage = message
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        XCTAssertEqual(model.newTabPageRemoteMessage, message)
    }

    func testWhenMessageIsDismissedThenItIsClearedFromModel() async throws {
        store.scheduledRemoteMessage = message
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )
        await model.dismissRemoteMessage(with: .close)

        XCTAssertNil(model.newTabPageRemoteMessage)
    }

    func testWhenMessageIsMarkedAsShownThenShownFlagIsSavedInStore() async throws {
        store.scheduledRemoteMessage = message
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        XCTAssertFalse(store.hasShownRemoteMessage(withID: message.id))
        await model.markRemoteMessageAsShown()
        XCTAssertTrue(store.hasShownRemoteMessage(withID: message.id))
    }

    func testWhenMessageIsForTabBar_thenCorrectPublisherIsSet() {
        store.scheduledRemoteMessage = RemoteMessageModel(
            id: "tab_bar_message",
            surfaces: .tabBar,
            content: .bigSingleAction(titleText: "Help Us Improve!",
                                      descriptionText: "Description",
                                      placeholder: .announce,
                                      primaryActionText: "Test",
                                      primaryAction: .survey(value: "www.survey.com")),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        XCTAssertNotNil(model.tabBarRemoteMessage)
        XCTAssertNil(model.newTabPageRemoteMessage)
    }

    func testWhenMessageTargetsBothSurfaces_thenBothPublishersAreSet() {
        store.scheduledRemoteMessage = RemoteMessageModel(
            id: "tab_bar_and_new_tab_message",
            surfaces: [.tabBar, .newTabPage],
            content: .bigSingleAction(titleText: "Help Us Improve!",
                                      descriptionText: "Description",
                                      placeholder: .announce,
                                      primaryActionText: "Test",
                                      primaryAction: .survey(value: "www.survey.com")),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        XCTAssertNotNil(model.tabBarRemoteMessage)
        XCTAssertNotNil(model.newTabPageRemoteMessage)
    }

    func testWhenMessageIsForNewTabPage_thenCorrectPublisherIsSet() {
        store.scheduledRemoteMessage = message
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        XCTAssertNil(model.tabBarRemoteMessage)
        XCTAssertNotNil(model.newTabPageRemoteMessage)
    }

    func testWhenSurfaceSwitchesBetweenTabBarAndNewTabPage_thenOtherPublisherIsCleared() {
        let tabBarMessage = RemoteMessageModel(
            id: "tab_bar_message",
            surfaces: .tabBar,
            content: .bigSingleAction(titleText: "Help Us Improve!",
                                      descriptionText: "Description",
                                      placeholder: .announce,
                                      primaryActionText: "Test",
                                      primaryAction: .survey(value: "www.survey.com")),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        store.scheduledRemoteMessage = tabBarMessage
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )
        XCTAssertNotNil(model.tabBarRemoteMessage)
        XCTAssertNil(model.newTabPageRemoteMessage)

        let newTabMessage = RemoteMessageModel(
            id: "new_tab_message",
            surfaces: .newTabPage,
            content: .small(titleText: "Hello", descriptionText: "World"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        store.scheduledRemoteMessage = newTabMessage
        NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        let expectation = expectation(description: "Switches to new tab message and clears tab bar message")
        DispatchQueue.main.async {
            XCTAssertNil(self.model.tabBarRemoteMessage)
            XCTAssertEqual(self.model.newTabPageRemoteMessage, newTabMessage)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenScheduledMessageIsCalledThenSurfaceIsNewTabPage() {
        // GIVEN
        store.scheduledRemoteMessage = message
        XCTAssertEqual(store.fetchScheduledRemoteMessageCalls, 0)
        XCTAssertNil(store.capturedSurfaces)

        // WHEN
        model = ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { }
        )

        // THEN
        XCTAssertEqual(store.fetchScheduledRemoteMessageCalls, 1)
        XCTAssertTrue(store.capturedSurfaces!.contains(.newTabPage))
        XCTAssertTrue(store.capturedSurfaces!.contains(.tabBar))
    }

}
