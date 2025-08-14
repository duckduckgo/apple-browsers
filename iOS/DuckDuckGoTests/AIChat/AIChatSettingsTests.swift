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
import BrowserServicesKit
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

}

final class MockAIChatDebugSettings: AIChatDebugSettingsHandling {
    var messagePolicyHostname: String?
    var customURL: String?
    func reset() {}
}
