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
import PrivacyConfig

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        resetState()
    }

    override func tearDown() {
        resetState()
        super.tearDown()
    }

    private func resetState() {
        UnifiedToggleInputFeature.resetPersistedStateForTesting()
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: []),
                                          devicePlatform: MockDevicePlatform.self)
        MockDevicePlatform.isIphone = false
    }

    // MARK: - Helpers

    /// Mirrors a launch: snapshots the given flag state for the given device.
    private func resolve(featureOn: Bool, includeNewUsers: Bool, isIphone: Bool) {
        MockDevicePlatform.isIphone = isIphone
        var flags: [FeatureFlag] = []
        if featureOn { flags.append(.unifiedToggleInput) }
        if includeNewUsers { flags.append(.unifiedToggleInputIncludeNewUsers) }
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: flags),
                                          devicePlatform: MockDevicePlatform.self)
    }

    private func makeFeature(isIphone: Bool) -> UnifiedToggleInputFeature {
        MockDevicePlatform.isIphone = isIphone
        return UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
    }

    // MARK: - Feature flag × device

    func test_isAvailable_whenFlagOnAndIphone() {
        resolve(featureOn: true, includeNewUsers: true, isIphone: true)
        XCTAssertTrue(makeFeature(isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOnButNotIphone() {
        resolve(featureOn: true, includeNewUsers: true, isIphone: false)
        XCTAssertFalse(makeFeature(isIphone: false).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffButIphone() {
        resolve(featureOn: false, includeNewUsers: true, isIphone: true)
        XCTAssertFalse(makeFeature(isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffAndNotIphone() {
        resolve(featureOn: false, includeNewUsers: true, isIphone: false)
        XCTAssertFalse(makeFeature(isIphone: false).isAvailable)
    }

    // MARK: - New-user cutoff

    /// A new iPhone user with both flags on gets UTI, and the grant is sticky: flipping the
    /// new-user cutoff off afterwards must NOT take UTI away from them.
    func test_grantedUser_keepsUTI_afterNewUserCutoff() {
        resolve(featureOn: true, includeNewUsers: true, isIphone: true)
        XCTAssertTrue(makeFeature(isIphone: true).isAvailable, "Precondition: new user is granted UTI")

        resolve(featureOn: true, includeNewUsers: false, isIphone: true)
        XCTAssertTrue(makeFeature(isIphone: true).isAvailable,
                      "A granted user must keep UTI after the new-user cutoff")
    }

    /// A user who has never been granted UTI must not receive it once the cutoff is active, and
    /// re-launching must keep them out (no grant was ever recorded).
    func test_newUser_afterCutoff_neverGetsUTI() {
        resolve(featureOn: true, includeNewUsers: false, isIphone: true)
        XCTAssertFalse(makeFeature(isIphone: true).isAvailable)

        resolve(featureOn: true, includeNewUsers: false, isIphone: true)
        XCTAssertFalse(makeFeature(isIphone: true).isAvailable,
                       "An un-granted user stays out across launches while the cutoff is active")
    }

    /// The `unifiedToggleInput` flag remains a full kill switch: turning it off revokes UTI even
    /// from a user who was previously granted.
    func test_featureFlagOff_revokesEvenGrantedUser() {
        resolve(featureOn: true, includeNewUsers: true, isIphone: true)
        XCTAssertTrue(makeFeature(isIphone: true).isAvailable, "Precondition: user is granted UTI")

        resolve(featureOn: false, includeNewUsers: true, isIphone: true)
        XCTAssertFalse(makeFeature(isIphone: true).isAvailable,
                       "Turning the feature flag off removes UTI from everyone, including granted users")
    }

    /// Exercises the device guard on grant-recording. The first launch is eligible by flags
    /// (`includeNewUsers` on) but runs on a non-iPhone, so the grant must be blocked solely by the
    /// `&& devicePlatform.isIphone` guard. The second launch — now an iPhone with the cutoff active —
    /// would return `isAvailable == true` if a grant had leaked through on the non-iPhone launch, so
    /// asserting `false` here proves the device guard held. (Drop the guard and this test fails.)
    func test_nonIphone_doesNotRecordGrant() {
        resolve(featureOn: true, includeNewUsers: true, isIphone: false)
        XCTAssertFalse(makeFeature(isIphone: false).isAvailable, "Precondition: non-iPhone never shows UTI")

        resolve(featureOn: true, includeNewUsers: false, isIphone: true)
        XCTAssertFalse(makeFeature(isIphone: true).isAvailable,
                       "No grant was recorded on the non-iPhone launch, so the new-user cutoff now excludes it")
    }

    // MARK: - Snapshot semantics

    /// Mid-session flag flips must not change availability. Resolve writes the launch-time flag
    /// value into UserDefaults, while readers still apply the device availability gate.
    func test_isAvailable_usesLaunchResolvedFlagSnapshot() {
        MockDevicePlatform.isIphone = true
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput, .unifiedToggleInputIncludeNewUsers])
        UnifiedToggleInputFeature.resolve(using: flagger, devicePlatform: MockDevicePlatform.self)
        let feature = UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
        XCTAssertTrue(feature.isAvailable, "Precondition: availability is ON after resolve")

        flagger.enabledFeatureFlags = []
        XCTAssertFalse(flagger.isFeatureOn(.unifiedToggleInput),
                       "Sanity: the live flagger now reports the flag as off")
        XCTAssertTrue(feature.isAvailable,
                      "Snapshot must ignore the post-resolve mutation on the same instance")
        XCTAssertTrue(UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self).isAvailable,
                      "A fresh instance must read the same snapshot, not the mutated live flagger")

        UnifiedToggleInputFeature.resolve(using: flagger, devicePlatform: MockDevicePlatform.self)
        XCTAssertFalse(feature.isAvailable,
                       "After re-resolving the snapshot must flip — otherwise resolve isn't doing its job")
    }
}
