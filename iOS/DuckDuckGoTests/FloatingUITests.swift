//
//  FloatingUITests.swift
//  DuckDuckGoTests
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

import UIKit
import XCTest
@testable import Core
@testable import DuckDuckGo

final class FloatingUIManagerTests: XCTestCase {

    func testWhenFloatingUIAndUnifiedToggleInputAreEnabledOnIPhoneThenFloatingUIIsEnabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
            isPadProvider: { false },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertTrue(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIIsEnabledButUnifiedToggleInputIsUnavailableThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
            isPadProvider: { false },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: false)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIIsDisabledAndUnifiedToggleInputIsAvailableThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            isPadProvider: { false },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIAndUnifiedToggleInputAreEnabledOnIPadThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
            isPadProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }
}

final class FloatingUILayoutPolicyTests: XCTestCase {

    func testWhenTopAddressBarThenAdditionalSafeAreaInsetsApplyOmniBarHeightToTop() {
        let insets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .top,
            isUnifiedToggleInputAffectingLayout: false,
            omniBarHeight: 52,
            toolbarHeight: 44
        )

        XCTAssertEqual(insets, UIEdgeInsets(top: 52, left: 0, bottom: 0, right: 0))
    }

    func testWhenBottomAddressBarThenAdditionalSafeAreaInsetsApplyToolbarHeightToBottom() {
        let insets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .bottom,
            isUnifiedToggleInputAffectingLayout: false,
            omniBarHeight: 52,
            toolbarHeight: 44
        )

        XCTAssertEqual(insets, UIEdgeInsets(top: 0, left: 0, bottom: 44, right: 0))
    }

    func testWhenUnifiedToggleInputAffectsLayoutThenInsetsAreZero() {
        let topInsets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .top,
            isUnifiedToggleInputAffectingLayout: true,
            omniBarHeight: 52,
            toolbarHeight: 44
        )
        XCTAssertEqual(topInsets, .zero)

        let bottomInsets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .bottom,
            isUnifiedToggleInputAffectingLayout: true,
            omniBarHeight: 52,
            toolbarHeight: 44
        )
        XCTAssertEqual(bottomInsets, .zero)
    }
}
