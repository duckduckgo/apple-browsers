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

final class NewTabPageBackgroundColorTests: XCTestCase {

    private var darkAppearance: NSAppearance { NSAppearance(named: .darkAqua)! }
    private var lightAppearance: NSAppearance { NSAppearance(named: .aqua)! }

    func testDefaultBackgroundFollowsAppearance() {
        let dark = NewTabPageBackgroundColor.color(customBackground: nil, themeName: .default, appearance: darkAppearance)
        let light = NewTabPageBackgroundColor.color(customBackground: nil, themeName: .default, appearance: lightAppearance)

        XCTAssertEqual(dark.hex(), "#1C1C1C")
        XCTAssertEqual(light.hex(), "#FDFDFD")
    }

    func testDefaultBackgroundFollowsThemeVariant() {
        let defaultTheme = NewTabPageBackgroundColor.color(customBackground: nil, themeName: .default, appearance: darkAppearance)
        let violet = NewTabPageBackgroundColor.color(customBackground: nil, themeName: .violet, appearance: darkAppearance)

        XCTAssertNotEqual(violet.hex(), defaultTheme.hex())
    }

    func testSolidColorBackgroundUsesItsColor() {
        let color = NewTabPageBackgroundColor.color(customBackground: .solidColor(.color06), themeName: .default, appearance: lightAppearance)

        XCTAssertEqual(color.hex(), SolidColorBackground.color06.color.hex())
    }

    func testGradientBackgroundUsesItsFallbackColor() {
        let color = NewTabPageBackgroundColor.color(customBackground: .gradient(.gradient04), themeName: .default, appearance: lightAppearance)

        XCTAssertEqual(color.hex(), "#4448AE")
    }

    func testUserImageBackgroundUsesCanvasForImageColorScheme() {
        let image = UserBackgroundImage(fileName: "image.jpg", colorScheme: .dark)

        let color = NewTabPageBackgroundColor.color(customBackground: .userImage(image), themeName: .default, appearance: lightAppearance)

        XCTAssertEqual(color.hex(), "#1C1C1C")
    }
}
