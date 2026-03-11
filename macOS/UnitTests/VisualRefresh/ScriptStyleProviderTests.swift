//
//  ScriptStyleProviderTests.swift
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

import Foundation
import Combine
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
import Common
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ScriptStyleProviderTests: XCTestCase {

    func testInitialThemeAndAppearanceAreEffectivelyRelayed() {
        let (styleProvider, _) = buildStyleProvider(initialAppearance: .dark, initialTheme: .violet)
        XCTAssertEqual(styleProvider.themeName, ThemeName.violet.rawValue)
        XCTAssertEqual(styleProvider.themeAppearance, ThemeAppearance.dark.rawValue)
    }

    func testSystemDefaultAppearanceIsMappedIntoSystemLowercaseString() {
        let (styleProvider, _) = buildStyleProvider(initialAppearance: .systemDefault)
        XCTAssertEqual(styleProvider.themeAppearance, "system")
    }

    func testThemeNameChangesAreRelayedThroughThemeStylePublisher() async {
        let (styleProvider, themeManager) = buildStyleProvider()

        let styleUpdated = expectation(description: "Theme style updated")
        var themeName: String?
        let cancellable = styleProvider.themeStylePublisher.first().sink { value in
            themeName = value.1
            styleUpdated.fulfill()
        }

        themeManager.themeName = .green

        await fulfillment(of: [styleUpdated], timeout: 5)
        XCTAssertEqual(themeName, ThemeName.green.rawValue)
        withExtendedLifetime(cancellable) {}
    }

    func testAppearanceChangesAreRelayedThroughThemeStylePublisher() async {
        let (styleProvider, themeManager) = buildStyleProvider()

        let styleUpdated = expectation(description: "Theme style updated")
        var appearance: String?
        let cancellable = styleProvider.themeStylePublisher.first().sink { value in
            appearance = value.0
            styleUpdated.fulfill()
        }

        themeManager.appearance = .light

        await fulfillment(of: [styleUpdated], timeout: 5)
        XCTAssertEqual(appearance, ThemeAppearance.light.rawValue)
        withExtendedLifetime(cancellable) {}
    }
}

private extension ScriptStyleProviderTests {

    func buildStyleProvider(initialAppearance: ThemeAppearance = .systemDefault, initialTheme: ThemeName = .default) -> (ScriptStyleProviding, MockThemeManager) {
        let themeManager = MockThemeManager(appearance: initialAppearance, themeName: initialTheme)
        let styleProvider = ScriptStyleProvider(themeManager: themeManager)

        return (styleProvider, themeManager)
    }
}
