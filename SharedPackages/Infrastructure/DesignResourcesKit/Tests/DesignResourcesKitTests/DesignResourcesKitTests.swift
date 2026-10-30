//
//  DesignResourcesKitTests.swift
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

import SwiftUI
import XCTest
@testable import DesignResourcesKit

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

final class DesignResourcesKitTests: XCTestCase {

    @MainActor
    func testHexColorPreservesRGBChannelsAndOpacity() throws {
        let color = PlatformColor(Color(0x12ABEF, opacity: 0.4))

        try assertComponents(color, expected: (18 / 255, 171 / 255, 239 / 255, 0.4))
    }

    @MainActor
    func testHexColorDefaultsToOpaque() throws {
        try assertComponents(PlatformColor(Color(0xFF0000)), expected: (1, 0, 0, 1))
    }

    @MainActor
    func testStaticColorResolvesIdenticallyInBothAppearances() throws {
        let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        let color = platformColor(DynamicColor(staticColor: red))

        try assertComponents(color, expected: (1, 0, 0, 1))
        try assertComponents(color, dark: true, expected: (1, 0, 0, 1))
    }

    @MainActor
    func testDynamicColorResolvesTheRequestedAppearance() throws {
        let color = platformColor(DynamicColor(lightHex: 0xFF0000, darkHex: 0x0000FF))

        try assertComponents(color, expected: (1, 0, 0, 1))
        try assertComponents(color, dark: true, expected: (0, 0, 1, 1))
    }

    @MainActor
    func testHexOpacityIsAppliedToEachAppearance() throws {
        let color = platformColor(DynamicColor(lightHex: 0xFF0000, lightOpacityHex: 0x80,
                                               darkHex: 0x0000FF, darkOpacityHex: 0x40))

        try assertComponents(color, expected: (1, 0, 0, 128 / 255))
        try assertComponents(color, dark: true, expected: (0, 0, 1, 64 / 255))
    }

    @MainActor
    func testPublicColorInitializersUseTheExplicitPalette() throws {
#if os(macOS)
        let palette = ColorPalette.coolGray
#else
        let palette = ColorPalette.default
#endif
        let definition = palette.paletteDefinition.dynamicColor(for: DesignSystemColor.accentPrimary)
        let nativeColor = PlatformColor(designSystemColor: .accentPrimary, palette: palette)
        let swiftUIColor = PlatformColor(Color(designSystemColor: .accentPrimary, palette: palette))

        for dark in [false, true] {
            let expected = try components(PlatformColor(dark ? definition.darkColor : definition.lightColor), dark: dark)
            try assertComponents(nativeColor, dark: dark, expected: expected)
            try assertComponents(swiftUIColor, dark: dark, expected: expected)
        }
    }

#if os(macOS)
    @MainActor
    func testNewColorsUseCurrentPaletteWhileExistingColorsKeepTheirPalette() throws {
        let original = DesignSystemPalette.current
        defer { DesignSystemPalette.current = original }

        DesignSystemPalette.current = .coolGray
        let existingColor = NSColor(designSystemColor: .accentPrimary)
        DesignSystemPalette.current = .rose
        let newColor = NSColor(designSystemColor: .accentPrimary)

        for dark in [false, true] {
            let coolGray = try components(NSColor(designSystemColor: .accentPrimary, palette: .coolGray), dark: dark)
            let rose = try components(NSColor(designSystemColor: .accentPrimary, palette: .rose), dark: dark)
            try assertComponents(existingColor, dark: dark, expected: coolGray)
            try assertComponents(newColor, dark: dark, expected: rose)
        }
    }
#endif

    @MainActor
    private func platformColor(_ color: DynamicColor) -> PlatformColor {
#if canImport(UIKit)
        color.uiColor
#else
        color.nsColor
#endif
    }

    @MainActor
    private func components(_ color: PlatformColor, dark: Bool) throws -> (CGFloat, CGFloat, CGFloat, CGFloat) {
#if canImport(UIKit)
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red, green, blue, alpha)
#else
        let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        let rgb = try XCTUnwrap(resolved)
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
#endif
    }

    @MainActor
    private func assertComponents(_ color: PlatformColor, dark: Bool = false,
                                  expected: (CGFloat, CGFloat, CGFloat, CGFloat),
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try components(color, dark: dark)
        XCTAssertEqual(actual.0, expected.0, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.1, expected.1, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.2, expected.2, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.3, expected.3, accuracy: 0.00001, file: file, line: line)
    }
}
