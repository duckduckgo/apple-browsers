//
//  WinBackOfferPromptPresenterTests.swift
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
import BrowserServicesKit
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo_Privacy_Browser

final class WinBackOfferPromptPresenterTests: XCTestCase {
    var sut: WinBackOfferPromptPresenter!
    var mockVisibilityManager: MockWinBackOfferVisibilityManager!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var lastReceivedURL: URL?
    var capturedPixels: [SubscriptionPixel]!

    override func setUp() {
        super.setUp()
        mockVisibilityManager = MockWinBackOfferVisibilityManager()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        capturedPixels = []
        sut = WinBackOfferPromptPresenter(visibilityManager: mockVisibilityManager, urlOpener: { url in
            self.lastReceivedURL = url
        }, subscriptionManager: mockSubscriptionManager, pixelHandler: { pixel in
            self.capturedPixels.append(pixel)
        })
    }

    override func tearDown() {
        sut = nil
        mockVisibilityManager = nil
        mockSubscriptionManager = nil
        lastReceivedURL = nil
        capturedPixels = nil
        super.tearDown()
    }

    @MainActor
    func testWhenNavigatingToOffer_ItAddsOriginAndFeaturePageParameters() async throws {
        // Given
        mockVisibilityManager.shouldShowLaunchMessage = true

        // When
        sut.handleSeeOffer()

        // Then
        let receivedURL = try XCTUnwrap(lastReceivedURL)
        let components = try XCTUnwrap(URLComponents(url: receivedURL, resolvingAgainstBaseURL: false))
        let originQueryItem = try XCTUnwrap(components.queryItems?.first { $0.name == "origin" })
        let featurePageQueryItem = try XCTUnwrap(components.queryItems?.first { $0.name == "featurePage" })
        XCTAssertEqual(originQueryItem.value, SubscriptionFunnelOrigin.winBackLaunch.rawValue)
        XCTAssertEqual(featurePageQueryItem.value, SubscriptionURL.FeaturePage.winback)
    }

    // MARK: - Pixels

    func testWhenLaunchPromptIsPresented_ItFiresPixel() {
        // Given
        mockVisibilityManager.shouldShowLaunchMessage = true
        XCTAssertEqual(capturedPixels.count, 0, "Should not have fired any pixels yet")

        // When
        sut.tryToShowPrompt(in: MockWindow())

        // Then
        XCTAssertEqual(capturedPixels.count, 1, "Should have fired exactly one pixel")
        if case .subscriptionWinBackOfferLaunchPromptShown = capturedPixels.first! {
            // Correct pixel fired
        } else {
            XCTFail("Should fire subscriptionWinBackOfferLaunchPromptShown pixel")
        }
    }

    @MainActor
    func testWhenLaunchPromptCTAIsClicked_ItFiresPixel() {
        // When
        sut.handleSeeOffer()

        // Then
        XCTAssertEqual(capturedPixels.count, 1, "Should have fired exactly one pixel")
        if case .subscriptionWinBackOfferLaunchPromptCTAClicked = capturedPixels.first! {
            // Correct pixel fired
        } else {
            XCTFail("Should fire subscriptionWinBackOfferLaunchPromptCTAClicked pixel")
        }
    }

    @MainActor
    func testWhenLaunchPromptIsDismissed_ItFiresPixel() {
        // When
        sut.handleDismiss()

        // Then
        XCTAssertEqual(capturedPixels.count, 1, "Should have fired exactly one pixel")
        if case .subscriptionWinBackOfferLaunchPromptDismissed = capturedPixels.first {
            // Correct pixel fired
        } else {
            XCTFail("Should fire subscriptionWinBackOfferLaunchPromptDismissed pixel")
        }
    }
}
