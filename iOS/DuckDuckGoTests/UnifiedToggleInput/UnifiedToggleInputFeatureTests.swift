//
//  UnifiedToggleInputFeatureTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo
@testable import Core

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    // MARK: - Setup

    override func tearDown() {
        UserDefaults.app.removeObject(forKey: UnifiedToggleInputFeature.isFeatureFlagEnabledKey)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFeature(flagEnabled: Bool, isIphone: Bool) -> UnifiedToggleInputFeature {
        MockDevicePlatform.isIphone = isIphone
        let flags: [FeatureFlag] = flagEnabled ? [.unifiedToggleInput] : []
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: flags))
        return UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
    }

    // MARK: - Tests

    func test_isAvailable_whenFlagOnAndIphone() {
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOnButNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: true, isIphone: false).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffButIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffAndNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: false).isAvailable)
    }

    // MARK: - Snapshot semantics

    /// Mid-session flag flips (e.g. debug-menu toggle, remote-config update) must NOT
    /// change the captured value. The resolve writes the launch-time value into UserDefaults,
    /// and readers must never re-consult the live flagger — even if the same flagger object
    /// that was passed to resolve subsequently reports a different value. This is the whole
    /// point of the snapshot: a re-evaluating implementation would let the live flagger drag
    /// `isFeatureFlagEnabled` along with it and would fail this test.
    func test_isFeatureFlagEnabled_ignoresLiveFlaggerMutationAfterResolve() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput])
        UnifiedToggleInputFeature.resolve(using: flagger)
        let feature = UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
        XCTAssertTrue(feature.isFeatureFlagEnabled, "Precondition: snapshot is ON after resolve")

        // Simulate "the user toggled the flag off in the debug menu" by mutating the same
        // flagger that was passed to resolve. A re-evaluating implementation would observe
        // this and flip; the snapshot must not.
        flagger.enabledFeatureFlags = []
        XCTAssertFalse(flagger.isFeatureOn(.unifiedToggleInput),
                       "Sanity: the live flagger now reports the flag as off")
        XCTAssertTrue(feature.isFeatureFlagEnabled,
                      "Snapshot must ignore the post-resolve mutation on the same instance")
        XCTAssertTrue(UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self).isFeatureFlagEnabled,
                      "A fresh instance must read the same snapshot, not the mutated live flagger")

        // Only an explicit re-resolve (i.e. the next app launch) flips the snapshot.
        UnifiedToggleInputFeature.resolve(using: flagger)
        XCTAssertFalse(feature.isFeatureFlagEnabled,
                       "After re-resolving the snapshot must flip — otherwise resolve isn't doing its job")
    }
}
