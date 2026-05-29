//
//  VPNSettingsEnforceRoutesTests.swift
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

import Foundation
import XCTest
@testable import VPN

final class VPNSettingsEnforceRoutesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: VPNSettings!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = VPNSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        settings = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testResetsRelaxedValueWhenStrictRoutingUnavailable() {
        settings.enforceRoutes = false

        settings.resetEnforceRoutesIfUnavailable(strictRoutingAvailable: false)

        XCTAssertEqual(settings.enforceRoutes, UserDefaults.enforceRoutesDefaultValue)
        XCTAssertTrue(settings.enforceRoutes, "The safe default is expected to be true")
    }

    func testPreservesRelaxedValueWhenStrictRoutingAvailable() {
        settings.enforceRoutes = false

        settings.resetEnforceRoutesIfUnavailable(strictRoutingAvailable: true)

        XCTAssertFalse(settings.enforceRoutes, "A relaxed value must survive while the feature is available")
    }

    func testLeavesDefaultValueUntouchedWhenUnavailable() {
        settings.enforceRoutes = UserDefaults.enforceRoutesDefaultValue

        settings.resetEnforceRoutesIfUnavailable(strictRoutingAvailable: false)

        XCTAssertEqual(settings.enforceRoutes, UserDefaults.enforceRoutesDefaultValue)
    }
}
