//
//  DefaultBrowserAndDockPromptServiceTests.swift
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

import XCTest
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptServiceTests: XCTestCase {

    private var sut: DefaultBrowserAndDockPromptService!
    private var notificationPresenterMock: MockDefaultBrowserAndDockPromptNotificationPresenter!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let featureFlaggerMock = MockFeatureFlagger()
        let privacyConfigManagerMock = MockPrivacyConfigurationManager()
        let storeMock = MockThrowingKeyValueStore()
        notificationPresenterMock = MockDefaultBrowserAndDockPromptNotificationPresenter()
        sut = DefaultBrowserAndDockPromptService(featureFlagger: featureFlaggerMock,
                                                 privacyConfigManager: privacyConfigManagerMock,
                                                 keyValueStore: storeMock,
                                                 notificationPresenter: notificationPresenterMock,
                                                 isOnboardingCompletedProvider: { true })
    }

    override func tearDownWithError() throws {
        sut = nil
        notificationPresenterMock = nil

        try super.tearDownWithError()
    }

    func testHandleNotificationResponse_SendsExpectedResponseToNotificationPresenter() async throws {
        // GIVEN
        XCTAssertEqual(notificationPresenterMock.receivedResponses.count, 0)

        // WHEN
        await sut.handleNotificationResponse(.inactiveUserFeedbackRequest)

        // THEN
        XCTAssertEqual(notificationPresenterMock.receivedResponses.count, 1)
        XCTAssertEqual(notificationPresenterMock.receivedResponses.first, .inactiveUserFeedbackRequest)
    }

}
