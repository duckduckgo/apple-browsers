//
//  LoadingIndicatorPolicyTests.swift
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

import XCTest
import Foundation
import AppKit
@testable import DuckDuckGo_Privacy_Browser

final class LoadingIndicatorPolicyTests: XCTestCase {

    private let policy = DefaultLoadingIndicatorPolicy()

    func testLoadingIndicatorIsShownWhenThereAreNoErrorsAndTheURLIsValidHypertextSchema() {
        let testingURLs = [
            URL(string: "https://example.com")!,
            URL(string: "http://example.com")!,
            URL(string: "https://subdomain.example.com/path")
        ]

        for url in testingURLs {
            let result = policy.shouldShowLoadingIndicator(isLoading: true, url: url, error: nil)
            XCTAssertTrue(result)
        }
    }

    func testLoadingIndicatorIsNotShownWhenURLIsNilEvenIfOtherConditionsAreMet() {
        let result = policy.shouldShowLoadingIndicator(isLoading: true, url: nil, error: nil)
        XCTAssertFalse(result)
    }

    func testLoadingIndicatorIsNotShownWhenThereAreErrors() {
        let resultWhenLoading = policy.shouldShowLoadingIndicator(isLoading: true, url: .appStore, error: NSError.testingError)
        XCTAssertFalse(resultWhenLoading)

        let resultWhenNotLoading = policy.shouldShowLoadingIndicator(isLoading: false, url: .appStore, error: NSError.testingError)
        XCTAssertFalse(resultWhenNotLoading)
    }

    func testLoadingIndicatorIsNotShownForDuckSchemaURLs() async throws {
        for url in [URL.newtab, URL.welcome, URL.settings, URL.bookmarks, URL.history] {
            let result = policy.shouldShowLoadingIndicator(isLoading: true, url: url, error: nil)
            XCTAssertTrue(url.isDuckURLScheme)
            XCTAssertFalse(result)
        }
    }

    func testLoadingIndicatorIsNotShownForNonHypertextSchemes() {
        let testingURLs = [
            URL(string: "file:///path/to/file.html")!,
            URL(string: "ftp://example.com")!
        ]

        for url in testingURLs {
            let result = policy.shouldShowLoadingIndicator(isLoading: true, url: url, error: nil)
            XCTAssertFalse(result)
        }
    }

    func testLoadingIndicatorIsNotShownForDuckSearchEvenIfOtherConditionsAreMet(isLoading: Bool, error: NSError?) async throws {
        let sampleParameters: [(isLoading: Bool, error: NSError?)] = [(true, nil), (true, NSError.testingError), (false, nil), (false, NSError.testingError)]

        for (isLoading, error) in sampleParameters {
            let searchURL = URL.makeSearchUrl(from: "yosemite")
            let result = policy.shouldShowLoadingIndicator(isLoading: isLoading, url: searchURL, error: error)
            XCTAssertFalse(result)
        }
    }

    // MARK: - Favicon Crossfade Tests

    func testFaviconCrossfadesWhenPlaceholderIsDisplayedAndNewFaviconIsAvailable() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: .demoNetworkImage, oldFavicon: nil, displaysPlaceholder: true)
        XCTAssertTrue(result)
    }

    func testFaviconCrossfadesWhenOldFaviconExistsAndNewFaviconIsDifferent() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: .demoBonjourImage, oldFavicon: .demoNetworkImage, displaysPlaceholder: false)
        XCTAssertTrue(result)
    }

    func testFaviconDoesNotCrossfadeWhenOldFaviconExistsAndNewFaviconIsTheSame() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: .demoNetworkImage, oldFavicon: .demoNetworkImage, displaysPlaceholder: false)
        XCTAssertTrue(result == false)
    }

    func testFaviconDoesNotCrossfadeWhenNothingIsSet() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: nil, oldFavicon: nil, displaysPlaceholder: false)
        XCTAssertTrue(result == false)
    }
}

private extension NSError {
    static var testingError: NSError {
        NSError(domain: "test", code: 42, userInfo: nil)
    }
}

private extension NSImage {

    static var demoBonjourImage: NSImage? {
        NSImage(named: NSImage.bonjourName)
    }

    static var demoNetworkImage: NSImage? {
        NSImage(named: NSImage.networkName)
    }
}
