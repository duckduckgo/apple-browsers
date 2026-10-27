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
import Combine
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Expected values are the colours the New Tab Page itself uses (content-scope-scripts design tokens and
/// `customizer/values.js`), since the point is to match what the page settles on.
final class NewTabPageBackgroundColorTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

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
        let expected = ["color01": "#000000", "color05": "#DBDDDF", "color06": "#577DE4"]

        for (name, hex) in expected {
            let background = CustomBackground.solidColor(SolidColorBackground(name)!)
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: background, canvas: canvas(.violet), isDark: true).hex(), hex, name)
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: background, canvas: canvas(.default), isDark: false).hex(), hex, name)
        }
    }

    func testGradientsUseTheNewTabPageFallbackColors() {
        let expected: [GradientBackground: String] = [
            .gradient01: "#F2E5D4",
            .gradient02: "#D5BCD1",
            .gradient0201: "#F4CA78",
            .gradient03: "#E6A356",
            .gradient04: "#4448AE",
            .gradient05: "#A55778",
            .gradient06: "#222566",
            .gradient07: "#0E0E3D"
        ]

        XCTAssertEqual(Set(expected.keys), Set(GradientBackground.allCases))
        for (gradient, hex) in expected {
            XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: .gradient(gradient), canvas: canvas(.default), isDark: false).hex(), hex)
        }
    }

    func testUserImageUsesCanvasForTheImageColorScheme() {
        let darkImage = CustomBackground.userImage(UserBackgroundImage(fileName: "image.jpg", colorScheme: .dark))

        XCTAssertEqual(NewTabPageBackgroundColor.color(customBackground: darkImage, canvas: canvas(.default), isDark: false).hex(), "#1C1C1C")
    }

    func testPublisherEmitsNewColorWhenAnyInputChanges() {
        let background = CurrentValueSubject<CustomBackground?, Never>(nil)
        let themeCanvas = CurrentValueSubject<NSColor, Never>(canvas(.default))
        let isDark = CurrentValueSubject<Bool, Never>(true)
        var emitted: [String] = []
        NewTabPageBackgroundColor.publisher(customBackground: background, canvas: themeCanvas, isDark: isDark)
            .sink { emitted.append($0.hex()) }
            .store(in: &cancellables)

        isDark.send(false)
        themeCanvas.send(canvas(.violet))
        background.send(.solidColor(.color06))

        XCTAssertEqual(emitted, ["#1C1C1C", "#FDFDFD", "#EDECF9", "#577DE4"])
    }
}
