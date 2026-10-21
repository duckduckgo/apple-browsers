//
//  WinBackOfferPromotionViewCoordinatorTests.swift
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
@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

final class WinBackOfferPromotionViewCoordinatorTests: XCTestCase {

    private var sut: WinBackOfferPromotionViewCoordinator!
    private var mockVisibilityManager: MockWinBackOfferVisibilityManager!
    private var capturedPixels: [SubscriptionPixel]!

    override func setUp() {
        super.setUp()

        capturedPixels = []
        mockVisibilityManager = MockWinBackOfferVisibilityManager()
        mockVisibilityManager.shouldShowUrgencyMessage = true
        mockVisibilityManager.didDismissUrgencyMessage = false

        sut = WinBackOfferPromotionViewCoordinator(
            winBackOfferVisibilityManager: mockVisibilityManager,
            pixelHandler: { [weak self] pixel in
                self?.capturedPixels.append(pixel)
            },
            urlOpener: { _ in }
        )
    }

    override func tearDown() {
        sut = nil
        mockVisibilityManager = nil
        capturedPixels = nil
        super.tearDown()
    }

    // MARK: - Pixel Tests

    func testWhenCreateViewModelCalled_ItFiresShownPixel() {
        // When
        let viewModel = sut.createViewModel()

        // Then
        XCTAssertNotNil(viewModel)
        XCTAssertEqual(capturedPixels.count, 1, "Should have fired exactly one pixel")
        if case .subscriptionWinBackOfferNewTabPageShown = capturedPixels.first! {
            // Correct pixel fired
        } else {
            XCTFail("Should fire subscriptionWinBackOfferNewTabPageShown pixel")
        }
    }

    func testWhenProceedActionCalled_ItFiresCTAClickedPixel() async {
        // When
        await sut.proceedAction()

        // Then
        if case .subscriptionWinBackOfferNewTabPageCTAClicked = capturedPixels.last! {
            // Correct pixel fired
        } else {
            XCTFail("Should fire subscriptionWinBackOfferNewTabPageCTAClicked pixel")
        }
    }

    func testWhenCloseActionCalled_ItFiresDismissedPixel() {
        // When
        sut.closeAction()

        // Then
        XCTAssertEqual(capturedPixels.count, 1, "Should have fired exactly one pixel")
        if case .subscriptionWinBackOfferNewTabPageDismissed = capturedPixels.first! {
            // Correct pixel fired
        } else {
            XCTFail("Should fire subscriptionWinBackOfferNewTabPageDismissed pixel")
        }
    }
}
