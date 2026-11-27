//
//  TopSitesPickerFaviconSeederTests.swift
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

import Bookmarks
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class TopSitesPickerFaviconSeederTests: XCTestCase {
    private struct StoredFavicon: Equatable {
        let imageData: Data
        let faviconURL: URL?
        let documentURL: URL
    }

    private final class CapturingFaviconStore: Bookmarks.FaviconStoring {
        var domainsWithFavicon: Set<String> = []
        var stored: [StoredFavicon] = []

        func hasFavicon(for domain: String) -> Bool {
            domainsWithFavicon.contains(domain)
        }

        func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {
            stored.append(StoredFavicon(imageData: imageData, faviconURL: url, documentURL: documentURL))
        }
    }

    private var rootDirectory: URL!
    private var iconsDirectory: URL!

    override func setUpWithError() throws {
        rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        iconsDirectory = rootDirectory.appendingPathComponent("top-sites")
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: rootDirectory)
    }

    @MainActor
    func testSeedFavicons_StoresTheBundledIconOnlyForSitesWithoutAFavicon() async throws {
        let youtubeIcon = try bundleIcon(named: "youtube")
        try bundleIcon(named: "reddit")
        try bundleIcon(named: "secret", in: rootDirectory)
        let faviconStore = CapturingFaviconStore()
        faviconStore.domainsWithFavicon = ["www.reddit.com"]
        let seeder = TopSitesPickerFaviconSeeder(faviconStore: faviconStore, iconsDirectory: iconsDirectory)
        let sites = [
            site(id: "youtube", url: "https://www.youtube.com"),
            site(id: "reddit", url: "https://www.reddit.com"),
            site(id: "netflix", url: "https://www.netflix.com"),
            site(id: "../secret", url: "https://secret.example"),
        ]

        await seeder.seedFavicons(for: sites)

        XCTAssertEqual(faviconStore.stored, [
            StoredFavicon(imageData: youtubeIcon,
                          faviconURL: URL(string: "duck://onboarding/assets/img/v4/top-sites/youtube.png"),
                          documentURL: URL(string: "https://www.youtube.com/")!)
        ])
    }
}

private extension TopSitesPickerFaviconSeederTests {

    @discardableResult
    func bundleIcon(named name: String, in directory: URL? = nil) throws -> Data {
        let data = Data(name.utf8)
        try data.write(to: (directory ?? iconsDirectory).appendingPathComponent(name).appendingPathExtension("png"))
        return data
    }

    func site(id: String, url: String) -> OnboardingUserScript.FavoriteSite {
        OnboardingUserScript.FavoriteSite(id: id, url: URL(string: url)!, title: id)
    }
}
