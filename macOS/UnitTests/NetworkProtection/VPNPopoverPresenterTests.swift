//
//  VPNPopoverPresenterTests.swift
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

@MainActor
final class VPNPopoverPresenterTests: XCTestCase {

    var sut: DefaultVPNUpsellPopoverPresenter!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var vpnUpsellVisibilityManager: VPNUpsellVisibilityManager!
    var firedPixels: [PrivacyProPixel] = []

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        firedPixels = []

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
            autoDismissDays: 7,
            pixelHandler: { _ in }
        )
        vpnUpsellVisibilityManager.setup(isFirstLaunch: false)

        sut = DefaultVPNUpsellPopoverPresenter(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )
    }

    override func tearDown() {
        super.tearDown()
        sut = nil
        vpnUpsellVisibilityManager = nil
        mockSubscriptionManager = nil
        mockFeatureFlagger = nil
        mockDefaultBrowserProvider = nil
        firedPixels = []
        mockPersistor = nil
    }

    func testWhenPopoverIsShown_ThenShowPixelIsFired() {
        // Given
        let mockView = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))

        // When
        sut.show(below: mockView)

        // Then
        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, PrivacyProPixel.privacyProToolbarButtonPopoverShown.name)
    }
}
