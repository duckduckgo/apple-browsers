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

import Testing
import Foundation
import AppKit
@testable import DuckDuckGo_Privacy_Browser

@Suite("LoadingIndicatorPolicy Tests", .serialized)
struct LoadingIndicatorPolicyTests {

    private let policy = DefaultLoadingIndicatorPolicy()

    @Test(arguments: [
        URL(string: "https://example.com")!,
        URL(string: "http://example.com")!,
        URL(string: "https://subdomain.example.com/path")!
    ])
    func testLoadingIndicatorIsShownWhenThereAreNoErrorsAndTheURLIsValidHypertextSchema(url: URL) {
        let result = policy.shouldShowLoadingIndicator(isLoading: true, url: url, error: nil)
        #expect(result)
    }

    @Test
    func testLoadingIndicatorIsNotShownWhenURLIsNilEvenIfOtherConditionsAreMet() {
        let result = policy.shouldShowLoadingIndicator(isLoading: true, url: nil, error: nil)
        #expect(result == false)
    }

    @Test
    func testLoadingIndicatorIsNotShownWhenThereAreErrors() {
        let resultWhenLoading = policy.shouldShowLoadingIndicator(isLoading: true, url: .appStore, error: NSError.testingError)
        #expect(resultWhenLoading == false)

        let resultWhenNotLoading = policy.shouldShowLoadingIndicator(isLoading: false, url: .appStore, error: NSError.testingError)
        #expect(resultWhenNotLoading == false)
    }

    @Test(arguments: [URL.newtab, URL.welcome, URL.settings, URL.bookmarks, URL.history])
    func testLoadingIndicatorIsNotShownForDuckSchemaURLs(url: URL) async throws {
        let result = policy.shouldShowLoadingIndicator(isLoading: true, url: url, error: nil)
        #expect(result == false)
        #expect(url.isDuckURLScheme)
    }

    @Test(arguments: [
        URL(string: "file:///path/to/file.html")!,
        URL(string: "ftp://example.com")!,
    ])
    func testLoadingIndicatorIsNotShownForNonHypertextSchemes(url: URL) {
        let result = policy.shouldShowLoadingIndicator(isLoading: true, url: url, error: nil)
        #expect(result == false)
    }

    @Test(arguments: [(true, nil), (true, NSError.testingError), (false, nil), (false, NSError.testingError)])
    func testLoadingIndicatorIsNotShownForDuckSearchEvenIfOtherConditionsAreMet(isLoading: Bool, error: NSError?) async throws {
        let searchURL = URL.makeSearchUrl(from: "yosemite")
        let result = policy.shouldShowLoadingIndicator(isLoading: isLoading, url: searchURL, error: error)
        #expect(result == false)
    }

    // MARK: - Favicon Crossfade Tests

    @Test
    func testFaviconCrossfadesWhenPlaceholderIsDisplayedAndNewFaviconIsAvailable() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: .demoNetworkImage, oldFavicon: nil, displaysPlaceholder: true)
        #expect(result)
    }

    @Test
    func testFaviconCrossfadesWhenOldFaviconExistsAndNewFaviconIsDifferent() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: .demoBonjourImage, oldFavicon: .demoNetworkImage, displaysPlaceholder: false)
        #expect(result)
    }

    @Test
    func testFaviconDoesNotCrossfadeWhenOldFaviconExistsAndNewFaviconIsTheSame() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: .demoNetworkImage, oldFavicon: .demoNetworkImage, displaysPlaceholder: false)
        #expect(result == false)
    }

    @Test
    func testFaviconDoesNotCrossfadeWhenNothingIsSet() {
        let result = policy.shouldCrossfadeFavicon(newFavicon: nil, oldFavicon: nil, displaysPlaceholder: false)
        #expect(result == false)
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
