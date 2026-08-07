//
//  PageContextBlocklistSettingsTests.swift
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
@testable import AIChat

final class PageContextBlocklistSettingsTests: XCTestCase {

    /// The canonical config block from spec §4.1.
    private var canonicalBlocklist: [String: Any] {
        [
            "pdf": ["urlExtensions": [".pdf"], "contentTypes": ["application/pdf"]],
            "image": ["urlExtensions": [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp"],
                      "contentTypePrefixes": ["image/"]],
            "video": ["urlExtensions": [".mp4", ".webm", ".avi", ".mov", ".mkv"],
                      "contentTypePrefixes": ["video/"]],
            "audio": ["urlExtensions": [".mp3", ".wav", ".ogg", ".flac", ".aac", ".m4a"],
                      "contentTypePrefixes": ["audio/"]]
        ]
    }

    func testWhenCanonicalBlocklistThenAllCategoriesDecode() {
        let settings = PageContextBlocklistSettings(blocklist: canonicalBlocklist)
        XCTAssertNotNil(settings)
        XCTAssertEqual(Set(settings?.categories.keys ?? [:].keys), ["pdf", "image", "video", "audio"])
        XCTAssertEqual(settings?.categories["pdf"]?.contentTypes, ["application/pdf"])
        XCTAssertEqual(settings?.categories["image"]?.contentTypePrefixes, ["image/"])
        XCTAssertNil(settings?.categories["pdf"]?.contentTypePrefixes)
    }

    func testWhenArbitraryCategoryThenDecodes() {
        let settings = PageContextBlocklistSettings(blocklist: ["archive": ["contentTypes": ["application/zip"]]])
        XCTAssertEqual(settings?.categories["archive"]?.contentTypes, ["application/zip"])
        XCTAssertNil(settings?.categories["archive"]?.urlExtensions)
    }

    func testWhenNilBlocklistThenReturnsNil() {
        XCTAssertNil(PageContextBlocklistSettings(blocklist: nil))
    }

    func testWhenEmptyBlocklistThenReturnsNil() {
        XCTAssertNil(PageContextBlocklistSettings(blocklist: [String: Any]()))
    }

    func testWhenWrongTypeThenReturnsNil() {
        XCTAssertNil(PageContextBlocklistSettings(blocklist: "not-a-dictionary"))
    }
}
