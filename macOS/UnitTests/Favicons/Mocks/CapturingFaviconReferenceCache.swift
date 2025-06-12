//
//  CapturingFaviconReferenceCache.swift
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

import Common
import Foundation

@testable import DuckDuckGo_Privacy_Browser

final class CapturingFaviconReferenceCache: FaviconReferenceCaching {

    init() {}

    init(faviconStoring: any FaviconStoring) {}

    var loaded: Bool = false

    @MainActor
    func load() async throws {
        loadCallsCount += 1
    }

    var hostReferences: [String: FaviconHostReference] = [:]
    var urlReferences: [URL: FaviconUrlReference] = [:]

    @MainActor
    func insert(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL) {
        insertCalls.append(.init(faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl, documentUrl))
    }

    func getFaviconUrl(for documentURL: URL, sizeCategory: Favicon.SizeCategory) -> URL? {
        getFaviconURLForDocumentURLCalls.append(.init(documentURL, sizeCategory))
        return getFaviconURLForDocumentURL(documentURL, sizeCategory)
    }

    func getFaviconUrl(for host: String, sizeCategory: Favicon.SizeCategory) -> URL? {
        getFaviconURLForHostCalls.append(.init(host, sizeCategory))
        return getFaviconURLForHost(host, sizeCategory)
    }

    func cleanOld(except fireproofDomains: FireproofDomains, bookmarkManager: any BookmarkManager) async {
        cleanCallsCount += 1
    }

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: any BookmarkManager, savedLogins: Set<String>) async {
        burnCallsCount += 1
    }

    func burnDomains(_ baseDomains: Set<String>, exceptBookmarks bookmarkManager: any BookmarkManager, exceptSavedLogins logins: Set<String>, exceptHistoryDomains history: Set<String>, tld: TLD) async {
        burnDomainsCallsCount += 1
    }

    struct Insert: Equatable {
        let smallURL: URL?
        let mediumURL: URL?
        let documentURL: URL

        init(_ smallURL: URL?, _ mediumURL: URL?, _ documentURL: URL) {
            self.smallURL = smallURL
            self.mediumURL = mediumURL
            self.documentURL = documentURL
        }
    }

    struct GetFaviconURLForDocumentURL: Equatable {
        let documentURL: URL
        let sizeCategory: Favicon.SizeCategory

        init(_ documentURL: URL, _ sizeCategory: Favicon.SizeCategory) {
            self.documentURL = documentURL
            self.sizeCategory = sizeCategory
        }
    }

    struct GetFaviconURLForHost: Equatable {
        let host: String
        let sizeCategory: Favicon.SizeCategory

        init(_ host: String, _ sizeCategory: Favicon.SizeCategory) {
            self.host = host
            self.sizeCategory = sizeCategory
        }
    }

    var loadCallsCount: Int = 0
    var insertCalls: [Insert] = []
    var getFaviconURLForDocumentURLCalls: [GetFaviconURLForDocumentURL] = []
    var getFaviconURLForHostCalls: [GetFaviconURLForHost] = []

    var cleanCallsCount: Int = 0
    var burnCallsCount: Int = 0
    var burnDomainsCallsCount: Int = 0

    var getFaviconURLForDocumentURL: (URL, Favicon.SizeCategory) -> URL? = { _, _ in nil }
    var getFaviconURLForHost: (String, Favicon.SizeCategory) -> URL? = { _, _ in nil }
}
