//
//  VPNUpsellPopoverViewModelTests.swift
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
import Combine
import VPN
import BrowserServicesKit
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo_Privacy_Browser

final class VPNUpsellPopoverViewModelTests: XCTestCase {
    var sut: VPNUpsellPopoverViewModel!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var vpnUpsellVisibilityManager: VPNUpsellVisibilityManager!
    var lastReceivedURL: URL?

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()

        mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]

        vpnUpsellVisibilityManager = VPNUpsellVisibilityManager(
            isFirstLaunch: false,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.01,
            autoDismissDays: 7
        )
        vpnUpsellVisibilityManager.setup(isFirstLaunch: false)

        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            urlOpener: { url in
                self.lastReceivedURL = url
            },
            onDismiss: {}
        )
    }

    override func tearDown() {
        super.tearDown()
        sut = nil
        vpnUpsellVisibilityManager = nil
        mockSubscriptionManager = nil
        mockFeatureFlagger = nil
        mockDefaultBrowserProvider = nil
        lastReceivedURL = nil
        mockPersistor = nil
    }

    func testWhenPopoverIsDismissed_ThenDismissedFlagIsSet() throws {
        autoreleasepool {
            // Given
            XCTAssertEqual(vpnUpsellVisibilityManager.state, .visible)
            XCTAssertFalse(mockPersistor.vpnUpsellDismissed)

            // When
            sut.dismiss()

            // Then
            XCTAssertTrue(mockPersistor.vpnUpsellDismissed)
            XCTAssertEqual(vpnUpsellVisibilityManager.state, .dismissed)
        }
    }

    @MainActor
    func testWhenPrimaryCTAIsClicked_SubscriptionLandingPageIsOpened_AndOriginIsSet() throws {
        // Given
        let baseURL = URL(string: "https://duckduckgo.com/pro/purchase")!
        mockSubscriptionManager.urls[.purchase] = baseURL

        // When
        sut.showSubscriptionLandingPage()

        // Then
        let receivedURL = try XCTUnwrap(lastReceivedURL)
        let components = try XCTUnwrap(URLComponents(url: receivedURL, resolvingAgainstBaseURL: false))
        let originQueryItem = try XCTUnwrap(components.queryItems?.first { $0.name == "origin" })
        XCTAssertEqual(originQueryItem.value, SubscriptionFunnelOrigin.vpnUpsell.rawValue)
        XCTAssertEqual(originQueryItem.value, "funnel_toolbar_macos")
    }
}
