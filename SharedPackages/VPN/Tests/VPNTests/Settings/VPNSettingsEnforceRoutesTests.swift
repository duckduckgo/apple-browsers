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

import Combine
import Foundation
import XCTest
@testable import VPN

final class VPNSettingsEnforceRoutesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: VPNSettings!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = VPNSettings(defaults: defaults)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        defaults.removePersistentDomain(forName: suiteName)
        settings = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToStrictWhenUserHasNotChosen() {
        XCTAssertTrue(settings.enforceRoutes, "Strict routing must default to true when the user hasn't chosen a value")
    }

    func testPublisherEmitsWhenValueChanges() {
        settings.enforceRoutes = true

        let expectation = expectation(description: "publisher emits the updated value")
        var received: Bool?

        settings.enforceRoutesPublisher
            .removeDuplicates() // KVO fires twice per change for this key; collapse to one.
            .dropFirst() // Ignore the value emitted on subscription.
            .sink { value in
                received = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        settings.enforceRoutes = false

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, false)
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
