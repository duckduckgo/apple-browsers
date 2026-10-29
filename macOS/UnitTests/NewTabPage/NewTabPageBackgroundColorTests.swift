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
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Expected values are the colours the New Tab Page itself uses (content-scope-scripts design tokens and
/// `customizer/values.js`), since the point is to match what the page settles on.
final class NewTabPageBackgroundColorTests: XCTestCase {

    private func canvas(_ themeName: ThemeName) -> NSColor {
        ThemeColors(themeName: themeName).surfaceCanvas
    }

    func testDefaultThemeUsesCanvasForAppearance() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.default), isDark: true).hex(), "#1C1C1C")
        // The page's own light canvas token is #FAFAFA; the native one is slightly lighter.
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.default), isDark: false).hex(), "#FDFDFD")
    }

    func testThemeVariantUsesItsCanvas() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.violet), isDark: true).hex(), "#271C49")
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: nil, canvas: canvas(.violet), isDark: false).hex(), "#EDECF9")
    }

    func testSolidColorIgnoresThemeAndAppearance() {
        for (background, hex) in [(SolidColorBackground.color01, "#000000"), (.color05, "#DBDDDF")] {
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .solidColor(background), canvas: canvas(.violet), isDark: true).hex(), hex)
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .solidColor(background), canvas: canvas(.default), isDark: false).hex(), hex)
        }
    }

    func testGradientUsesItsFallbackColor() {
        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .gradient(.gradient07), canvas: canvas(.default), isDark: false).hex(), "#0E0E3D")
    }

    func testUserImageUsesCanvasForTheImageColorScheme() {
        let darkImage = CustomBackground.userImage(UserBackgroundImage(fileName: "image.jpg", colorScheme: .dark))

        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: darkImage, canvas: canvas(.default), isDark: false).hex(), "#1C1C1C")
    }
}
