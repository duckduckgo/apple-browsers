//
//  URLInputClassifierTests.swift
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

import CustomDump
import Foundation
import Testing
@testable import AppRouting

@Suite("URL Input Classifier")
struct URLInputClassifierTests {

    @Test("Supported URL inputs are classified as navigation")
    func whenInputIsAValidWebURLThenItIsReturned() {
        let inputs = [
            "https://blah.accountants",
            "http://www.veganchic.com/products/Camo-High-Top-Sneaker-by-The-Critical-Slide-Societ+80758-0180.html",
            "https://example.com/path?x=1",
            "http://localhost",
            "http://localserver",
            "duck://example.com/path",
            "example.com",
            "localhost/path",
            "myhost.local",
            "82.xn--b1aew.xn--p1ai",
            "121.33.2.11/path",
            "test.com?s=dafas&d=342",
            "https://m.facebook.com/?refsrc=https%3A%2F%2Fwww.facebook.com%2F&_rdr"
        ]
        let expected = [
            "https://blah.accountants",
            "http://www.veganchic.com/products/Camo-High-Top-Sneaker-by-The-Critical-Slide-Societ+80758-0180.html",
            "https://example.com/path?x=1",
            "http://localhost",
            "http://localserver",
            "duck://example.com/path",
            "http://example.com",
            "http://localhost/path",
            "http://myhost.local",
            "http://82.xn--b1aew.xn--p1ai",
            "http://121.33.2.11/path",
            "http://test.com?s=dafas&d=342",
            "https://m.facebook.com/?refsrc=https%3A%2F%2Fwww.facebook.com%2F&_rdr"
        ]

        expectNoDifference(inputs.map { URLInputClassifier.webURL(from: $0)?.absoluteString }, expected.map(Optional.some))
    }

    @Test("Unsupported or malformed URL inputs are rejected")
    func whenInputIsNotAValidWebURLThenItIsRejected() {
        let inputs = [
            "randomtext",
            "33",
            ".randomtext",
            "randomtext.",
            "http",
            "http:",
            "http:/",
            "https",
            "https:",
            "https:/",
            "asdas://test.com",
            "asdas://121.33.2.11",
            "asdas://localhost",
            "http://test .com",
            "test!com.com",
            "121.33.33.",
            "localserver",
            "1.4"
        ]

        let expected: [URL?] = Array(repeating: nil, count: inputs.count)
        expectNoDifference(inputs.map { URLInputClassifier.webURL(from: $0) }, expected)
    }

    @Test("Address-bar validation rejects whitespace")
    func whenAddressBarInputContainsWhitespaceThenItIsRejected() {
        #expect(URLInputClassifier.isValidAddressBarURLInput("https://example.com/path"))
        #expect(URLInputClassifier.isValidAddressBarURLInput("example.com"))
        #expect(!URLInputClassifier.isValidAddressBarURLInput("https://example .com"))
        #expect(!URLInputClassifier.isValidAddressBarURLInput("example com"))
    }
}
