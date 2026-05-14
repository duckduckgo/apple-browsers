//
//  FaviconsTabExtensionTests.swift
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

import Combine
import UserScript
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FaviconsTabExtensionTests: XCTestCase {

    var mockFaviconManagement: MockFaviconManagement!
    var scriptsSubject: PassthroughSubject<MockFaviconUserScriptProvider, Never>!
    var contentSubject: PassthroughSubject<Tab.TabContent, Never>!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockFaviconManagement = MockFaviconManagement()
        scriptsSubject = PassthroughSubject()
        contentSubject = PassthroughSubject()
        cancellables = []
    }

    override func tearDown() {
        mockFaviconManagement = nil
        scriptsSubject = nil
        contentSubject = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Delegate Tests

    @MainActor
    func testFaviconUserScriptDelegateIsSetWhenScriptsPublished() {
        let faviconScript = FaviconUserScript()
        let provider = MockFaviconUserScriptProvider(faviconScript: faviconScript)

        let extension_ = FaviconsTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            faviconManagement: mockFaviconManagement
        )

        // Initially delegate should be nil
        XCTAssertNil(faviconScript.delegate)

        // Publish scripts
        scriptsSubject.send(provider)

        // Allow async task to complete
        let expectation = expectation(description: "Delegate set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Delegate should now be set
        XCTAssertTrue(faviconScript.delegate === extension_)
    }

    @MainActor
    func testFaviconLinksArePassedToFaviconManagement() async {
        let faviconScript = FaviconUserScript()
        let provider = MockFaviconUserScriptProvider(faviconScript: faviconScript)

        let documentUrl = URL(string: "https://example.com")!
        let faviconUrl = URL(string: "https://example.com/favicon.ico")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: faviconUrl, rel: "icon", type: "image/x-icon")
        ]

        let extension_ = FaviconsTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            faviconManagement: mockFaviconManagement
        )

        // Set up content
        contentSubject.send(.url(documentUrl, credential: nil, source: .userEntered("")))

        // Publish scripts and wait for delegate to be set
        scriptsSubject.send(provider)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Call the delegate method
        extension_.faviconUserScript(faviconScript, didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        // Wait for async handling
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Verify FaviconManagement received the links
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.count, 1)
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.first?.links.count, 1)
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.first?.documentUrl, documentUrl)
    }

    @MainActor
    func testFaviconLinksIgnoredWhenDocumentUrlDoesNotMatch() async {
        let faviconScript = FaviconUserScript()
        let provider = MockFaviconUserScriptProvider(faviconScript: faviconScript)

        let contentUrl = URL(string: "https://example.com")!
        let differentUrl = URL(string: "https://different.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.ico")!, rel: "icon")
        ]

        let extension_ = FaviconsTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            faviconManagement: mockFaviconManagement
        )

        // Set up content
        contentSubject.send(.url(contentUrl, credential: nil, source: .userEntered("")))

        // Publish scripts and wait
        scriptsSubject.send(provider)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Call delegate with different URL
        extension_.faviconUserScript(faviconScript, didFindFaviconLinks: faviconLinks, for: differentUrl, in: nil)

        // Wait for any async handling
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Verify FaviconManagement was NOT called (URLs don't match)
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.count, 0)
    }

    @MainActor
    func testFaviconLinksIgnoredForErrorUrl() async {
        let faviconScript = FaviconUserScript()
        let provider = MockFaviconUserScriptProvider(faviconScript: faviconScript)
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.ico")!, rel: "icon")
        ]

        let extension_ = FaviconsTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            faviconManagement: mockFaviconManagement
        )

        // Set up content with error URL
        contentSubject.send(.url(.error, credential: nil, source: .userEntered("")))

        // Publish scripts and wait
        scriptsSubject.send(provider)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Call delegate with error URL
        extension_.faviconUserScript(faviconScript, didFindFaviconLinks: faviconLinks, for: .error, in: nil)

        // Wait for any async handling
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Verify FaviconManagement was NOT called
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.count, 0)
    }

    @MainActor
    func testFaviconPublisherEmitsWhenFaviconChanges() async {
        let faviconScript = FaviconUserScript()
        let provider = MockFaviconUserScriptProvider(faviconScript: faviconScript)

        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.ico")!, rel: "icon")
        ]

        // Set up mock to return a favicon
        let testImage = NSImage(size: NSSize(width: 16, height: 16))
        mockFaviconManagement.faviconToReturn = Favicon(image: testImage, url: documentUrl, dateCreated: Date())

        let extension_ = FaviconsTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            faviconManagement: mockFaviconManagement
        )

        var receivedFavicon: NSImage?
        let faviconExpectation = expectation(description: "Favicon received")

        extension_.faviconPublisher
            .sink { favicon in
                receivedFavicon = favicon
                faviconExpectation.fulfill()
            }
            .store(in: &cancellables)

        // Set up content
        contentSubject.send(.url(documentUrl, credential: nil, source: .userEntered("")))

        // Publish scripts and wait
        scriptsSubject.send(provider)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Call delegate
        extension_.faviconUserScript(faviconScript, didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        await fulfillment(of: [faviconExpectation], timeout: 2.0)

        XCTAssertNotNil(receivedFavicon)
    }

    // MARK: - Multiple Favicon Links Tests

    @MainActor
    func testMultipleFaviconLinksArePassedToManagement() async {
        let faviconScript = FaviconUserScript()
        let provider = MockFaviconUserScriptProvider(faviconScript: faviconScript)

        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.ico")!, rel: "icon", type: "image/x-icon"),
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.png")!, rel: "icon", type: "image/png"),
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/apple-touch-icon.png")!, rel: "apple-touch-icon")
        ]

        let extension_ = FaviconsTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            faviconManagement: mockFaviconManagement
        )

        // Set up content
        contentSubject.send(.url(documentUrl, credential: nil, source: .userEntered("")))

        // Publish scripts and wait
        scriptsSubject.send(provider)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Call delegate with multiple links
        extension_.faviconUserScript(faviconScript, didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        // Wait for async handling
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Verify all links were passed
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.count, 1)
        XCTAssertEqual(mockFaviconManagement.handleFaviconLinksCalls.first?.links.count, 3)
    }
}

// MARK: - Mocks

private struct MockFaviconUserScriptProvider: FaviconUserScriptProvider {
    let faviconScript: FaviconUserScript
}

private final class MockFaviconManagement: FaviconManagement {
    var isCacheLoaded: Bool = true
    var handleFaviconLinksCalls: [(links: [FaviconUserScript.FaviconLink], documentUrl: URL)] = []
    var faviconToReturn: Favicon?

    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL, webView: WebKit.WKWebView?) async -> Favicon? {
        handleFaviconLinksCalls.append((links: faviconLinks, documentUrl: documentUrl))
        return faviconToReturn
    }

    // MARK: - Other FaviconManagement requirements (stubs)

    var store: FaviconStoring { fatalError("Not implemented") }

    func populateFaviconCache(bookmarkManager: BookmarkManager, waitFor timeout: TimeInterval) async {}

    func getCachedFavicon(for documentURL: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? { nil }
    func getCachedFavicon(forUrlOrAnySubdomain url: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? { nil }
    func getCachedFavicon(forDomainOrAnySubdomain baseDomain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? { nil }
    func getCachedFaviconURL(for documentURL: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL? { nil }
    func getFaviconURLForDomainMatch(documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL? { nil }
    func getCachedFaviconURL(forDomainOrAnySubdomain baseDomain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL? { nil }

    func loadFavicons(forDomainOrAnySubdomain baseDomain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) async -> [Favicon] { [] }
    func loadFavicons(forHost host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) async -> [Favicon] { [] }
    func loadFaviconImages(forHost host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) async -> [NSImage] { [] }

    func burnExcept(fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager) async {}
    func burnDomains(_ domains: Set<String>, exceptBookmarks bookmarkManager: BookmarkManager) {}
    func burnAllExceptBookmarked(_ bookmarkManager: BookmarkManager) {}
    func handleFaviconsByDocumentUrl(_ faviconsByDocumentUrl: [URL: [Favicon]]) {}
}
