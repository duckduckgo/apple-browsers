//
//  FeatureFlagsTests.swift
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

import FeatureFlags_iOS
import Foundation
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest

final class FeatureFlagsTests: XCTestCase {

    func testTabSwitcherSwipeUpGestureIsDefaultDisabledRemoteReleasableAndLocallyOverridable() {
        let flag = FeatureFlag.tabSwitcherSwipeUpGesture
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? iOSBrowserConfigSubfeature, .tabSwitcherSwipeUpGesture)
        XCTAssertEqual(subfeature.parent, .iOSBrowserConfig)
        XCTAssertEqual(subfeature.rawValue, "tabSwitcherSwipeUpGesture")
        guard case .disabled = flag.defaultValue else {
            XCTFail("Expected disabled default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testTabSwitcherSwipeUpGestureDefaultsOffAndFollowsRemoteChanges() {
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)
        defer { unsetenv("TESTS_FEATUREFLAGGER_MODE") }

        let manager = makeSwipeUpConfigurationManager()
        let flagger = DefaultFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: false),
                                           privacyConfigManager: manager,
                                           experimentManager: nil)

        XCTAssertFalse(flagger.isFeatureOn(for: FeatureFlag.tabSwitcherSwipeUpGesture))
        manager.reload(etag: "enabled", data: swipeUpConfigurationData(state: "enabled"))
        XCTAssertTrue(flagger.isFeatureOn(for: FeatureFlag.tabSwitcherSwipeUpGesture))
        manager.reload(etag: "disabled", data: swipeUpConfigurationData(state: "disabled"))
        XCTAssertFalse(flagger.isFeatureOn(for: FeatureFlag.tabSwitcherSwipeUpGesture))
        manager.reload(etag: "enabled-again", data: swipeUpConfigurationData(state: "enabled"))
        XCTAssertTrue(flagger.isFeatureOn(for: FeatureFlag.tabSwitcherSwipeUpGesture))
        manager.reload(etag: "removed", data: swipeUpConfigurationData())
        XCTAssertFalse(flagger.isFeatureOn(for: FeatureFlag.tabSwitcherSwipeUpGesture))
    }

    func testTabSwitcherSwipeUpGestureSupportsChangingAndClearingLocalOverrides() throws {
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)
        defer { unsetenv("TESTS_FEATUREFLAGGER_MODE") }

        let suiteName = "FeatureFlagsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let overrides = FeatureFlagLocalOverrides(keyValueStore: defaults,
                                                 actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>())
        let manager = makeSwipeUpConfigurationManager()
        let flagger = DefaultFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                           privacyConfigManager: manager,
                                           localOverrides: overrides,
                                           experimentManager: nil,
                                           for: FeatureFlag.self)
        let flag = FeatureFlag.tabSwitcherSwipeUpGesture

        overrides.toggleOverride(for: flag)
        XCTAssertTrue(flagger.isFeatureOn(for: flag))
        overrides.clearOverride(for: flag)
        XCTAssertFalse(flagger.isFeatureOn(for: flag))

        manager.reload(etag: "enabled", data: swipeUpConfigurationData(state: "enabled"))
        XCTAssertTrue(flagger.isFeatureOn(for: flag))
        overrides.toggleOverride(for: flag)
        XCTAssertFalse(flagger.isFeatureOn(for: flag))
        overrides.clearOverride(for: flag)
        XCTAssertTrue(flagger.isFeatureOn(for: flag))
    }

    private func makeSwipeUpConfigurationManager() -> PrivacyConfigurationManager {
        PrivacyConfigurationManager(fetchedETag: nil,
                                    fetchedData: nil,
                                    embeddedDataProvider: MockEmbeddedDataProvider(data: swipeUpConfigurationData(), etag: "test"),
                                    localProtection: MockDomainsProtectionStore(),
                                    internalUserDecider: MockInternalUserDecider())
    }

    private func swipeUpConfigurationData(state: String? = nil) -> Data {
        let subfeature = state.map { "\"tabSwitcherSwipeUpGesture\": {\"state\": \"\($0)\"}" } ?? ""
        return """
        {
            "features": {
                "\(PrivacyFeature.iOSBrowserConfig.rawValue)": {"state": "enabled", "features": {\(subfeature)}}
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
    }

    func testAttachmentPrivacyUsesRemoteKillSwitchAndInternalOnlyDefault() {
        let flag = FeatureFlag.unifiedToggleInputAttachmentPrivacy
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? AIChatSubfeature, .unifiedToggleInputAttachmentPrivacy)
        XCTAssertEqual(subfeature.parent, .aiChat)
        guard case .internalOnly = flag.defaultValue else {
            XCTFail("Expected internal-only default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testPastedTextUsesItsOwnRemoteKillSwitchAndInternalOnlyDefault() {
        let flag = FeatureFlag.unifiedToggleInputPastedText
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? AIChatSubfeature, .unifiedToggleInputPastedText)
        XCTAssertEqual(subfeature.parent, .aiChat)
        XCTAssertEqual(subfeature.rawValue, "unifiedToggleInputPastedText")
        guard case .internalOnly = flag.defaultValue else {
            XCTFail("Expected internal-only default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testIPadAttachmentPrivacyUsesItsOwnRemoteKillSwitchAndInternalOnlyDefault() {
        let flag = FeatureFlag.aiChatAttachmentPrivacyIPad
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? AIChatSubfeature, .iPadAttachmentPrivacy)
        XCTAssertEqual(subfeature.parent, .aiChat)
        XCTAssertEqual(subfeature.rawValue, "iPadAttachmentPrivacy")
        guard case .internalOnly = flag.defaultValue else {
            XCTFail("Expected internal-only default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testAddressBarRecentChatsUsesItsOwnRemoteKillSwitchAndIsEnabledByDefault() {
        let flag = FeatureFlag.aiChatAddressBarRecentChats
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? AIChatSubfeature, .addressBarRecentChats)
        XCTAssertEqual(subfeature.parent, .aiChat)
        XCTAssertEqual(subfeature.rawValue, "addressBarRecentChats")
        guard case .enabled = flag.defaultValue else {
            XCTFail("Expected enabled default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testChromeMenuButtonIPadUsesItsOwnRemoteFlagAndIsInternalOnlyByDefault() {
        let flag = FeatureFlag.aiChatChromeMenuButtonIPad
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? AIChatSubfeature, .iPadChromeMenuButton)
        XCTAssertEqual(subfeature.parent, .aiChat)
        XCTAssertEqual(subfeature.rawValue, "iPadChromeMenuButton")
        guard case .internalOnly = flag.defaultValue else {
            XCTFail("Expected internal-only default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testContextualSidebarIPadUsesItsOwnRemoteFlagAndIsInternalOnlyByDefault() {
        let flag = FeatureFlag.ipadAIChatContextSidebar
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? AIChatSubfeature, .iPadContextualSidebar)
        XCTAssertEqual(subfeature.parent, .aiChat)
        XCTAssertEqual(subfeature.rawValue, "iPadContextualSidebar")
        guard case .internalOnly = flag.defaultValue else {
            XCTFail("Expected internal-only default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testWhenSubfeatureIsMissingThenProvidedDefaultValueIsReturned() {
        let configData = """
        {
            "features": {},
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
        let manager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: MockEmbeddedDataProvider(data: configData, etag: "test"),
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider())
        let config = manager.privacyConfig
        let subfeature = iOSBrowserConfigSubfeature.intentionallyLocalOnlySubfeatureForTests

        XCTAssertFalse(config.isSubfeatureEnabled(subfeature, defaultValue: false))
        XCTAssertTrue(config.isSubfeatureEnabled(subfeature, defaultValue: true))
    }

    func testWhenReadingIOSBrowserConfigSubfeatureThenParentAndRawValueAreStable() {
        let subfeature = iOSBrowserConfigSubfeature.searchTokenExperimentV4

        XCTAssertEqual(subfeature.parent, .iOSBrowserConfig)
        XCTAssertEqual(subfeature.rawValue, "searchTokenExperimentV4")
    }

    func testWhenReadingSearchTokenFeatureFlagThenSourceAndCohortUseSearchTokenConfiguration() {
        guard case let .remoteReleasable(subfeature) = FeatureFlag.searchTokenExperimentV4.source else {
            XCTFail("Expected remote-releasable source")
            return
        }

        XCTAssertEqual((subfeature as? iOSBrowserConfigSubfeature)?.rawValue,
                       iOSBrowserConfigSubfeature.searchTokenExperimentV4.rawValue)
        XCTAssertEqual(FeatureFlag.searchTokenExperimentV4.cohortType.map(ObjectIdentifier.init),
                       ObjectIdentifier(FeatureFlag.SearchTokenExperimentCohort.self))
    }

    func testTabEvictionFlagsAreDefaultEnabledRemoteReleasableAndLocallyOverridable() {
        let cases: [(FeatureFlag, iOSBrowserConfigSubfeature)] = [
            (.tabEvictionOnMemoryWarning, .tabEvictionOnMemoryWarning),
            (.tabLRUEviction, .tabLRUEviction)
        ]

        for (flag, expectedSubfeature) in cases {
            guard case let .remoteReleasable(subfeature) = flag.source else {
                XCTFail("Expected remote-releasable source for \(flag.rawValue)")
                continue
            }
            XCTAssertEqual((subfeature as? iOSBrowserConfigSubfeature)?.rawValue, expectedSubfeature.rawValue)
            guard case .enabled = flag.defaultValue else {
                XCTFail("Expected enabled default for \(flag.rawValue)")
                continue
            }
            XCTAssertTrue(flag.supportsLocalOverriding)
        }
    }

    func testLegacyDeviceRenamePatchFlagIsDefaultEnabledAndRemoteReleasable() {
        let flag = FeatureFlag.syncCanUsePatchEndpointForLegacyDeviceRename
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }

        XCTAssertEqual((subfeature as? SyncSubfeature)?.rawValue,
                       SyncSubfeature.canUsePatchEndpointForLegacyDeviceRename.rawValue)
        guard case .enabled = flag.defaultValue else {
            XCTFail("Expected enabled default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testAlwaysShowKeyboardOnNewTabPageIsDefaultDisabledRemoteReleasableAndLocallyOverridable() {
        let flag = FeatureFlag.alwaysShowKeyboardOnNewTabPage
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? iOSBrowserConfigSubfeature, .alwaysShowKeyboardOnNewTabPage)
        XCTAssertEqual(subfeature.parent, .iOSBrowserConfig)
        XCTAssertEqual(subfeature.rawValue, "alwaysShowKeyboardOnNewTabPage")
        guard case .disabled = flag.defaultValue else {
            XCTFail("Expected disabled default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }
}
