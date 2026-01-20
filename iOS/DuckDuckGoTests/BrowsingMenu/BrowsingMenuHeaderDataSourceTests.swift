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

    func testInitialState() {
        XCTAssertFalse(sut.isHeaderVisible)
        XCTAssertNil(sut.title)
        XCTAssertNil(sut.url)
        XCTAssertNil(sut.favicon)
        XCTAssertNil(sut.easterEggLogoURL)
    }

    func testUpdateSetsHeaderProperties() {
        let url = URL(string: "https://example.com")!

        sut.update(isHeaderVisible: true, title: "Test Title", url: url, easterEggLogoURL: nil)

        XCTAssertTrue(sut.isHeaderVisible)
        XCTAssertEqual(sut.title, "Test Title")
        XCTAssertEqual(sut.url, url)
    }

    func testUpdateFaviconSetsFavicon() {
        let image = UIImage()

        sut.update(favicon: image)

        XCTAssertNotNil(sut.favicon)
    }

    func testResetClearsAllProperties() {
        let url = URL(string: "https://example.com")!
        sut.update(isHeaderVisible: true, title: "Test", url: url, easterEggLogoURL: nil)
        sut.update(favicon: UIImage())

        sut.reset()

        XCTAssertFalse(sut.isHeaderVisible)
        XCTAssertNil(sut.title)
        XCTAssertNil(sut.url)
        XCTAssertNil(sut.favicon)
        XCTAssertNil(sut.easterEggLogoURL)
    }

    func testWhenURLChangesThenFaviconIsCleared() {
        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://different.com")!
        sut.update(isHeaderVisible: true, title: "Page 1", url: url1, easterEggLogoURL: nil)
        sut.update(favicon: UIImage())
        XCTAssertNotNil(sut.favicon)

        sut.update(isHeaderVisible: true, title: "Page 2", url: url2, easterEggLogoURL: nil)

        XCTAssertNil(sut.favicon)
        XCTAssertEqual(sut.url, url2)
    }

    func testWhenURLUnchangedThenFaviconIsPreserved() {
        let url = URL(string: "https://example.com")!
        sut.update(isHeaderVisible: true, title: "Page 1", url: url, easterEggLogoURL: nil)
        sut.update(favicon: UIImage())
        XCTAssertNotNil(sut.favicon)

        sut.update(isHeaderVisible: true, title: "Updated Title", url: url, easterEggLogoURL: nil)

        XCTAssertNotNil(sut.favicon)
    }
}
