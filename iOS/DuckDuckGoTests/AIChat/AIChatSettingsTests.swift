//
//  AIChatSettingsTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import Core
@testable import DuckDuckGo
import PrivacyConfig
import Combine
import AIChat
import Persistence
import PersistenceTestingUtils

class AIChatSettingsTests: XCTestCase {

    private var mockPrivacyConfigurationManager: PrivacyConfigurationManagerMock!
    private var mockKeyValueStore: KeyValueStoring!
    private var mockNotificationCenter: NotificationCenter!
    private var mockFeatureFlagger: FeatureFlagger!
    private var mockAIChatDebugSettings: MockAIChatDebugSettings!

    override func setUp() {
        super.setUp()
        mockPrivacyConfigurationManager = PrivacyConfigurationManagerMock()
        mockKeyValueStore = MockKeyValueStore()
        mockNotificationCenter = NotificationCenter()
        mockFeatureFlagger = MockFeatureFlagger()
        mockAIChatDebugSettings = MockAIChatDebugSettings()
    }

    override func tearDown() {
        mockPrivacyConfigurationManager = nil
        mockKeyValueStore = nil
        mockNotificationCenter = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    func testAIChatURLReturnsDefaultWhenRemoteSettingsMissing() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter)

        (mockPrivacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock)?.settings = [:]

        let expectedURL = URL(string: AIChatSettings.SettingsValue.aiChatURL.defaultValue)!
        XCTAssertEqual(settings.aiChatURL, expectedURL)
    }

    func testAIChatURLReturnsRemoteSettingWhenAvailable() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter)

        let remoteURL = "https://example.com/ai-chat"
        (mockPrivacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock)?.settings = [
            .aiChat: [AIChatSettings.SettingsValue.aiChatURL.rawValue: remoteURL]
        ]

        XCTAssertEqual(settings.aiChatURL, URL(string: remoteURL))
    }

    func testAIChatURLReturnsOverriddenSettingWhenAvailable() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter)

        let override = "https://override.com/ai-chat"
        mockAIChatDebugSettings.customURL = override

        XCTAssertEqual(settings.aiChatURL, URL(string: override))
    }

    func testEnableAIChatBrowsingMenuUserSettings() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter)

        settings.enableAIChatBrowsingMenuUserSettings(enable: false)
        XCTAssertFalse(settings.isAIChatBrowsingMenuUserSettingsEnabled)

        settings.enableAIChatBrowsingMenuUserSettings(enable: true)
        XCTAssertTrue(settings.isAIChatBrowsingMenuUserSettingsEnabled)
    }

    func testEnableAIChatAddressBarUserSettings() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter)

        settings.enableAIChatAddressBarUserSettings(enable: false)
        XCTAssertFalse(settings.isAIChatAddressBarUserSettingsEnabled)

        settings.enableAIChatAddressBarUserSettings(enable: true)
        XCTAssertTrue(settings.isAIChatAddressBarUserSettingsEnabled)
    }

    func testNotificationPostedWhenSettingsChange() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter)

        let expectation = self.expectation(description: "Notification should be posted")

        let observer = mockNotificationCenter.addObserver(forName: .aiChatSettingsChanged, object: nil, queue: nil) { _ in
            expectation.fulfill()
        }

        settings.enableAIChatBrowsingMenuUserSettings(enable: false)
        waitForExpectations(timeout: 1, handler: nil)
        mockNotificationCenter.removeObserver(observer)
    }

    func testEnableAutomaticContextAttachment_WhenFeatureFlagOn_DefaultsToTrue() {
        // Given
        (mockFeatureFlagger as? MockFeatureFlagger)?.enabledFeatureFlags = [.aiChatAutoAttachContextByDefault]

        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)

        // Then
        XCTAssertTrue(settings.isAutomaticContextAttachmentEnabled)

        // When
        settings.enableAutomaticContextAttachment(enable: false)

        // Then
        XCTAssertFalse(settings.isAutomaticContextAttachmentEnabled)

        // When
        settings.enableAutomaticContextAttachment(enable: true)

        // Then
        XCTAssertTrue(settings.isAutomaticContextAttachmentEnabled)
    }

    func testEnableAutomaticContextAttachment_WhenFeatureFlagOff_DefaultsToFalse() {
        // Given
        (mockFeatureFlagger as? MockFeatureFlagger)?.enabledFeatureFlags = []

        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)

        // Then
        XCTAssertFalse(settings.isAutomaticContextAttachmentEnabled)

        // When
        settings.enableAutomaticContextAttachment(enable: true)

        // Then
        XCTAssertTrue(settings.isAutomaticContextAttachmentEnabled)
    }

    // MARK: - Navigation Bar shortcut (iPad Duck.ai chrome)

    func testIsAIChatNavigationBarUserSettingsEnabled_returnsTrueByDefault_whenAIChatIsEnabled() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        // Pin the AI Chat global gate explicitly so the test only depends on
        // showAIChatNavigationBarDefaultValue, not the isAIChatEnabled default.
        settings.enableAIChat(enable: true)

        XCTAssertTrue(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testEnableAIChatNavigationBarUserSettings_persistsValue() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)

        settings.enableAIChatNavigationBarUserSettings(enable: false)
        XCTAssertFalse(settings.isAIChatNavigationBarUserSettingsEnabled)

        settings.enableAIChatNavigationBarUserSettings(enable: true)
        XCTAssertTrue(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testIsAIChatNavigationBarUserSettingsEnabled_returnsFalse_whenAIChatGloballyDisabled() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        settings.enableAIChatNavigationBarUserSettings(enable: true)
        settings.enableAIChat(enable: false)

        XCTAssertFalse(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testEnableAIChatNavigationBarUserSettings_postsNotification() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)

        let expectation = self.expectation(description: "Notification posted on Navigation Bar setting change")
        let observer = mockNotificationCenter.addObserver(forName: .aiChatSettingsChanged, object: nil, queue: nil) { _ in
            expectation.fulfill()
        }

        settings.enableAIChatNavigationBarUserSettings(enable: false)
        waitForExpectations(timeout: 1, handler: nil)
        mockNotificationCenter.removeObserver(observer)
    }

    // MARK: - DuckAIChromeShortcutVisibility

    func testDuckAIChromeShortcutVisibility_settingsRowVisible_onIPad_whenFlagOn() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        XCTAssertTrue(DuckAIChromeShortcutVisibility.isSettingsRowVisible(isIPad: true, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_settingsRowHidden_onIPhone_evenWhenFlagOn() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isSettingsRowVisible(isIPad: false, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_settingsRowHidden_onIPad_whenFlagOff() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isSettingsRowVisible(isIPad: true, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_settingsRowHidden_onIPhone_whenFlagOff() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isSettingsRowVisible(isIPad: false, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_chromeButtonVisible_whenFlagOn_andSettingOn() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        XCTAssertTrue(DuckAIChromeShortcutVisibility.isChromeButtonVisible(
            featureFlagger: flagger,
            isAIChatNavigationBarUserSettingsEnabled: true
        ))
    }

    func testDuckAIChromeShortcutVisibility_chromeButtonHidden_whenFlagOff() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isChromeButtonVisible(
            featureFlagger: flagger,
            isAIChatNavigationBarUserSettingsEnabled: true
        ))
    }

    func testDuckAIChromeShortcutVisibility_chromeButtonHidden_whenSettingOff() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isChromeButtonVisible(
            featureFlagger: flagger,
            isAIChatNavigationBarUserSettingsEnabled: false
        ))
    }

    // MARK: - DuckAIChromeShortcutVisibility — Address Bar row / button

    func testDuckAIChromeShortcutVisibility_addressBarRowHidden_whenNavigationBarRowIsShown() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isAddressBarRowVisible(isIPad: true, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_addressBarRowVisible_onIPhone_evenWhenFlagOn() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        XCTAssertTrue(DuckAIChromeShortcutVisibility.isAddressBarRowVisible(isIPad: false, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_addressBarRowVisible_onIPad_whenFlagOff() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        XCTAssertTrue(DuckAIChromeShortcutVisibility.isAddressBarRowVisible(isIPad: true, featureFlagger: flagger))
    }

    func testDuckAIChromeShortcutVisibility_addressBarButtonHidden_onIPad_atLargeWidth() {
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isAddressBarButtonVisibleOnIPad(
            isLargeWidth: true,
            isAIChatNavigationBarUserSettingsEnabled: true
        ))
    }

    func testDuckAIChromeShortcutVisibility_addressBarButtonVisible_onIPad_atNarrowWidth_whenSettingOn() {
        XCTAssertTrue(DuckAIChromeShortcutVisibility.isAddressBarButtonVisibleOnIPad(
            isLargeWidth: false,
            isAIChatNavigationBarUserSettingsEnabled: true
        ))
    }

    func testDuckAIChromeShortcutVisibility_addressBarButtonHidden_onIPad_atNarrowWidth_whenSettingOff() {
        XCTAssertFalse(DuckAIChromeShortcutVisibility.isAddressBarButtonVisibleOnIPad(
            isLargeWidth: false,
            isAIChatNavigationBarUserSettingsEnabled: false
        ))
    }

    // MARK: - Address Bar → Navigation Bar migration

    func testMigration_preservesAddressBarOff_asNavigationBarOff() {
        mockKeyValueStore.set(false, forKey: LegacyAiChatUserDefaultsKeys.showAIChatAddressBarKey)

        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        settings.enableAIChat(enable: true)

        XCTAssertFalse(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testMigration_doesNothing_whenAddressBarWasOn() {
        mockKeyValueStore.set(true, forKey: LegacyAiChatUserDefaultsKeys.showAIChatAddressBarKey)

        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        settings.enableAIChat(enable: true)

        // No prior Nav Bar value, no migration override — falls through to default (true).
        XCTAssertTrue(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testMigration_doesNothing_whenAddressBarValueNeverSet() {
        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        settings.enableAIChat(enable: true)

        XCTAssertTrue(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testMigration_doesNotOverrideExplicitNavigationBarValue() {
        // User had Address Bar off AND Nav Bar already explicitly set to true — keep Nav Bar.
        mockKeyValueStore.set(false, forKey: LegacyAiChatUserDefaultsKeys.showAIChatAddressBarKey)
        mockKeyValueStore.set(true, forKey: LegacyAiChatUserDefaultsKeys.showAIChatNavigationBarKey)

        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        settings.enableAIChat(enable: true)

        XCTAssertTrue(settings.isAIChatNavigationBarUserSettingsEnabled)
    }

    func testMigration_isOneShot_subsequentAddressBarToggleDoesNotResetNavigationBar() {
        mockKeyValueStore.set(false, forKey: LegacyAiChatUserDefaultsKeys.showAIChatAddressBarKey)

        let settings = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                      debugSettings: mockAIChatDebugSettings,
                                      keyValueStore: mockKeyValueStore,
                                      notificationCenter: mockNotificationCenter,
                                      featureFlagger: mockFeatureFlagger)
        settings.enableAIChat(enable: true)
        XCTAssertFalse(settings.isAIChatNavigationBarUserSettingsEnabled)

        // User then turns Nav Bar back on; a new AIChatSettings instance must not re-migrate.
        settings.enableAIChatNavigationBarUserSettings(enable: true)
        let secondInstance = AIChatSettings(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                            debugSettings: mockAIChatDebugSettings,
                                            keyValueStore: mockKeyValueStore,
                                            notificationCenter: mockNotificationCenter,
                                            featureFlagger: mockFeatureFlagger)
        XCTAssertTrue(secondInstance.isAIChatNavigationBarUserSettingsEnabled)
    }

}

final class MockAIChatDebugSettings: AIChatDebugSettingsHandling {
    var messagePolicyHostname: String?
    var customURL: String?
    var contextualSessionTimerSeconds: Int?
    func reset() {}
    func matchesCustomURL(_ url: URL) -> Bool { false }
}
