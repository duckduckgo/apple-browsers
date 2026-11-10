//
//  SearchPageColorMemoryTests.swift
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

import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
struct SearchPageColorMemoryTests {

    private static let page = UIColor(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, alpha: 1)
    private static let card = UIColor(red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255, alpha: 1)
    private static let header = UIColor(red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255, alpha: 1)

    /// A phone-sized results page: header on top, then a card that fills all but the side margins.
    private static func makePage(size: CGSize = CGSize(width: 440, height: 956),
                                 margin: CGFloat = 16,
                                 headerHeight: CGFloat = 120) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            page.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            header.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: headerHeight))
            card.setFill()
            context.fill(CGRect(x: margin, y: headerHeight + 12, width: size.width - margin * 2, height: size.height - headerHeight - 24))
        }
    }

    private static func hex(_ color: UIColor?) -> String? {
        guard let color else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reads the page background from the margins, even when a card fills most of the screen", .timeLimit(.minutes(1)))
    func readsPageBehindCards() throws {
        let image = try #require(Self.makePage().cgImage)

        #expect(Self.hex(SearchPageColorMemory.marginColor(in: image)) == "#171717")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ignores the header strip", .timeLimit(.minutes(1)))
    func ignoresHeader() throws {
        let image = try #require(Self.makePage(headerHeight: 140).cgImage)

        #expect(Self.hex(SearchPageColorMemory.marginColor(in: image)) == "#171717")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Remembers the light page colour and only asks for one sample", .timeLimit(.minutes(1)))
    func remembersLightColor() {
        let memory = SearchPageColorMemory()
        #expect(memory.needsSample(for: .light))
        #expect(memory.color(for: .light) == nil)

        memory.record(preview: Self.makePage(), for: .light)

        #expect(!memory.needsSample(for: .light))
        #expect(Self.hex(memory.color(for: .light)) == "#171717")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dark mode uses the page background behind the header, not the lighter organic results band", .timeLimit(.minutes(1)))
    func darkUsesFixedPageBackground() {
        let memory = SearchPageColorMemory()
        #expect(!memory.needsSample(for: .dark))

        memory.record(preview: Self.makePage(), for: .dark)

        #expect(Self.hex(memory.color(for: .dark)) == "#181818")
    }
}
