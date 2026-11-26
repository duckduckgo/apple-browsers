//
//  URLPixelKitTests.swift
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

import XCTest
@testable import PixelKit

final class URLPixelKitTests: XCTestCase {

    func testURLSafeNameIsUnchanged() {
        let name = "m_mac_duck-ai_native-storage_migration_done_chats_u"
        let url = URL.pixelUrl(forPixelNamed: name)

        XCTAssertEqual(url.absoluteString, "\(URL.pixelBase)/t/\(name)")
    }

    func testNameWithDotIsUnchanged() {
        let url = URL.pixelUrl(forPixelNamed: "m.some.pixel")

        XCTAssertEqual(url.absoluteString, "\(URL.pixelBase)/t/m.some.pixel")
    }

    func testSpacesAndNonASCIIArePercentEncoded() {
        let url = URL.pixelUrl(forPixelNamed: "m_pixel_a b_é")

        XCTAssertEqual(url.absoluteString, "\(URL.pixelBase)/t/m_pixel_a%20b_%C3%A9")
    }

    func testNameStaysOnePathSegment() {
        let url = URL.pixelUrl(forPixelNamed: "m_pixel_../x?y=1#z")

        XCTAssertEqual(url.absoluteString, "\(URL.pixelBase)/t/m_pixel_..%2Fx%3Fy=1%23z")
        XCTAssertEqual(url.pathComponents.count, 3) // "/", "t", name
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
    }
}
