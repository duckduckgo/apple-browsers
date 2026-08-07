//
//  StringFileExtensionsTests.swift
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

import Common
import Testing

struct StringFileExtensionsTests {

    @available(iOS 16, macOS 13, *)
    @Test("Single extension is allowed", .timeLimit(.minutes(1)), arguments: [
        "bookmarks.html",
        "passwords.csv",
        "cards.json",
        "dir/passwords.csv",
        "nested/dir/bookmarks.html",
        "no-extension",
        ".dotfile"
    ])
    func singleExtensionIsNotFlagged(path: String) {
        #expect(path.hasMultipleFileExtensions == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Double extension is rejected", .timeLimit(.minutes(1)), arguments: [
        "foo.swift.html",
        "a/b.exe.csv",
        "x.html.html",
        "nested/dir/evil.swift.html",
        "report.tar.gz"
    ])
    func doubleExtensionIsFlagged(path: String) {
        #expect(path.hasMultipleFileExtensions == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dots in directory components are ignored", .timeLimit(.minutes(1)))
    func dotsInDirectoryComponentsAreIgnored() {
        // Only the last path component is considered.
        #expect("a.b.c/bookmarks.html".hasMultipleFileExtensions == false)
    }
}
