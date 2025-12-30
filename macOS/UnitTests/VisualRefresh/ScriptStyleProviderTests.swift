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

        let (_, themeName) = await styleProvider.themeStylePublisher.awaitFirst {
            themeManager.themeName = .green
        }

        XCTAssertEqual(themeName, ThemeName.green.rawValue)
    }

    func testAppearanceChangesAreRelayedThroughThemeStylePublisher() async {
        let (styleProvider, themeManager) = buildStyleProvider()

        let (appearance, _) = await styleProvider.themeStylePublisher.awaitFirst {
            themeManager.appearance = .light
        }

        XCTAssertEqual(appearance, ThemeAppearance.light.rawValue)
    }
}

private extension ScriptStyleProviderTests {

    func buildStyleProvider(initialAppearance: ThemeAppearance = .systemDefault, initialTheme: ThemeName = .default) -> (ScriptStyleProviding, MockThemeManager) {
        let themeManager = MockThemeManager(appearance: initialAppearance, themeName: initialTheme)
        let styleProvider = ScriptStyleProvider(themeManager: themeManager)

        return (styleProvider, themeManager)
    }
}

// MARK: - Published.Publisher Private Testing Helpers
//
private extension AnyPublisher {

    func awaitFirst(afterPerforming action: () -> Void) async -> Output where Failure == Never {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = self
                .first()
                .sink { value in
                    cancellable?.cancel()
                    continuation.resume(returning: value)
                }

            // Action runs, effectively, AFTER the subscription is established
            action()
        }
    }
}
