//
//  BrowsingMenuHeaderStateProviderTests.swift
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

final class BrowsingMenuHeaderStateProviderTests: XCTestCase {

    private var sut: BrowsingMenuHeaderStateProvider!
    private var dataSource: BrowsingMenuHeaderDataSource!

    override func setUp() {
        super.setUp()
        sut = BrowsingMenuHeaderStateProvider()
        dataSource = BrowsingMenuHeaderDataSource()
    }

    override func tearDown() {
        sut = nil
        dataSource = nil
        super.tearDown()
    }

    // MARK: - Header Visibility

    func testWhenRegularWebPageThenHeaderIsVisible() {
        let url = URL(string: "https://example.com")!

        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            hasLink: true,
            url: url,
            title: "Example"
        )

        XCTAssertTrue(dataSource.isHeaderVisible)
        XCTAssertEqual(dataSource.title, "Example")
        XCTAssertEqual(dataSource.url, url)
    }

    func testWhenFeatureDisabledThenHeaderIsNotVisible() {
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: false,
            hasLink: true,
            url: URL(string: "https://example.com"),
            title: "Example"
        )

        XCTAssertFalse(dataSource.isHeaderVisible)
    }

    func testWhenNewTabPageThenHeaderIsNotVisible() {
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            isNewTabPage: true,
            hasLink: true,
            url: URL(string: "https://example.com"),
            title: "Example"
        )

        XCTAssertFalse(dataSource.isHeaderVisible)
    }

    func testWhenAITabThenHeaderIsNotVisible() {
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            isAITab: true,
            hasLink: true,
            url: URL(string: "https://example.com"),
            title: "Example"
        )

        XCTAssertFalse(dataSource.isHeaderVisible)
    }

    func testWhenErrorPageThenHeaderIsNotVisible() {
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            isError: true,
            hasLink: true,
            url: URL(string: "https://example.com"),
            title: "Example"
        )

        XCTAssertFalse(dataSource.isHeaderVisible)
    }

    func testWhenNoLinkThenHeaderIsNotVisible() {
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            hasLink: false
        )

        XCTAssertFalse(dataSource.isHeaderVisible)
    }

    func testWhenHeaderBecomesHiddenThenDataSourceIsReset() {
        // First show the header
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            hasLink: true,
            url: URL(string: "https://example.com"),
            title: "Example"
        )
        XCTAssertTrue(dataSource.isHeaderVisible)

        // Then hide it
        sut.update(
            dataSource: dataSource,
            isFeatureEnabled: true,
            isNewTabPage: true,
            hasLink: true,
            url: URL(string: "https://example.com"),
            title: "Example"
        )

        XCTAssertFalse(dataSource.isHeaderVisible)
        XCTAssertNil(dataSource.title)
        XCTAssertNil(dataSource.url)
    }
}
