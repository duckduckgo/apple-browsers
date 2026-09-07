//
//  VPNSettingsEndpointPortOverrideTests.swift
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

final class VPNSettingsEndpointPortOverrideTests: XCTestCase {

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

    func testDefaultsToNilWhenUserHasNotChosen() {
        XCTAssertNil(settings.endpointPortOverride, "The endpoint port override must default to nil when the user hasn't chosen a value")
    }

    func testSettingValuePersists() {
        settings.endpointPortOverride = 51820

        XCTAssertEqual(settings.endpointPortOverride, 51820)
    }

    func testPublisherEmitsWhenValueChanges() {
        let expectation = expectation(description: "publisher emits the updated value")
        var received: UInt16??

        settings.endpointPortOverridePublisher
            .dropFirst() // Ignore the value emitted on subscription.
            .sink { value in
                received = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        settings.endpointPortOverride = 51820

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, 51820)
    }

    func testChangePublisherEmitsSetEndpointPortOverride() {
        let expectation = expectation(description: "changePublisher emits the endpoint port override change")
        var received: VPNSettings.Change?

        settings.changePublisher
            .sink { change in
                guard case .setEndpointPortOverride = change else { return }
                received = change
                expectation.fulfill()
            }
            .store(in: &cancellables)

        settings.endpointPortOverride = 51820

        wait(for: [expectation], timeout: 1.0)
        guard case .setEndpointPortOverride(let port)? = received else {
            return XCTFail("Expected .setEndpointPortOverride, got \(String(describing: received))")
        }
        XCTAssertEqual(port, 51820)
    }

    func testApplyingChangeUpdatesValue() {
        settings.apply(change: .setEndpointPortOverride(51820))

        XCTAssertEqual(settings.endpointPortOverride, 51820)
    }

    func testApplyingChangeWithNilClearsValue() {
        settings.endpointPortOverride = 51820

        settings.apply(change: .setEndpointPortOverride(nil))

        XCTAssertNil(settings.endpointPortOverride)
    }

    func testResetToDefaultsClearsValue() {
        settings.endpointPortOverride = 51820

        settings.resetToDefaults()

        XCTAssertNil(settings.endpointPortOverride)
    }
}
