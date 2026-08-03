//
//  PromoPresentationCoordinationFeatureFlagTests.swift
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

@Suite("Promo Presentation Coordination Feature Flag")
struct PromoPresentationCoordinationFeatureFlagTests {

    // MARK: - Flag declaration

    @available(iOS 16, *)
    @Test("Promo presentation coordination is disabled by default", .timeLimit(.minutes(1)))
    func whenInspectingPromoPresentationCoordinationThenDefaultIsDisabled() {
        guard case .disabled = FeatureFlag.promoPresentationCoordination.defaultValue else {
            Issue.record("Expected promo presentation coordination to be disabled by default")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Promo presentation coordination maps to the remote-releasable iOS browser config subfeature", .timeLimit(.minutes(1)))
    func whenInspectingPromoPresentationCoordinationThenSourceIsRemoteReleasableIOSBrowserConfigSubfeature() {
        guard case .remoteReleasable(let subfeature) = FeatureFlag.promoPresentationCoordination.source else {
            Issue.record("Expected promo presentation coordination to use a remote-releasable source")
            return
        }

        #expect(subfeature as? iOSBrowserConfigSubfeature == .promoPresentationCoordination)
    }

    @available(iOS 16, *)
    @Test("Promo presentation coordination supports local overriding", .timeLimit(.minutes(1)))
    func whenInspectingPromoPresentationCoordinationThenLocalOverridingIsSupported() {
        #expect(FeatureFlag.promoPresentationCoordination.supportsLocalOverriding)
    }

    // MARK: - Embedded privacy configuration

    @available(iOS 16, *)
    @Test("Embedded privacy config ships no promo presentation coordination entry, so the flag default is what decides", .timeLimit(.minutes(1)))
    func whenReadingEmbeddedPrivacyConfigThenPromoPresentationCoordinationSubfeatureIsMissing() throws {
        let privacyConfig = try makeEmbeddedPrivacyConfiguration()

        // Assert the parent first: `iOSBrowserConfig` ships enabled, so the subfeature reading below is not the
        // parent kill-switch short-circuiting. The subfeature is genuinely absent from the shipped config, which
        // is what lets the flag's `.disabled` default decide.
        guard case .enabled = privacyConfig.stateFor(featureKey: .iOSBrowserConfig) else {
            Issue.record("Expected the embedded privacy config to enable the iOS browser config parent feature")
            return
        }

        guard case .disabled(.featureMissing) = privacyConfig.stateFor(iOSBrowserConfigSubfeature.promoPresentationCoordination) else {
            Issue.record("Expected the embedded privacy config to omit the promo presentation coordination subfeature")
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
            identifier: "promo-presentation-coordination-tests",
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )
    }
}
