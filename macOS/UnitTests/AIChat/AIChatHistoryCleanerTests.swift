//
//  AIChatHistoryCleanerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import BrowserServicesKitTestsUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AIChatHistoryCleanerTests: XCTestCase {

    private var featureFlaggerMock: MockFeatureFlagger!
    private var aiChatMenuConfiguration: MockAIChatConfig!
    private var featureDiscoveryMock: MockFeatureDiscovery!
    private var privacyConfigMock: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        featureFlaggerMock = MockFeatureFlagger()
        aiChatMenuConfiguration = MockAIChatConfig()
        featureDiscoveryMock = MockFeatureDiscovery()
        privacyConfigMock = MockPrivacyConfigurationManager()
    }

    override func tearDown() {
        featureFlaggerMock = nil
        aiChatMenuConfiguration = nil
        featureDiscoveryMock = nil
        privacyConfigMock = nil
        super.tearDown()
    }

    func testWhenAIChatShouldBeShown_andAIChatWasUsed_thenShouldDisplayCleanAIChatHistoryOptionIsTrue() {
        aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature = true
        featureDiscoveryMock.setReturnValue(true, for: .aiChat)

        let sut = AIChatHistoryCleaner(featureFlagger: featureFlaggerMock, aiChatMenuConfiguration: aiChatMenuConfiguration, featureDiscovery: featureDiscoveryMock, privacyConfig: privacyConfigMock)

        XCTAssertTrue(sut.shouldDisplayCleanAIChatHistoryOption)
    }

    func testWhenAIChatShouldBeShown_andAIChatWasNotUsed_thenShouldDisplayCleanAIChatHistoryOptionIsFalse() {
        aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature = true
        featureDiscoveryMock.setReturnValue(false, for: .aiChat)

        let sut = AIChatHistoryCleaner(featureFlagger: featureFlaggerMock, aiChatMenuConfiguration: aiChatMenuConfiguration, featureDiscovery: featureDiscoveryMock, privacyConfig: privacyConfigMock)

        XCTAssertFalse(sut.shouldDisplayCleanAIChatHistoryOption)
    }

    func testWhenAIChatShouldNotBeShown_andAIChatWasUsed_thenShouldDisplayCleanAIChatHistoryOptionIsFalse() {
        aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature = false
        featureDiscoveryMock.setReturnValue(true, for: .aiChat)

        let sut = AIChatHistoryCleaner(featureFlagger: featureFlaggerMock, aiChatMenuConfiguration: aiChatMenuConfiguration, featureDiscovery: featureDiscoveryMock, privacyConfig: privacyConfigMock)

        XCTAssertFalse(sut.shouldDisplayCleanAIChatHistoryOption)
    }

    func testWhenNotificationIsPosted_thenShouldDisplayCleanAIChatHistoryOptionIsEnabled() {
        aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature = true
        featureDiscoveryMock.setReturnValue(false, for: .aiChat)
        let notificationCenter = NotificationCenter()

        let sut = AIChatHistoryCleaner(featureFlagger: featureFlaggerMock, aiChatMenuConfiguration: aiChatMenuConfiguration, featureDiscovery: featureDiscoveryMock, notificationCenter: notificationCenter, privacyConfig: privacyConfigMock)

        XCTAssertFalse(sut.shouldDisplayCleanAIChatHistoryOption)

        notificationCenter.post(name: .featureDiscoverySetWasUsedBefore, object: nil, userInfo: ["feature": WasUsedBeforeFeature.aiChat.rawValue])

        XCTAssertTrue(sut.shouldDisplayCleanAIChatHistoryOption)
    }

}
