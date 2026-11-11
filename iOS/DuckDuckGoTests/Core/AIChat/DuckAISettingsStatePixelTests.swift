//
//  DuckAISettingsStatePixelTests.swift
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

import XCTest
@testable import Core
@testable import DuckDuckGo
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit

@MainActor
final class DuckAISettingsStatePixelTests: XCTestCase {

    func testDailySnapshotIncludesDefaultEnabledKeyboardAnimationWithoutUserAction() throws {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInputKeyboardEdgeSweep])
        let settings = makeSettings(featureFlagger: featureFlagger)
        let pixelFiring = PixelKitMock()
        let reporter = DuckAISettingsStatePixelReporter(settings: settings,
                                                        featureFlagger: featureFlagger,
                                                        isPad: false,
                                                        openDuckAITabCount: { 2 },
                                                        pixelFiring: pixelFiring)

        reporter.fireDaily()

        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "aichat_settings_state")
        XCTAssertEqual(call.frequency, .daily)
        XCTAssertEqual(call.pixel.parameters, [
            "keyboard_animation": "enabled",
            "duckai_enabled": "true",
            "addressbar_toggle": "false",
            "tabbar_button": "false",
            "default_mode": "search",
            "duckai_tabs_open": "2+"
        ])
        XCTAssertNil(call.pixel.standardParameters)
        XCTAssertNil(call.additionalParameters)
        XCTAssertTrue(call.includeAppVersionParameter)
    }

    func testDailySnapshotIncludesStoredDisabledKeyboardAnimation() {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInputKeyboardEdgeSweep])
        let store = MockKeyValueStore()
        makeSettings(store: store, featureFlagger: featureFlagger).enableKeyboardAnimation(enable: false)
        let settings = makeSettings(store: store, featureFlagger: featureFlagger)
        let pixelFiring = PixelKitMock()
        let reporter = DuckAISettingsStatePixelReporter(settings: settings,
                                                        featureFlagger: featureFlagger,
                                                        isPad: false,
                                                        openDuckAITabCount: { 0 },
                                                        pixelFiring: pixelFiring)

        reporter.fireDaily()

        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters?["keyboard_animation"], "disabled")
        XCTAssertFalse(settings.isKeyboardAnimationEnabled)
    }

    func testUnavailableReasonsOverrideBothSavedPreferences() {
        for savedPreference in [true, false] {
            for reason in ["iPad", "flagOff", "duckAIOff"] {
                let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: reason == "flagOff" ? [] : [.unifiedToggleInputKeyboardEdgeSweep])
                let store = MockKeyValueStore()
                store.set(reason != "duckAIOff", forKey: AppConfigurationKeyNames.isAIChatEnabled)
                let settings = makeSettings(store: store, featureFlagger: featureFlagger)
                settings.enableKeyboardAnimation(enable: savedPreference)
                let pixelFiring = PixelKitMock()
                let reporter = DuckAISettingsStatePixelReporter(settings: settings,
                                                                featureFlagger: featureFlagger,
                                                                isPad: reason == "iPad",
                                                                openDuckAITabCount: { 0 },
                                                                pixelFiring: pixelFiring)

                reporter.fireDaily()

                XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters?["keyboard_animation"], "unavailable", reason)
                XCTAssertEqual(settings.isKeyboardAnimationEnabled, savedPreference, reason)
            }
        }
    }

    func testSnapshotReadsLiveFlagAndDuckAISettingChangesWithoutChangingSavedPreference() {
        for savedPreference in [true, false] {
            let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInputKeyboardEdgeSweep])
            let store = MockKeyValueStore()
            let settings = makeSettings(store: store, featureFlagger: featureFlagger)
            settings.enableKeyboardAnimation(enable: savedPreference)
            let pixelFiring = PixelKitMock()
            let reporter = DuckAISettingsStatePixelReporter(settings: settings,
                                                            featureFlagger: featureFlagger,
                                                            isPad: false,
                                                            openDuckAITabCount: { 0 },
                                                            pixelFiring: pixelFiring)

            reporter.fireDaily()
            featureFlagger.enabledFeatureFlags = []
            reporter.fireDaily()
            featureFlagger.enabledFeatureFlags = [.unifiedToggleInputKeyboardEdgeSweep]
            reporter.fireDaily()
            store.set(false, forKey: AppConfigurationKeyNames.isAIChatEnabled)
            reporter.fireDaily()
            store.set(true, forKey: AppConfigurationKeyNames.isAIChatEnabled)
            reporter.fireDaily()

            let savedState = savedPreference ? "enabled" : "disabled"
            XCTAssertEqual(pixelFiring.actualFireCalls.map { $0.pixel.parameters?["keyboard_animation"] },
                           [savedState, "unavailable", savedState, "unavailable", savedState])
            XCTAssertTrue(pixelFiring.actualFireCalls.allSatisfy { $0.frequency == .daily })
            XCTAssertEqual(makeSettings(store: store, featureFlagger: featureFlagger).isKeyboardAnimationEnabled, savedPreference)
        }
    }

    func testAddressBarToggleDoesNotChangeKeyboardAnimationState() {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInputKeyboardEdgeSweep])
        let store = MockKeyValueStore()
        let settings = makeSettings(store: store, featureFlagger: featureFlagger)
        let pixelFiring = PixelKitMock()
        let reporter = DuckAISettingsStatePixelReporter(settings: settings,
                                                        featureFlagger: featureFlagger,
                                                        isPad: false,
                                                        openDuckAITabCount: { 0 },
                                                        pixelFiring: pixelFiring)

        for savedPreference in [true, false] {
            settings.enableKeyboardAnimation(enable: savedPreference)
            for addressBarToggle in [false, true] {
                store.set(addressBarToggle, forKey: LegacyAiChatUserDefaultsKeys.showAIChatExperimentalSearchInputKey)
                reporter.fireDaily()

                XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.parameters?["addressbar_toggle"], String(addressBarToggle))
                XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.parameters?["keyboard_animation"], savedPreference ? "enabled" : "disabled")
            }
        }
    }

    private func makeSettings(store: MockKeyValueStore = MockKeyValueStore(), featureFlagger: MockFeatureFlagger) -> AIChatSettings {
        AIChatSettings(privacyConfigurationManager: PrivacyConfigurationManagerMock(),
                       debugSettings: MockAIChatDebugSettings(),
                       keyValueStore: store,
                       notificationCenter: NotificationCenter(),
                       featureFlagger: featureFlagger,
                       pixelFiring: nil)
    }
}
