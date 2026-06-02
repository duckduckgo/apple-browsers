//
//  BookmarkImportSchemeValidationTests.swift
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

import Bookmarks
import Testing

struct BookmarkImportSchemeValidationTests {

    @Test("Unsafe schemes are detected", arguments: [
        "javascript:alert(1)",
        "JavaScript:alert(1)",
        "  javascript:alert(1)",
        "data:text/html,<script>alert(1)</script>",
        "DATA:text/html;base64,AAAA"
    ])
    func unsafeSchemesDetected(urlString: String) {
        #expect(urlString.hasUnsafeBookmarkImportScheme() == true)
    }

    @Test("Safe URLs are not flagged", arguments: [
        "https://duckduckgo.com",
        "http://example.com",
        "ftp://files.example.com",
        "about:blank",
        "https://example.com?q=javascript:foo" // scheme is https, not javascript
    ])
    func safeURLsAllowed(urlString: String) {
        #expect(urlString.hasUnsafeBookmarkImportScheme() == false)
    }

    @Test("Bookmark or favorite with an unsafe scheme is invalid")
    func unsafeSchemeBookmarkIsInvalid() {
        let jsBookmark = BookmarkOrFolder(name: "x", type: .bookmark, urlString: "javascript:alert(1)", children: nil)
        let dataFavorite = BookmarkOrFolder(name: "x", type: .favorite, urlString: "data:text/html,x", children: nil)

        #expect(jsBookmark.isInvalidBookmark)
        #expect(dataFavorite.isInvalidBookmark)
    }

    @Test("Bookmark with a safe scheme is valid")
    func safeSchemeBookmarkIsValid() {
        let bookmark = BookmarkOrFolder(name: "x", type: .bookmark, urlString: "https://duckduckgo.com", children: nil)

        #expect(bookmark.isInvalidBookmark == false)
    }

    @Test("Bookmark with no URL is invalid")
    func bookmarkWithoutURLIsInvalid() {
        let bookmark = BookmarkOrFolder(name: "x", type: .bookmark, urlString: nil, children: nil)

        #expect(bookmark.isInvalidBookmark)
    }

    @Test("Folder is never invalidated by the scheme check")
    func folderIsValid() {
        let folder = BookmarkOrFolder(name: "f", type: .folder, urlString: nil, children: [])

        #expect(folder.isInvalidBookmark == false)
    }
}
