//
//  PageLoadTesterTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import WebKit
@testable import PerformanceTest

@MainActor
final class PageLoadTesterTests: XCTestCase {

    // MARK: - Properties

    private var webView: WKWebView!
    private var tester: PageLoadTester!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create web view with test configuration
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)

        // Create tester
        tester = PageLoadTester(webView: webView)
    }

    override func tearDown() async throws {
        webView = nil
        tester = nil
        try await super.tearDown()
    }

    // MARK: - Basic Tests

    func testPageLoadTesterInitialization() {
        // Then
        XCTAssertNotNil(tester)
        XCTAssertNotNil(webView.navigationDelegate)
        XCTAssertTrue(webView.navigationDelegate is PageLoadTester)
    }

    func testHandlersCanBeSet() {
        // When
        tester.progressHandler = { _ in
            // Handler set
        }

        tester.completionHandler = { _ in
            // Handler set
        }

        tester.beforeLoadHandler = {
            // Handler set
        }

        // Then - handlers are set (actual calls tested in LogicTests)
        XCTAssertNotNil(tester.progressHandler)
        XCTAssertNotNil(tester.completionHandler)
        XCTAssertNotNil(tester.beforeLoadHandler)
    }

    func testConcurrentCreation() async throws {
        // Given - multiple testers can be created concurrently
        let urls = [
            URL(string: "https://example1.com")!,
            URL(string: "https://example2.com")!,
            URL(string: "https://example3.com")!
        ]

        // When
        let testers = await withTaskGroup(of: PageLoadTester.self) { group in
            for _ in urls {
                group.addTask { @MainActor in
                    let config = WKWebViewConfiguration()
                    config.websiteDataStore = .nonPersistent()
                    let webView = WKWebView(frame: .zero, configuration: config)
                    return PageLoadTester(webView: webView)
                }
            }

            var results: [PageLoadTester] = []
            for await tester in group {
                results.append(tester)
            }
            return results
        }

        // Then
        XCTAssertEqual(testers.count, 3)
        for tester in testers {
            XCTAssertNotNil(tester)
        }
    }
}