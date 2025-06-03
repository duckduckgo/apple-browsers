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
import Common
import History

final class FaviconManagerMock: FaviconManagement {

    func loadFavicons() {}
    @Published var isCacheLoaded = true
    var faviconsLoadedPublisher: Published<Bool>.Publisher { $isCacheLoaded }

    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL) async -> Favicon? {
        nil
    }

    func handleFaviconsByDocumentUrl(_ faviconsByDocumentUrl: [URL: [Favicon]]) async {
        // no-op
    }

    func getCachedFaviconURL(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL? {
        return nil
    }

    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        return nil
    }

    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        return nil
    }

    func getCachedFavicon(forDomainOrAnySubdomain host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        return nil
    }

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async {
    }

    func burnDomains(_ domains: Set<String>, exceptBookmarks bookmarkManager: any BookmarkManager, exceptSavedLogins: Set<String>, exceptExistingHistory history: BrowsingHistory, tld: TLD) async {
    }
}
#endif
