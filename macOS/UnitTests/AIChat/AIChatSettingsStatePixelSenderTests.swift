//
//  AIChatSettingsStatePixelSenderTests.swift
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

import AIChat
import FeatureFlags_macOS
import Foundation
import NewTabPage
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import PrivacyConfig
import Testing

@testable import DuckDuckGo_Privacy_Browser

struct AIChatSettingsStatePixelSenderTests {

    private let preferencesStorage = MockAIChatPreferencesStorage()
    private let menuConfiguration = MockAIChatConfig()
    private let chromeButtonsVisibilityManager = LocalDuckAIChromeButtonsVisibilityManager(
        persistor: DuckAIChromeButtonsUserDefaultsPersistor(keyValueStore: InMemoryKeyValueStore())
    )
    private let pixelFiring = PixelKitMock()

    private func makeSender(preferencesStorage: AIChatPreferencesStorage? = nil,
                            isNewTabPageOmnibarOn: Bool = true,
                            isSearchBoxVisible: Bool = true,
                            storedMode: NewTabPageDataModel.OmnibarMode = .search) -> AIChatSettingsStatePixelSender {
        AIChatSettingsStatePixelSender(
            preferencesStorage: preferencesStorage ?? self.preferencesStorage,
            menuConfiguration: menuConfiguration,
            chromeButtonsVisibilityManager: chromeButtonsVisibilityManager,
            featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.newTabPageOmnibar.rawValue: isNewTabPageOmnibarOn]),
            isNewTabPageSearchBoxVisible: { isSearchBoxVisible },
            newTabPageOmnibarMode: { storedMode },
            pixelFiring: pixelFiring
        )
    }

    private var firedParameters: [String: String]? {
        pixelFiring.actualFireCalls.last?.pixel.parameters
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports every setting that is on", .timeLimit(.minutes(1)))
    func testThatEverySettingThatIsOnIsReported() {
        preferencesStorage.isAIFeaturesEnabled = true
        preferencesStorage.showSearchAndDuckAIToggle = true
        menuConfiguration.shouldDisplayNewTabPageShortcut = true

        makeSender(storedMode: .ai).firePixel()

        #expect(firedParameters == [
            "duckai_enabled": "true",
            "addressbar_toggle": "true",
            "tabbar_button": "true",
            "ntp_search_box": "true",
            "ntp_duckai": "true",
            "ntp_mode": "ai"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports every setting that is off", .timeLimit(.minutes(1)))
    func testThatEverySettingThatIsOffIsReported() {
        preferencesStorage.isAIFeaturesEnabled = false
        preferencesStorage.showSearchAndDuckAIToggle = false
        menuConfiguration.shouldDisplayNewTabPageShortcut = false
        chromeButtonsVisibilityManager.setHidden(true, for: .duckAI)

        makeSender(isSearchBoxVisible: false, storedMode: .search).firePixel()

        #expect(firedParameters == [
            "duckai_enabled": "false",
            "addressbar_toggle": "false",
            "tabbar_button": "false",
            "ntp_search_box": "false",
            "ntp_duckai": "false",
            "ntp_mode": "search"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A Duck.ai mode left on the New Tab Page reports search once Duck.ai isn't offered there", .timeLimit(.minutes(1)))
    func testThatTheModeFallsBackToSearchWhenDuckAIIsNotOffered() {
        menuConfiguration.shouldDisplayNewTabPageShortcut = false

        makeSender(storedMode: .ai).firePixel()

        #expect(firedParameters?["ntp_mode"] == "search")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaves out the New Tab Page settings when it has no search box", .timeLimit(.minutes(1)))
    func testThatNewTabPageSettingsAreOmittedWithoutTheOmnibarFlag() {
        menuConfiguration.shouldDisplayNewTabPageShortcut = true

        makeSender(isNewTabPageOmnibarOn: false, storedMode: .ai).firePixel()

        #expect(firedParameters.map { Set($0.keys) } == ["duckai_enabled", "addressbar_toggle", "tabbar_button"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The address bar toggle follows the while-typing setting until the user sets it", .timeLimit(.minutes(1)))
    func testThatTheAddressBarToggleFollowsTheWhileTypingSettingUntilSet() throws {
        let suiteName = "test.aiChatSettingsState.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var storage = DefaultAIChatPreferencesStorage(userDefaults: defaults, notificationCenter: NotificationCenter())
        storage.showShortcutInAddressBarWhenTyping = false

        makeSender(preferencesStorage: storage).firePixel()
        storage.showSearchAndDuckAIToggle = true
        makeSender(preferencesStorage: storage).firePixel()

        #expect(pixelFiring.actualFireCalls.map { $0.pixel.parameters?["addressbar_toggle"] } == ["false", "true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fires once a day", .timeLimit(.minutes(1)))
    func testThatThePixelFiresDaily() {
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatSettingsState(duckAIEnabled: true,
                                                                                      addressBarToggle: true,
                                                                                      tabBarButton: true,
                                                                                      newTabPage: nil),
                                               frequency: .daily)]

        makeSender(isNewTabPageOmnibarOn: false).firePixel()

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }
}
