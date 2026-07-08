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
