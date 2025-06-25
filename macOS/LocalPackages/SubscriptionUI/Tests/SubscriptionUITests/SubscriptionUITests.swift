//
//  SubscriptionUITests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import SubscriptionUI
import Combine
import PreferencesUI_macOS

final class SubscriptionUITests: XCTestCase {

    func testPreferencesPaidAIChatModel_Initialization() {
        var receivedEvents: [PreferencesPaidAIChatModel.UserEvent] = []
        let statusSubject = CurrentValueSubject<StatusIndicator, Never>(.off)

        let model = PreferencesPaidAIChatModel(
            userEventHandler: { event in
                receivedEvents.append(event)
            },
            statusUpdates: statusSubject.eraseToAnyPublisher()
        )

        XCTAssertEqual(model.status, .off)
    }

    func testPreferencesPaidAIChatModel_UserEvents() async {
        var receivedEvents: [PreferencesPaidAIChatModel.UserEvent] = []

        let model = PreferencesPaidAIChatModel(
            userEventHandler: { event in
                receivedEvents.append(event)
            },
            statusUpdates: Just(.off).eraseToAnyPublisher()
        )

        // Test didAppear
        await model.didAppear()
        XCTAssertEqual(receivedEvents.count, 1)
        if case .didOpenAICPreferencePane = receivedEvents[0] {
            // Expected event
        } else {
            XCTFail("Unexpected event type")
        }

        // Test openPaidAIChat
        await model.openPaidAIChat()
        XCTAssertEqual(receivedEvents.count, 2)
        if case .openAIC = receivedEvents[1] {
            // Expected event
        } else {
            XCTFail("Unexpected event type")
        }

        // Test openFAQ
        await model.openFAQ()
        XCTAssertEqual(receivedEvents.count, 3)
        if case .openURL(let url) = receivedEvents[2] {
            XCTAssertEqual(url, .faq)
        } else {
            XCTFail("Unexpected event type")
        }
    }

    func testPreferencesPaidAIChatModel_StatusUpdates() {
        let statusSubject = CurrentValueSubject<StatusIndicator, Never>(.off)

        let model = PreferencesPaidAIChatModel(
            userEventHandler: { _ in },
            statusUpdates: statusSubject.eraseToAnyPublisher()
        )

        XCTAssertEqual(model.status, .off)

        statusSubject.send(.on)
        XCTAssertEqual(model.status, .on)

        statusSubject.send(.off)
        XCTAssertEqual(model.status, .off)
    }
}
