//
//  BrowsingMenuHeaderDataSourceTests.swift
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

import XCTest
@testable import DuckDuckGo

// MARK: - BrowsingMenuHeaderDataSource Tests

final class BrowsingMenuHeaderDataSourceTests: XCTestCase {

    private var sut: BrowsingMenuHeaderDataSource!

    override func setUp() {
        super.setUp()
        sut = BrowsingMenuHeaderDataSource()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(sut.isHeaderVisible)
        XCTAssertNil(sut.title)
        XCTAssertNil(sut.displayURL)
        XCTAssertEqual(sut.iconType, .globe)
    }

    // MARK: - Website Header Update

    func testWhenUpdateForWebsiteThenHeaderIsVisible() {
        let url = URL(string: "https://example.com")!

        sut.update(title: "Test Title", url: url, easterEggLogoURL: nil)

        XCTAssertTrue(sut.isHeaderVisible)
        XCTAssertEqual(sut.title, "Test Title")
        XCTAssertEqual(sut.displayURL, "example.com")
    }

    func testWhenUpdateForWebsiteThenIconTypeIsGlobe() {
        let url = URL(string: "https://example.com")!

        sut.update(title: "Test Title", url: url, easterEggLogoURL: nil)

        XCTAssertEqual(sut.iconType, .globe)
    }

    func testWhenUpdateFaviconThenIconTypeIsFavicon() {
        let url = URL(string: "https://example.com")!
        let image = UIImage()
        sut.update(title: "Test Title", url: url, easterEggLogoURL: nil)

        sut.update(favicon: image)

        XCTAssertEqual(sut.iconType, .favicon(image))
    }

    func testWhenUpdateWithEasterEggThenIconTypeIsEasterEgg() {
        let url = URL(string: "https://example.com")!
        let easterEggURL = URL(string: "https://example.com/logo.png")!

        sut.update(title: "Test Title", url: url, easterEggLogoURL: easterEggURL)

        XCTAssertEqual(sut.iconType, .easterEgg(easterEggURL))
    }

    // MARK: - AI Tab Update

    func testWhenUpdateForAITabThenIconTypeIsAIChat() {
        sut.update(forAITab: "Duck.ai")

        XCTAssertEqual(sut.iconType, .aiChat)
    }

    func testWhenUpdateForAITabThenHeaderIsVisible() {
        sut.update(forAITab: "Duck.ai")

        XCTAssertTrue(sut.isHeaderVisible)
        XCTAssertEqual(sut.title, "Duck.ai")
    }

    func testWhenUpdateForAITabThenDisplayURLIsNil() {
        sut.update(forAITab: "Duck.ai")

        XCTAssertNil(sut.displayURL)
    }

    // MARK: - Reset

    func testWhenResetThenAllPropertiesCleared() {
        let url = URL(string: "https://example.com")!
        sut.update(title: "Test", url: url, easterEggLogoURL: nil)
        sut.update(favicon: UIImage())

        sut.reset()

        XCTAssertFalse(sut.isHeaderVisible)
        XCTAssertNil(sut.title)
        XCTAssertNil(sut.displayURL)
        XCTAssertEqual(sut.iconType, .globe)
    }

    func testWhenResetAfterAITabThenAllPropertiesCleared() {
        sut.update(forAITab: "Duck.ai")

        sut.reset()

        XCTAssertFalse(sut.isHeaderVisible)
        XCTAssertNil(sut.title)
        XCTAssertEqual(sut.iconType, .globe)
    }

    // MARK: - URL Change Behavior

    func testWhenURLChangesThenIconTypeResetsToGlobe() {
        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://different.com")!
        sut.update(title: "Page 1", url: url1, easterEggLogoURL: nil)
        sut.update(favicon: UIImage())
        XCTAssertNotEqual(sut.iconType, .globe)

        sut.update(title: "Page 2", url: url2, easterEggLogoURL: nil)

        XCTAssertEqual(sut.iconType, .globe)
        XCTAssertEqual(sut.displayURL, "different.com")
    }

    func testWhenURLUnchangedThenFaviconIsPreserved() {
        let url = URL(string: "https://example.com")!
        let image = UIImage()
        sut.update(title: "Page 1", url: url, easterEggLogoURL: nil)
        sut.update(favicon: image)

        sut.update(title: "Updated Title", url: url, easterEggLogoURL: nil)

        XCTAssertEqual(sut.iconType, .favicon(image))
    }
}
