//
//  ModalPromptCoordinationFeatureFlagTests.swift
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

@Suite("Modal Prompt Coordination Feature Flag")
struct ModalPromptCoordinationFeatureFlagTests {

    // MARK: - Flag declaration

    @available(iOS 16, *)
    @Test("Modal prompt coordination is disabled by default", .timeLimit(.minutes(1)))
    func whenInspectingModalPromptCoordinationThenDefaultIsDisabled() {
        guard case .disabled = FeatureFlag.modalPromptCoordination.defaultValue else {
            Issue.record("Expected modal prompt coordination to be disabled by default")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Modal prompt coordination maps to the remote-releasable iOS browser config subfeature", .timeLimit(.minutes(1)))
    func whenInspectingModalPromptCoordinationThenSourceIsRemoteReleasableIOSBrowserConfigSubfeature() {
        guard case .remoteReleasable(let subfeature) = FeatureFlag.modalPromptCoordination.source else {
            Issue.record("Expected modal prompt coordination to use a remote-releasable source")
            return
        }

        #expect(subfeature as? iOSBrowserConfigSubfeature == .modalPromptCoordination)
    }

    @available(iOS 16, *)
    @Test("Modal prompt coordination supports local overriding", .timeLimit(.minutes(1)))
    func whenInspectingModalPromptCoordinationThenLocalOverridingIsSupported() {
        #expect(FeatureFlag.modalPromptCoordination.supportsLocalOverriding)
    }

    // MARK: - Embedded privacy configuration

    @available(iOS 16, *)
    @Test("Embedded privacy config ships no modal prompt coordination entry, so the flag default is what decides", .timeLimit(.minutes(1)))
    func whenReadingEmbeddedPrivacyConfigThenModalPromptCoordinationSubfeatureIsMissing() throws {
        let privacyConfig = try makeEmbeddedPrivacyConfiguration()

        // Assert the parent first: `iOSBrowserConfig` ships enabled, so the subfeature reading below is not the
        // parent kill-switch short-circuiting. The subfeature is genuinely absent from the shipped config, which
        // is what lets the flag's `.disabled` default decide.
        guard case .enabled = privacyConfig.stateFor(featureKey: .iOSBrowserConfig) else {
            Issue.record("Expected the embedded privacy config to enable the iOS browser config parent feature")
            return
        }

        guard case .disabled(.featureMissing) = privacyConfig.stateFor(iOSBrowserConfigSubfeature.modalPromptCoordination) else {
            Issue.record("Expected the embedded privacy config to omit the modal prompt coordination subfeature")
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
            identifier: "modal-prompt-coordination-tests",
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )
    }
}
