//
//  NewTabPageBackgroundColorTests.swift
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

import AppKit
import DesignResourcesKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageBackgroundColorTests: XCTestCase {

    private func surface(_ themeName: ThemeName) -> NSColor {
        ThemeColors(themeName: themeName).surfacePrimary
    }

    /// The design system `surfacePrimary` for `themeName`, resolved for the given appearance.
    private func expectedSurfaceHex(_ themeName: ThemeName, isDark: Bool) -> String? {
        var hex: String?
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            hex = NSColor(designSystemColor: .surfacePrimary, palette: themeName.designColorPalette).usingColorSpace(.sRGB)?.hex()
        }
        return hex
    }

    func testDefaultThemeUsesSurfaceForAppearance() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, surface: surface(.default), isDark: true).hex(),
                       expectedSurfaceHex(.default, isDark: true))
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, surface: surface(.default), isDark: false).hex(),
                       expectedSurfaceHex(.default, isDark: false))
    }

    func testThemeVariantUsesItsSurface() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, surface: surface(.violet), isDark: true).hex(),
                       expectedSurfaceHex(.violet, isDark: true))
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, surface: surface(.violet), isDark: false).hex(),
                       expectedSurfaceHex(.violet, isDark: false))
    }

    func testSolidColorIgnoresThemeAndAppearance() {
        for background in [SolidColorBackground.color01, .color05] {
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .solidColor(background), surface: surface(.violet), isDark: true).hex(),
                           background.color.hex())
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .solidColor(background), surface: surface(.default), isDark: false).hex(),
                           background.color.hex())
        }
    }

    func testGradientUsesItsFallbackColor() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .gradient(.gradient07), surface: surface(.default), isDark: false).hex(),
                       GradientBackground.gradient07.fallbackColor.hex())
    }

    func testUserImageUsesSurfaceForTheImageColorScheme() {
        let darkImage = CustomBackground.userImage(UserBackgroundImage(fileName: "image.jpg", colorScheme: .dark))

        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: darkImage, surface: surface(.default), isDark: false).hex(),
                       expectedSurfaceHex(.default, isDark: true))
    }
}
