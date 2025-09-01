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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DefaultVisualizeFireSettingsDeciderTests: XCTestCase {

    @MainActor
    func testWhenFeatureFlagIsOnAndFireAnimationIsDisabled_thenShouldShowFireAnimationIsFalse() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.isFireAnimationEnabled = false
        featureFlagger.enabledFeatureFlags = [.disableFireAnimation]

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertFalse(sut.shouldShowFireAnimation)
    }

    @MainActor
    func testWhenFeatureFlagIsOnAndFireAnimationIsEnabled_thenShouldShowFireAnimationIsTrue() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.isFireAnimationEnabled = true
        featureFlagger.enabledFeatureFlags = [.disableFireAnimation]

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertTrue(sut.shouldShowFireAnimation)
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
            pixelFiring: nil
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertTrue(sut.shouldShowFireAnimation)
    }

    @MainActor
    func testWhenFeatureFlagIsOnAndSettingIsOn_thenOpenFireWindowByDefaultIsTrue() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.shouldOpenFireWindowbyDefault = true
        featureFlagger.enabledFeatureFlags = [.openFireWindowByDefault]

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertTrue(sut.isOpenFireWindowByDefaultEnabled)
    }

    @MainActor
    func testWhenFeatureFlagIsOnAndSettingIsOff_thenOpenFireWindowByDefaultIsFalse() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.shouldOpenFireWindowbyDefault = false
        featureFlagger.enabledFeatureFlags = [.openFireWindowByDefault]

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertFalse(sut.isOpenFireWindowByDefaultEnabled)
    }

    @MainActor
    func testWhenFeatureFlagIsOff_thenOpenFireWindowByDefaultIsFalse() {
        let persistor = MockFireButtonPreferencesPersistor()
        let featureFlagger = MockFeatureFlagger()

        persistor.shouldOpenFireWindowbyDefault = true
        featureFlagger.enabledFeatureFlags = []

        let dataClearingPreferences: DataClearingPreferences = .init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: nil
        )

        let sut = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)

        XCTAssertFalse(sut.isOpenFireWindowByDefaultEnabled)
    }
}
