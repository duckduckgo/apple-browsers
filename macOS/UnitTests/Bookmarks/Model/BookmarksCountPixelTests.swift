//
//  BookmarksCountPixelTests.swift
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

import PixelKit
import PixelKitTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class BookmarksCountPixelTests: XCTestCase {
    func testBookmarksCountBucketsAtBoundaries() {
        let expectedBuckets: [(count: Int, bucket: BookmarksPixel.BookmarksCountBucket)] = [
            (0, .zero),
            (1, .oneToTen),
            (10, .oneToTen),
            (11, .elevenToFifty),
            (50, .elevenToFifty),
            (51, .fiftyOneToOneHundred),
            (100, .fiftyOneToOneHundred),
            (101, .oneHundredOneToFiveHundred),
            (500, .oneHundredOneToFiveHundred),
            (501, .fiveHundredOneOrMore),
        ]

        for (count, expectedBucket) in expectedBuckets {
            XCTAssertEqual(BookmarksPixel.BookmarksCountBucket(count), expectedBucket, "count: \(count)")
        }
    }

    func testPixelContainsOnlyBucketedCountAndPixelSourceStandardParameter() throws {
        let pixel = BookmarksPixel.count(.elevenToFifty)

        XCTAssertEqual(pixel.name, "bookmarks_count")
        XCTAssertEqual(pixel.parameters, ["bookmarks_count_bucket": "11-50"])
        XCTAssertEqual(pixel.standardParameters?.count, 1)

        let standardParameter = try XCTUnwrap(pixel.standardParameters?.first)
        guard case .pixelSource = standardParameter else {
            return XCTFail("Expected pixelSource standard parameter")
        }
    }

    func testPixelFiresWithConfiguredFrequencyAndBucketedCount() {
        let pixel = BookmarksPixel.count(.init(51))
        let pixelFiring = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: pixel, frequency: .daily),
        ])

        pixel.fire(pixelFiring: pixelFiring)

        pixelFiring.verifyExpectations()
    }

    func testBookmarkListCountIncludesFavoritesAndNestedBookmarksButExcludesFolders() {
        let favorite = Bookmark(id: "favorite", url: "https://favorite.example", title: "Favorite", isFavorite: true)
        let nestedBookmark = Bookmark(id: "nested", url: "https://nested.example", title: "Nested", isFavorite: false)
        let folder = BookmarkFolder(id: "folder", title: "Folder", children: [nestedBookmark])
        let bookmarkList = BookmarkList(entities: [favorite, folder, nestedBookmark])

        XCTAssertEqual(bookmarkList.totalBookmarks, 2)
    }
}
