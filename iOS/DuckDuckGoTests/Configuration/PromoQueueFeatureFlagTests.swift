//
//  PromoQueueFeatureFlagTests.swift
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

import Core
import PrivacyConfig
import Testing

@Suite("Promo Queue Feature Flag")
struct PromoQueueFeatureFlagTests {

    @Test("Promo queue is disabled by default")
    func whenInspectingPromoQueueThenDefaultIsDisabled() {
        guard case .disabled = FeatureFlag.promoQueue.defaultValue else {
            Issue.record("Expected promo queue to be disabled by default")
            return
        }
    }

    @Test("Promo queue maps to the remote-releasable promo queue subfeature")
    func whenInspectingPromoQueueThenSourceIsRemoteReleasablePromoQueueSubfeature() {
        guard case .remoteReleasable(let subfeature) = FeatureFlag.promoQueue.source else {
            Issue.record("Expected promo queue to use a remote-releasable source")
            return
        }

        #expect(subfeature as? PromoQueueSubfeature == .featureEnabled)
    }

    @Test("Promo queue supports local overriding")
    func whenInspectingPromoQueueThenLocalOverridingIsSupported() {
        #expect(FeatureFlag.promoQueue.supportsLocalOverriding)
    }
}
