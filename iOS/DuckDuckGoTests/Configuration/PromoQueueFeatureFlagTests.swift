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
import PrivacyConfigTestsUtils
import Testing

@Suite("Promo Queue Feature Flag")
struct PromoQueueFeatureFlagTests {

    // MARK: - Flag declaration

    @available(iOS 16, *)
    @Test("Promo queue is disabled by default", .timeLimit(.minutes(1)))
    func whenInspectingPromoQueueThenDefaultIsDisabled() {
        guard case .disabled = FeatureFlag.promoQueue.defaultValue else {
            Issue.record("Expected promo queue to be disabled by default")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Promo queue maps to the remote-releasable promo queue subfeature", .timeLimit(.minutes(1)))
    func whenInspectingPromoQueueThenSourceIsRemoteReleasablePromoQueueSubfeature() {
        guard case .remoteReleasable(let subfeature) = FeatureFlag.promoQueue.source else {
            Issue.record("Expected promo queue to use a remote-releasable source")
            return
        }

        #expect(subfeature as? PromoQueueSubfeature == .featureEnabled)
    }

    @available(iOS 16, *)
    @Test("Promo queue supports local overriding", .timeLimit(.minutes(1)))
    func whenInspectingPromoQueueThenLocalOverridingIsSupported() {
        #expect(FeatureFlag.promoQueue.supportsLocalOverriding)
    }

    @available(iOS 16, *)
    @Test("Embedded privacy config ships no promo queue entry, so the flag default is what decides", .timeLimit(.minutes(1)))
    func whenReadingEmbeddedPrivacyConfigThenPromoQueueSubfeatureIsMissing() throws {
        let privacyConfig = try makeEmbeddedPrivacyConfiguration()

        guard case .disabled(.featureMissing) = privacyConfig.stateFor(PromoQueueSubfeature.featureEnabled) else {
            Issue.record("Expected the embedded privacy config to omit the promo queue subfeature")
            return
        }
    }

    // MARK: - Helpers

    /// The privacy configuration the app actually ships, so "disabled by default" is asserted against
    /// production data rather than a hand-written stand-in.
    private func makeEmbeddedPrivacyConfiguration() throws -> AppPrivacyConfiguration {
        let data = try PrivacyConfigurationData(data: AppPrivacyConfigurationDataProvider().embeddedData)
        return makePrivacyConfiguration(data: data)
    }

    private func makePrivacyConfiguration(data: PrivacyConfigurationData) -> AppPrivacyConfiguration {
        AppPrivacyConfiguration(
            data: data,
            identifier: "promo-queue-tests",
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )
    }
}
