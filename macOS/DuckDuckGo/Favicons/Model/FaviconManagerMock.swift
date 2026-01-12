//
//  FaviconManagerMock.swift
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

#if DEBUG
import AppKit
import Common
import Combine
import Foundation
import History
import WebKit

final class FaviconManagerMock: FaviconManagement {

    @Published var isCacheLoaded = true
    var faviconsLoadedPublisher: Published<Bool>.Publisher { $isCacheLoaded }

    // MARK: - Preview/Test Helpers
    /// Map of host -> image to be returned by getCachedFavicon(for:host:)
    var imagesByHost: [String: NSImage] = [:]

    /// Provide a prebuilt image for a host
    func setImage(_ image: NSImage, forHost host: String) {
        imagesByHost[host] = image
    }

    // MARK: - FaviconManagement

    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL, webView: WKWebView?) async -> Favicon? {
        nil
    }

    func handleFaviconsByDocumentUrl(_ faviconsByDocumentUrl: [URL: [Favicon]]) async {
        // no-op
    }

    func getCachedFaviconURL(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL? {
        return nil
    }

    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        guard let host = documentUrl.host, let image = imagesByHost[host] else { return nil }
        return Favicon(identifier: UUID(), url: documentUrl, image: image, relation: .icon, documentUrl: documentUrl, dateCreated: Date())
    }

    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        guard let image = imagesByHost[host] else { return nil }
        let url = URL(string: "https://\(host)") ?? URL(string: "about:blank")!
        return Favicon(identifier: UUID(), url: url, image: image, relation: .icon, documentUrl: url, dateCreated: Date())
    }

    func getCachedFavicon(forDomainOrAnySubdomain host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        // Try exact host or eTLD+1 stripping a leading subdomain
        if let exact = imagesByHost[host] {
            let url = URL(string: "https://\(host)") ?? URL(string: "about:blank")!
            return Favicon(identifier: UUID(), url: url, image: exact, relation: .icon, documentUrl: url, dateCreated: Date())
        }
        if let base = host.split(separator: ".").suffix(2).joined(separator: ".") as String?, let img = imagesByHost[base] {
            let url = URL(string: "https://\(base)") ?? URL(string: "about:blank")!
            return Favicon(identifier: UUID(), url: url, image: img, relation: .icon, documentUrl: url, dateCreated: Date())
        }
        return nil
    }

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async {
    }

    func burnDomains(_ domains: Set<String>, exceptBookmarks bookmarkManager: any BookmarkManager, exceptSavedLogins: Set<String>, exceptExistingHistory history: BrowsingHistory, tld: TLD) async {
    }
}
#endif
