//
//  SafariDataImporterTests.swift
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

import AppKit
import CryptoKit
import Foundation
import GRDB
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SafariDataImporterTests: XCTestCase {

    @MainActor
    func testWhenImportingBookmarks_FaviconsAreHandledAsBitmaps_IncludingSVGsThatCrashCoreSVG() async throws {
        let profileURL = try makeProfileWithFavicons(["svg.example": Data(FaviconTestFixtures.recursiveFilterSVG.utf8),
                                                      "broken.example": Data("not an image".utf8)])
        let faviconManager = FaviconManagerMock()
        let importer = SafariDataImporter(profile: .init(browser: .safari, profileURL: profileURL),
                                          bookmarkImporter: MockBookmarkImporter(importBookmarks: { _, _, _, _ in .init(successful: 0, duplicates: 0, failed: 0) }),
                                          faviconManager: faviconManager,
                                          faviconRasterizer: FaviconTestFixtures.makeRasterizer())

        _ = await importer.importData(types: [.bookmarks]).task.value

        let handled = try XCTUnwrap(faviconManager.handledFaviconsByDocumentUrl.first)
        let svgImage = try XCTUnwrap(handled[try XCTUnwrap(URL(string: "https://svg.example"))]?.first?.image)
        XCTAssertTrue(svgImage.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(svgImage.hasVisiblePixels())
        XCTAssertNil(handled[try XCTUnwrap(URL(string: "https://broken.example"))]?.first?.image)
        XCTAssertEqual(handled.count, 2)
    }

    /// A Safari profile folder with the test bookmarks and a favicons cache holding the given icons (host to image
    /// data). Safari names each image file after the MD5 hash of its host.
    private func makeProfileWithFavicons(_ dataByHost: [String: Data]) throws -> URL {
        let profileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cacheURL = profileURL.appendingPathComponent("Touch Icons Cache")
        let imagesURL = cacheURL.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: profileURL) }
        try FileManager.default.copyItem(at: resourceURL().appendingPathComponent("Bookmarks.plist"),
                                         to: profileURL.appendingPathComponent("Bookmarks.plist"))

        let queue = try DatabaseQueue(path: cacheURL.appendingPathComponent("TouchIconCacheSettings.db").path)
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE cache_settings (host TEXT)")
            for (host, data) in dataByHost {
                try database.execute(sql: "INSERT INTO cache_settings (host) VALUES (?)", arguments: [host])
                let hash = Insecure.MD5.hash(data: Data(host.utf8)).map { String(format: "%02hhx", $0) }.joined().uppercased()
                try data.write(to: imagesURL.appendingPathComponent(hash).appendingPathExtension("png"))
            }
        }
        return profileURL
    }

    private func resourceURL() -> URL {
        let bundle = Bundle(for: SafariBookmarksReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestSafariData")
    }
}
