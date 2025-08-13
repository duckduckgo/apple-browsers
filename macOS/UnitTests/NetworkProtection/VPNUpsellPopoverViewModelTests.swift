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
import Common
import VPN
import BrowserServicesKit
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VPNUpsellPopoverViewModelTests: XCTestCase {
    var sut: VPNUpsellPopoverViewModel!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var vpnUpsellVisibilityManager: VPNUpsellVisibilityManager!
    var lastReceivedURL: URL?
    var firedPixels: [PrivacyProPixel] = []
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        firedPixels = []

        mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)

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

        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            urlOpener: { url in
                self.lastReceivedURL = url
            },
            onDismiss: {},
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
        lastReceivedURL = nil
        firedPixels = []
        mockPersistor = nil
        cancellables.removeAll()
    }

    func testWhenPopoverIsDismissed_ThenDismissedFlagIsSet() throws {
            // Given
            XCTAssertEqual(vpnUpsellVisibilityManager.state, .visible)
            XCTAssertFalse(mockPersistor.vpnUpsellDismissed)

            // When
            sut.dismiss()

            // Then
            XCTAssertTrue(mockPersistor.vpnUpsellDismissed)
        XCTAssertEqual(vpnUpsellVisibilityManager.state, .dismissed)
    }

    func testWhenPopoverIsDismissed_ThenDismissPixelIsFired() throws {
        // Given
        XCTAssertTrue(firedPixels.isEmpty)

        // When
        sut.dismiss()

        // Then
        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, PrivacyProPixel.privacyProToolbarButtonPopoverDismissButtonClicked.name)
    }

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

    func testWhenPrimaryCTAIsClicked_ThenProceedPixelIsFired() throws {
        // Given
        let baseURL = URL(string: "https://duckduckgo.com/pro/purchase")!
        mockSubscriptionManager.urls[.purchase] = baseURL
        XCTAssertTrue(firedPixels.isEmpty)

        // When
        sut.showSubscriptionLandingPage()

        // Then
        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, PrivacyProPixel.privacyProToolbarButtonPopoverProceedButtonClicked.name)
    }

    func testWhenUserIsEligibleForFreeTrial_ThenMainCTATitleIsTryForFree() throws {
        // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertEqual(featureSet.mainCTATitle, UserText.vpnUpsellPopoverFreeTrialCTA)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }

    func testWhenUserIsNotEligibleForFreeTrial_ThenMainCTATitleIsLearnMore() throws {
        // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")
        mockSubscriptionManager.isEligibleForFreeTrialResult = false

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertEqual(featureSet.mainCTATitle, UserText.vpnUpsellPopoverLearnMoreCTA)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }

    func testWhenListingPlusFeatures_ItAlwaysListsIdentityTheftProtection() throws {
        // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertTrue(featureSet.plus.contains(.identityTheftProtection))
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }

    func testWhenListingPlusFeatures_AndAIChatIsEnabled_ItListsAIChat() throws {
        // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")
        mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell, .paidAIChat]

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertEqual(featureSet.plus.first, .aiChat)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }

    func testWhenListingPlusFeatures_AndPIRIsEnabled_ItListsPIR() throws {
        // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")
        mockSubscriptionManager.enabledFeatures = [.dataBrokerProtection]
        mockSubscriptionManager.subscriptionFeatures = [.dataBrokerProtection]

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertEqual(featureSet.plus.last, .pir)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }

    func testWhenOnlyOnePlusFeatureIsEnabled_TheCopyDoesNotContainTheCount() throws {
        // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertEqual(featureSet.plusFeaturesSubtitle, UserText.vpnUpsellPopoverPlusFeaturesSubtitle)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }

    func testWhenMoreThanOnePlusFeatureIsEnabled_TheCopyContainsTheCorrectCount() throws {
         // Given
        let expectation = XCTestExpectation(description: "Feature set should be updated")
        mockSubscriptionManager.enabledFeatures = [.dataBrokerProtection, .paidAIChat]
        mockSubscriptionManager.subscriptionFeatures = [.dataBrokerProtection, .paidAIChat]

        sut.$featureSet
            .dropFirst()
            .sink { featureSet in
                // Then
                XCTAssertEqual(featureSet.plusFeaturesSubtitle, String(format: UserText.vpnUpsellPopoverPlusFeaturesSubtitleCount, 2))
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut = VPNUpsellPopoverViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: {},
            pixelHandler: { pixel in
                self.firedPixels.append(pixel)
            }
        )

        wait(for: [expectation], timeout: 1)
    }
}
