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
import Foundation
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import Testing

@Suite("Promo Queue Feature Flag")
struct PromoQueueFeatureFlagTests {

    /// `DefaultFeatureFlagger` trips a debug assertion when it is built under a unit-test run type,
    /// which this target is (its product is `UnitTests.xctest`), unless this opt-in is present.
    /// The real flagger is required here: a mock flagger cannot exercise the privacy-config
    /// resolution path that decides whether `.promoQueue` is on, which is the whole point of these
    /// tests. The variable is deliberately never unset — clearing it would race with the parallel
    /// test runner, and all it does is relax a debug assertion.
    init() {
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)
    }

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

    // MARK: - Resolution through the privacy configuration

    /// Guards the test below from passing for the wrong reason: `.featureMissing` is the only state
    /// in which `isSubfeatureEnabled` consults the flag's `defaultValue` at all. If the promo queue
    /// entry ever lands in the embedded config, the `.disabled` default stops being what decides.
    @available(iOS 16, *)
    @Test("Embedded privacy config ships no promo queue entry, so the flag default is what decides", .timeLimit(.minutes(1)))
    func whenReadingEmbeddedPrivacyConfigThenPromoQueueSubfeatureIsMissing() throws {
        let privacyConfig = try makeEmbeddedPrivacyConfiguration()

        guard case .disabled(.featureMissing) = privacyConfig.stateFor(PromoQueueSubfeature.featureEnabled) else {
            Issue.record("Expected the embedded privacy config to omit the promo queue subfeature")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Promo queue resolves to off against the privacy config the app ships with", .timeLimit(.minutes(1)))
    func whenPrivacyConfigOmitsPromoQueueThenFeatureIsOff() throws {
        let featureFlagger = makeFeatureFlagger(privacyConfig: try makeEmbeddedPrivacyConfiguration())

        #expect(featureFlagger.isFeatureOn(.promoQueue) == false)
    }

    @available(iOS 16, *)
    @Test("Promo queue resolves to on once the privacy config enables the subfeature", .timeLimit(.minutes(1)))
    func whenPrivacyConfigEnablesPromoQueueSubfeatureThenFeatureIsOn() throws {
        let privacyConfig = try makePrivacyConfiguration(promoQueueSubfeatureState: PrivacyConfigurationData.State.enabled)
        let featureFlagger = makeFeatureFlagger(privacyConfig: privacyConfig)

        #expect(featureFlagger.isFeatureOn(.promoQueue))
    }

    @available(iOS 16, *)
    @Test("Promo queue resolves to off when the privacy config disables the subfeature", .timeLimit(.minutes(1)))
    func whenPrivacyConfigDisablesPromoQueueSubfeatureThenFeatureIsOff() throws {
        let privacyConfig = try makePrivacyConfiguration(promoQueueSubfeatureState: PrivacyConfigurationData.State.disabled)
        let featureFlagger = makeFeatureFlagger(privacyConfig: privacyConfig)

        #expect(featureFlagger.isFeatureOn(.promoQueue) == false)
    }

    // MARK: - Local overriding

    /// The behavioural counterpart to `whenInspectingPromoQueueThenLocalOverridingIsSupported`: were
    /// `.promoQueue`'s `Config` to pass `supportsLocalOverriding: false`, `FeatureFlagLocalOverrides`
    /// would refuse both the toggle and the lookup, and the flag would stay off.
    @available(iOS 16, *)
    @Test("An internal user can turn promo queue on with a local override", .timeLimit(.minutes(1)))
    func whenInternalUserOverridesPromoQueueThenFeatureIsOn() throws {
        let privacyConfigManager = MockPrivacyConfigurationManager()
        privacyConfigManager.privacyConfig = try makeEmbeddedPrivacyConfiguration()

        let localOverrides = FeatureFlagLocalOverrides(
            keyValueStore: MockKeyValueStore(),
            actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        let featureFlagger = DefaultFeatureFlagger(
            internalUserDecider: MockInternalUserDecider(isInternalUser: true),
            privacyConfigManager: privacyConfigManager,
            localOverrides: localOverrides,
            experimentManager: nil,
            for: FeatureFlag.self
        )

        #expect(featureFlagger.isFeatureOn(.promoQueue) == false)

        localOverrides.toggleOverride(for: FeatureFlag.promoQueue)

        #expect(featureFlagger.isFeatureOn(.promoQueue))
    }

    // MARK: - Helpers

    private func makeFeatureFlagger(privacyConfig: PrivacyConfiguration) -> DefaultFeatureFlagger {
        let privacyConfigManager = MockPrivacyConfigurationManager()
        privacyConfigManager.privacyConfig = privacyConfig

        return DefaultFeatureFlagger(
            internalUserDecider: MockInternalUserDecider(),
            privacyConfigManager: privacyConfigManager,
            experimentManager: nil
        )
    }

    /// The privacy configuration the app actually ships, so "disabled by default" is asserted against
    /// production data rather than a hand-written stand-in.
    private func makeEmbeddedPrivacyConfiguration() throws -> AppPrivacyConfiguration {
        let data = try PrivacyConfigurationData(data: AppPrivacyConfigurationDataProvider().embeddedData)
        return makePrivacyConfiguration(data: data)
    }

    private func makePrivacyConfiguration(promoQueueSubfeatureState: String) throws -> AppPrivacyConfiguration {
        let subfeature = try #require(PrivacyConfigurationData.PrivacyFeature.Feature(json: ["state": promoQueueSubfeatureState]))
        let promoQueueFeature = PrivacyConfigurationData.PrivacyFeature(
            state: PrivacyConfigurationData.State.enabled,
            exceptions: [],
            features: [PromoQueueSubfeature.featureEnabled.rawValue: subfeature]
        )
        let data = PrivacyConfigurationData(
            features: [PrivacyFeature.promoQueue.rawValue: promoQueueFeature],
            unprotectedTemporary: [],
            trackerAllowlist: [:]
        )
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
