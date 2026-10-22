//
//  DefaultVisualizeFireSettingsDeciderTests.swift
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

import Common
import FoundationExtensions
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DefaultVisualizeFireSettingsDeciderTests: XCTestCase {

    func testWhenDialogBurnKeepsTabsOpen_thenFireAnimationIsEnabledWithoutPrivacyFeedDelay() {
        let decider = MockVisualizeFireAnimationDecider()
        for scope in [Fire.BurningScope.tab, .window, .allWindows, .visits] {
            let burn = Fire.BurningData.specificDomains([], closesTabs: false, scope: scope)
            XCTAssertTrue(burn.shouldPlayFireAnimation(decider: decider))
            XCTAssertFalse(burn.shouldDelayShowingDialog(decider: decider))
        }
    }

    func testWhenPrivacyFeedBurns_thenOnlyInPageAnimationPlaysBeforeDelayedProgress() {
        let decider = MockVisualizeFireAnimationDecider()
        let burn = Fire.BurningData.specificDomains([], closesTabs: false, scope: .none)
        XCTAssertFalse(burn.shouldPlayFireAnimation(decider: decider))
        XCTAssertTrue(burn.shouldDelayShowingDialog(decider: decider))
    }

    @MainActor
    func testWhenSnapshotFireLoads_thenOriginalAssetWipesWithoutRestoringBurnedAreas() async throws {
        let loaded = await DefaultFireAnimationLoader.shared.load()
        let fire = try XCTUnwrap(loaded)
        XCTAssertEqual(DefaultFireAnimationLoader.assetName, "02_Fire_rebranded")
        XCTAssertEqual(fire.animation.duration, 40.0 / 30.0)
        XCTAssertEqual(fire.burnFronts.count, 41)
        let first = try XCTUnwrap(fire.burnFronts.first)
        let last = try XCTUnwrap(fire.burnFronts.last)
        XCTAssertTrue(first.allSatisfy { $0 < 0 }, "The complete snapshot and shadow must be visible before the fire arrives")
        XCTAssertTrue(last.allSatisfy { $0 == 1 }, "No snapshot or shadow may remain after the fire")
        XCTAssertTrue(fire.burnFronts.dropFirst().dropLast().contains { front in
            front.contains { $0 > 0 && $0 < 1 }
        }, "The wipe must advance through the window with the original flames")
        for (previous, next) in zip(fire.burnFronts, fire.burnFronts.dropFirst()) {
            XCTAssertEqual(previous.count, next.count)
            XCTAssertTrue(zip(previous, next).allSatisfy { $0 <= $1 }, "Burned areas must stay transparent as the flames recede")
        }
    }

    @MainActor
    func testWhenFeatureFlagIsOff_thenShouldShowFireAnimationIsTrue() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.isFireAnimationEnabled = true

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner()
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertTrue(sut.shouldShowFireAnimation)
    }

    @MainActor
    func testWhenFeatureFlagIsOnAndSettingIsOn_thenOpenFireWindowByDefaultIsTrue() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.shouldOpenFireWindowByDefault = true

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner()
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertTrue(sut.isOpenFireWindowByDefaultEnabled)
    }

    @MainActor
    func testWhenFeatureFlagIsOnAndSettingIsOff_thenOpenFireWindowByDefaultIsFalse() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.shouldOpenFireWindowByDefault = false

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner()
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertFalse(sut.isOpenFireWindowByDefaultEnabled)
    }
}
