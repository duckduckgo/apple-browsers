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

    private func canvas(_ themeName: ThemeName) -> NSColor {
        ThemeColors(themeName: themeName).surfaceCanvas
    }

    /// The design system `surfaceCanvas` for `themeName`, resolved for the given appearance.
    private func expectedCanvasHex(_ themeName: ThemeName, isDark: Bool) -> String? {
        var hex: String?
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            hex = NSColor(designSystemColor: .surfaceCanvas, palette: themeName.designColorPalette).usingColorSpace(.sRGB)?.hex()
        }
        return hex
    }

    func testDefaultThemeUsesCanvasForAppearance() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.default), isDark: true).hex(),
                       expectedCanvasHex(.default, isDark: true))
        // The page's own light canvas token is #FAFAFA; the native one is slightly lighter.
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.default), isDark: false).hex(),
                       expectedCanvasHex(.default, isDark: false))
    }

    func testThemeVariantUsesItsCanvas() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.violet), isDark: true).hex(),
                       expectedCanvasHex(.violet, isDark: true))
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.violet), isDark: false).hex(),
                       expectedCanvasHex(.violet, isDark: false))
    }

    func testSolidColorIgnoresThemeAndAppearance() {
        for background in [SolidColorBackground.color01, .color05] {
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .solidColor(background), canvas: canvas(.violet), isDark: true).hex(),
                           background.color.hex())
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .solidColor(background), canvas: canvas(.default), isDark: false).hex(),
                           background.color.hex())
        }
    }

    func testGradientUsesItsFallbackColor() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .gradient(.gradient07), canvas: canvas(.default), isDark: false).hex(),
                       GradientBackground.gradient07.fallbackColor.hex())
    }

    func testUserImageUsesCanvasForTheImageColorScheme() {
        let darkImage = CustomBackground.userImage(UserBackgroundImage(fileName: "image.jpg", colorScheme: .dark))

        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: darkImage, canvas: canvas(.default), isDark: false).hex(),
                       expectedCanvasHex(.default, isDark: true))
    }
}
