//
//  RootViewV2Tests.swift
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
import Subscription
import SubscriptionTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser
@testable import SubscriptionUI

@MainActor
final class RootViewV2Tests: XCTestCase {
    var sidebarModel: PreferencesSidebarModel!
    var subscriptionManager: SubscriptionManagerMockV2!
    var subscriptionUIHandler: SubscriptionUIHandlerMock!
    var showTabCalled: Bool = false
    var showTabContent: Tab.TabContent?

    override func setUpWithError() throws {
        let ddsSyncing = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let vpnGatekeeper = MockVPNFeatureGatekeeper(canStartVPN: false, isInstalled: false, isVPNVisible: false, onboardStatusPublisher: Just(.completed).eraseToAnyPublisher())

        sidebarModel = PreferencesSidebarModel(privacyConfigurationManager: MockPrivacyConfigurationManaging(), featureFlagger: MockFeatureFlagger(), syncService: ddsSyncing, vpnGatekeeper: vpnGatekeeper, includeDuckPlayer: false, includeAIChat: true, subscriptionManager: SubscriptionAuthV1toV2BridgeMock())
        subscriptionManager = SubscriptionManagerMockV2()
        subscriptionUIHandler = SubscriptionUIHandlerMock( didPerformActionCallback: { _ in })
        showTabCalled = false
        showTabContent = nil
        subscriptionManager.resultStorePurchaseManager = StorePurchaseManagerMockV2()
    }

    override func tearDownWithError() throws {
        sidebarModel = nil
        subscriptionManager = nil
        subscriptionUIHandler = nil
        showTabCalled = false
        showTabContent = nil
    }

    func testMakePaidAIChatViewModel() throws {
        // Given
        let rootView = Preferences.RootViewV2(
            model: sidebarModel,
            subscriptionManager: subscriptionManager,
            subscriptionUIHandler: subscriptionUIHandler,
            aiChatURLSettings: MockRemoteAISettings(),
            showTab: { _ in },
            )

        // Then
        let model = rootView.paidAIChatModel!
        XCTAssertNotNil(model, "PaidAIChatModel should be created")
    }

    func testPaidAIChatViewModel_OpenAIChat() throws {
        let expectation = expectation(description: "Wait for showTab to be called")
        let mockRemoteAISettings = MockRemoteAISettings()
        // Given
        let rootView = Preferences.RootViewV2(
            model: sidebarModel,
            subscriptionManager: subscriptionManager,
            subscriptionUIHandler: subscriptionUIHandler,
            aiChatURLSettings: mockRemoteAISettings
        ) { content in
            self.showTabCalled = true
            self.showTabContent = content
            expectation.fulfill()
        }

        let model = rootView.paidAIChatModel!

        // When
        model.openPaidAIChat()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(showTabCalled, "Should call showTab")
        if case .url(let url, _, let source) = showTabContent {
            XCTAssertEqual(url.absoluteString, mockRemoteAISettings.aiChatURL.absoluteString)
            XCTAssertEqual(source, .ui)
        } else {
            XCTFail("Expected URL tab content")
        }
    }

    func testPaidAIChatViewModel_OpenURL() throws {
        let expectation = expectation(description: "Wait for showTab to be called")
        subscriptionManager.resultURL = URL.duckDuckGo

        // Given
        let rootView = Preferences.RootViewV2(
            model: sidebarModel,
            subscriptionManager: subscriptionManager,
            subscriptionUIHandler: subscriptionUIHandler,
            aiChatURLSettings: MockRemoteAISettings()
        ) { content in
            self.showTabCalled = true
            self.showTabContent = content
            expectation.fulfill()
        }

        let model = rootView.paidAIChatModel!

        // When
        model.openFAQ()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(showTabCalled, "Should call showTab")
        XCTAssertEqual(subscriptionManager.subscriptionURL, .faq)
        if case .subscription = showTabContent {
            // Success
        } else {
            XCTFail("Expected subscription tab content")
        }
    }

}
