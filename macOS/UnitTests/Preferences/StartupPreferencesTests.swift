//
//  StartupPreferencesTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import DuckDuckGo_Privacy_Browser

final class StartupPreferencesPersistorMock: StartupPreferencesPersistor {
    var launchToCustomHomePage: Bool
    var customHomePageURL: String
    var restorePreviousSession: Bool
    var startupWindowType: StartupWindowType

    init(launchToCustomHomePage: Bool = false, customHomePageURL: String = "", restorePreviousSession: Bool = false, startupWindowType: StartupWindowType = .window) {
        self.customHomePageURL = customHomePageURL
        self.launchToCustomHomePage = launchToCustomHomePage
        self.restorePreviousSession = restorePreviousSession
        self.startupWindowType = startupWindowType
    }
}

class StartupPreferencesTests: XCTestCase {

    @MainActor
    func testWhenInitializedThenItLoadsPersistedValues() throws {
        var model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: false, customHomePageURL: "duckduckgo.com", restorePreviousSession: false))
        XCTAssertEqual(model.launchToCustomHomePage, false)
        XCTAssertEqual(model.customHomePageURL, "duckduckgo.com")
        XCTAssertEqual(model.restorePreviousSession, false)
        XCTAssertEqual(model.startupWindowType, .window) // Default value

        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: true, customHomePageURL: "http://duckduckgo.com", restorePreviousSession: true))
        XCTAssertEqual(model.launchToCustomHomePage, true)
        XCTAssertEqual(model.customHomePageURL, "http://duckduckgo.com")
        XCTAssertEqual(model.restorePreviousSession, true)
        XCTAssertEqual(model.startupWindowType, .window) // Default value

        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: true, customHomePageURL: "https://duckduckgo.com", restorePreviousSession: true))
        XCTAssertEqual(model.customHomePageURL, "https://duckduckgo.com")
        XCTAssertEqual(model.startupWindowType, .window) // Default value

        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: true, customHomePageURL: "https://mail.google.com/mail/u/1/#spam/FMfcgzGtxKRZFPXfxKMWSKVgwJlswxnH", restorePreviousSession: true))
        XCTAssertEqual(model.friendlyURL, "https://mail.google.com/mai...")

        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: true, customHomePageURL: "https://www.rnids.rs/национални-домени/регистрација-националних-домена", restorePreviousSession: true))
        XCTAssertEqual(model.friendlyURL, "https://www.rnids.rs/национ...")

        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: true, customHomePageURL: "www.rnids.rs/национални-домени/регистрација-националних-домена", restorePreviousSession: true))
        XCTAssertEqual(model.friendlyURL, "www.rnids.rs/национални-дом...")

        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: true, customHomePageURL: "https://💩.la", restorePreviousSession: true))
        XCTAssertEqual(model.friendlyURL, "https://💩.la")

    }

    @MainActor
    func testIsValidURL() {
        XCTAssertFalse(StartupPreferences().isValidURL("invalid url"))
        XCTAssertFalse(StartupPreferences().isValidURL("invalidUrl"))
        XCTAssertFalse(StartupPreferences().isValidURL(""))
        XCTAssertTrue(StartupPreferences().isValidURL("test.com"))
        XCTAssertTrue(StartupPreferences().isValidURL("http://test.com"))
        XCTAssertTrue(StartupPreferences().isValidURL("https://test.com"))
    }

    // MARK: - StartupWindowType Tests

    func testStartupWindowTypeEnum() {
        // Test enum cases
        XCTAssertEqual(StartupWindowType.window.rawValue, "window")
        XCTAssertEqual(StartupWindowType.fireWindow.rawValue, "fire-window")

        // Test case iterable
        let allCases = StartupWindowType.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.window))
        XCTAssertTrue(allCases.contains(.fireWindow))

        // Test display names
        XCTAssertEqual(StartupWindowType.window.displayName, UserText.window)
        XCTAssertEqual(StartupWindowType.fireWindow.displayName, UserText.fireWindow)
    }

    func testStartupWindowTypeInitialization() {
        // Test initialization from raw value
        XCTAssertEqual(StartupWindowType(rawValue: "window"), .window)
        XCTAssertEqual(StartupWindowType(rawValue: "fire-window"), .fireWindow)
        XCTAssertNil(StartupWindowType(rawValue: "invalid"))
    }

    // MARK: - StartupWindowType Persistence Tests

    @MainActor
    func testWhenInitializedThenItLoadsStartupWindowType() {
        // Test default value
        var model = StartupPreferences(persistor: StartupPreferencesPersistorMock(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com"
        ))
        XCTAssertEqual(model.startupWindowType, .window)

        // Test fire window value
        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .fireWindow
        ))
        XCTAssertEqual(model.startupWindowType, .fireWindow)

        // Test window value explicitly
        model = StartupPreferences(persistor: StartupPreferencesPersistorMock(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .window
        ))
        XCTAssertEqual(model.startupWindowType, .window)
    }

    @MainActor
    func testWhenStartupWindowTypeIsUpdatedThenPersistedValueIsUpdated() {
        class TestPersistor: StartupPreferencesPersistor {
            var launchToCustomHomePage: Bool
            var customHomePageURL: String
            var restorePreviousSession: Bool
            var startupWindowType: StartupWindowType {
                didSet {
                    startupWindowTypeSetCalls.append(startupWindowType)
                }
            }
            var startupWindowTypeSetCalls: [StartupWindowType] = []

            init(launchToCustomHomePage: Bool, customHomePageURL: String, restorePreviousSession: Bool = false, startupWindowType: StartupWindowType = .window) {
                self.launchToCustomHomePage = launchToCustomHomePage
                self.customHomePageURL = customHomePageURL
                self.restorePreviousSession = restorePreviousSession
                self.startupWindowType = startupWindowType
            }
        }

        let persistor = TestPersistor(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com"
        )
        let model = StartupPreferences(persistor: persistor)

        // Initial value should not trigger a set call during initialization
        XCTAssertTrue(persistor.startupWindowTypeSetCalls.isEmpty)

        // Test changing to fire window
        model.startupWindowType = .fireWindow
        XCTAssertEqual(persistor.startupWindowTypeSetCalls, [.fireWindow])
        XCTAssertEqual(persistor.startupWindowType, .fireWindow)

        // Test changing back to regular window
        model.startupWindowType = .window
        XCTAssertEqual(persistor.startupWindowTypeSetCalls, [.fireWindow, .window])
        XCTAssertEqual(persistor.startupWindowType, .window)

        // Test setting same value calls persistor (this is expected behavior)
        persistor.startupWindowTypeSetCalls.removeAll()
        model.startupWindowType = .window
        XCTAssertEqual(persistor.startupWindowTypeSetCalls, [.window])
    }

    // MARK: - Enhanced Initialization Tests

    @MainActor
    func testWhenInitializedWithAllPropertiesThenItLoadsAllPersistedValues() {
        let persistor = StartupPreferencesPersistorMock(
            launchToCustomHomePage: true,
            customHomePageURL: "https://example.com",
            restorePreviousSession: true,
            startupWindowType: .fireWindow
        )

        let model = StartupPreferences(persistor: persistor)

        XCTAssertEqual(model.launchToCustomHomePage, true)
        XCTAssertEqual(model.customHomePageURL, "https://example.com")
        XCTAssertEqual(model.restorePreviousSession, true)
        XCTAssertEqual(model.startupWindowType, .fireWindow)
    }

    @MainActor
    func testWhenInitializedWithMixedPropertiesThenItLoadsCorrectValues() {
        // Test various combinations to ensure property independence
        let combinations: [(Bool, String, Bool, StartupWindowType)] = [
            (false, "duckduckgo.com", false, .window),
            (true, "https://example.com", false, .fireWindow),
            (false, "https://test.com", true, .fireWindow),
            (true, "duckduckgo.com", true, .window)
        ]

        for (launchCustom, url, restoreSession, windowType) in combinations {
            let persistor = StartupPreferencesPersistorMock(
                launchToCustomHomePage: launchCustom,
                customHomePageURL: url,
                restorePreviousSession: restoreSession,
                startupWindowType: windowType
            )

            let model = StartupPreferences(persistor: persistor)

            XCTAssertEqual(model.launchToCustomHomePage, launchCustom)
            XCTAssertEqual(model.customHomePageURL, url)
            XCTAssertEqual(model.restorePreviousSession, restoreSession)
            XCTAssertEqual(model.startupWindowType, windowType)
        }
    }

    // MARK: - Startup Burner Mode Tests

    @MainActor
    func testStartupBurnerMode() {
        // Test with regular window type - should return regular mode
        var persistor = StartupPreferencesPersistorMock(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .window
        )
        var model = StartupPreferences(persistor: persistor)
        var burnerMode = model.startupBurnerMode()
        XCTAssertEqual(burnerMode, .regular)

        // Test with fire window type - should return burner mode when feature flag is on
        persistor = StartupPreferencesPersistorMock(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .fireWindow
        )
        model = StartupPreferences(persistor: persistor)
        burnerMode = model.startupBurnerMode()
        XCTAssertTrue(burnerMode.isBurner)
    }

    @MainActor
    func testStartupBurnerModeEdgeCases() {
        let featureFlagger = MockFeatureFlagger()

        let persistor = StartupPreferencesPersistorMock(
            launchToCustomHomePage: false,
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .fireWindow
        )
        let model = StartupPreferences(persistor: persistor)

        // Test multiple calls return consistent results
        let burnerMode1 = model.startupBurnerMode()
        let burnerMode2 = model.startupBurnerMode()
        XCTAssertEqual(burnerMode1.isBurner, burnerMode2.isBurner)

        // Test state change
        model.startupWindowType = .window
        let regularMode = model.startupBurnerMode()
        XCTAssertEqual(regularMode, .regular)
    }

}

fileprivate extension StartupPreferences {
    @MainActor
    convenience init(persistor: StartupPreferencesPersistor = StartupPreferencesPersistorMock()) {
        self.init(
            persistor: persistor,
            windowControllersManager: WindowControllersManagerMock(),
            appearancePreferences: AppearancePreferences(
                persistor: AppearancePreferencesPersistorMock(),
                privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                featureFlagger: MockFeatureFlagger()
            )
        )
    }
}
