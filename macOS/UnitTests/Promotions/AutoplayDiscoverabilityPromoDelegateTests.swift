//
//  AutoplayDiscoverabilityPromoDelegateTests.swift
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
import FeatureFlags
import PixelKit
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AutoplayDiscoverabilityPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var windowControllersManager: WindowControllersManagerMock!
    private var firedPixels: [PixelKitEvent]!
    private var sut: AutoplayDiscoverabilityPromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.autoplayPolicy.rawValue: true])
        windowControllersManager = WindowControllersManagerMock()
        firedPixels = []
        sut = AutoplayDiscoverabilityPromoDelegate(featureFlagger: featureFlagger,
                                                   windowControllersManager: windowControllersManager,
                                                   firePixel: { [weak self] pixel in self?.firedPixels.append(pixel) })
    }

    override func tearDown() {
        sut = nil
        firedPixels = nil
        windowControllersManager = nil
        featureFlagger = nil
        super.tearDown()
    }

    func testWhenFeatureFlagOnThenEligible() {
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFeatureFlagOffThenNotEligible() {
        featureFlagger.featuresStub = [FeatureFlag.autoplayPolicy.rawValue: false]

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFeatureFlagChangesThenEligibilityPublisherEmits() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        featureFlagger.featuresStub = [FeatureFlag.autoplayPolicy.rawValue: false]
        featureFlagger.triggerUpdate()
        featureFlagger.featuresStub = [FeatureFlag.autoplayPolicy.rawValue: true]
        featureFlagger.triggerUpdate()

        cancellable.cancel()
        XCTAssertEqual(received, [true, false, true])
    }

    /// No window to anchor to: the promo must end its session rather than leave the queue waiting on
    /// an unresolved continuation.
    func testWhenThereIsNoKeyWindowThenShowReturnsNoChange() async {
        let result = await sut.show(history: PromoHistoryRecord(id: "autoplay-discoverability"), force: false)

        XCTAssertEqual(result, .noChange)
    }

    /// `PromoService` calls `hide()` on any promo it cleans up, including ones that never showed: no dismissal to report.
    func testWhenHiddenWithoutShowingThenNoPixelIsFired() {
        sut.hide()

        XCTAssertTrue(firedPixels.isEmpty)
    }

    // MARK: - Pixels

    /// Nothing was presented, so there is no impression to report.
    func testWhenShowCannotPresentThenNoPixelIsFired() async {
        _ = await sut.show(history: PromoHistoryRecord(id: "autoplay-discoverability"), force: false)

        XCTAssertTrue(firedPixels.isEmpty)
    }

    /// The names must match `autoplay_promo_pixels.json5` verbatim.
    func testPixelNames() {
        XCTAssertEqual(AutoplayPromoPixel.shown.name, "m_mac_autoplay-promo_shown")
        XCTAssertEqual(AutoplayPromoPixel.engaged.name, "m_mac_autoplay-promo_engaged")
        XCTAssertEqual(AutoplayPromoPixel.autoDismissed.name, "m_mac_autoplay-promo_auto-dismissed")
        XCTAssertEqual(AutoplayPromoPixel.settingsLinkClicked.name, "m_mac_autoplay-promo_settings-click")
    }
}
