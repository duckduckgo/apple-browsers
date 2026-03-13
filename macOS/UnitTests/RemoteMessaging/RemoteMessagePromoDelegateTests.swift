//
//  RemoteMessagePromoDelegateTests.swift
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

import Combine
import Foundation
import PersistenceTestingUtils
import RemoteMessaging
import RemoteMessagingTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class RemoteMessagePromoDelegateTests: XCTestCase {

    private var model: ActiveRemoteMessageModel!
    private var store: MockRemoteMessagingStore!
    private var ntpMessage: RemoteMessageModel!
    private var tabBarMessage: RemoteMessageModel!

    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        store = MockRemoteMessagingStore()
        ntpMessage = RemoteMessageModel(
            id: "ntp-1",
            surfaces: .newTabPage,
            content: .small(titleText: "test", descriptionText: "desc"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        tabBarMessage = RemoteMessageModel(
            id: "tabbar-1",
            surfaces: .tabBar,
            content: .bigSingleAction(
                titleText: "Help Us Improve!",
                descriptionText: "Description",
                placeholder: .announce,
                imageUrl: nil,
                primaryActionText: "Test",
                primaryAction: .survey(value: "www.survey.com")
            ),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
    }

    override func tearDown() {
        model = nil
        store = nil
        ntpMessage = nil
        tabBarMessage = nil
        cancellables.removeAll()
        super.tearDown()
    }

    private func makeModel() -> ActiveRemoteMessageModel {
        ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { },
            navigateToPIRHandler: { },
            navigateToSoftwareUpdateHandler: { }
        )
    }

    // MARK: - Visibility Tests

    func testWhenNTPMessageExistsThenNTPDelegateIsVisible() {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenTabBarMessageExistsThenTabBarDelegateIsVisible() {
        store.scheduledRemoteMessage = tabBarMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .tabBar)

        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenNoMessageExistsThenDelegateIsNotVisible() {
        store.scheduledRemoteMessage = nil
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        XCTAssertFalse(delegate.isVisible)
    }

    func testWhenNTPMessageExistsThenNTPDelegatePublisherEmitsVisible() {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        let expectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(try XCTUnwrap(receivedVisible))
    }

    func testWhenTabBarMessageExistsThenTabBarDelegatePublisherEmitsVisible() {
        store.scheduledRemoteMessage = tabBarMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .tabBar)

        let expectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(try XCTUnwrap(receivedVisible))
    }

    func testWhenNoMessageExistsThenDelegatePublisherEmitsNotVisible() {
        store.scheduledRemoteMessage = nil
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        let expectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(delegate.isVisible)
        XCTAssertFalse(try XCTUnwrap(receivedVisible))
    }

    func testWhenMessageAppearsThenVisibilityUpdatesToTrue() {
        store.scheduledRemoteMessage = nil
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        let visibilityExpectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .dropFirst()
            .sink { visible in
                receivedVisible = visible
                if visible {
                    visibilityExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        store.scheduledRemoteMessage = ntpMessage
        NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        let modelUpdated = expectation(description: "Model updated")
        DispatchQueue.main.async {
            modelUpdated.fulfill()
        }
        wait(for: [modelUpdated], timeout: 1.0)

        wait(for: [visibilityExpectation], timeout: 1.0)
        XCTAssertTrue(try XCTUnwrap(receivedVisible))
    }

    func testWhenMessageDisappearsThenVisibilityUpdatesToFalse() {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        let expectation = expectation(description: "Visibility becomes false")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .dropFirst()
            .sink { visible in
                receivedVisible = visible
                if !visible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        store.scheduledRemoteMessage = nil
        NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(try XCTUnwrap(receivedVisible))
    }

    func testWhenMessageHasUnsupportedContentThenDelegateIsNotVisible() {
        let unsupportedMessage = RemoteMessageModel(
            id: "unsupported-1",
            surfaces: .newTabPage,
            content: .promoSingleAction(
                titleText: "Unsupported",
                descriptionText: "Desc",
                placeholder: .announce,
                imageUrl: nil,
                actionText: "OK",
                action: .dismiss
            ),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        store.scheduledRemoteMessage = unsupportedMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        let expectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(try XCTUnwrap(receivedVisible))
    }
}
