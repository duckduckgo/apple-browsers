//
//  StringExtensionTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
@testable import DuckDuckGo_Privacy_Browser

class StringExtensionTests: XCTestCase {

    func testHtmlEscapedString() {
        NSError.disableSwizzledDescription = true
        defer { NSError.disableSwizzledDescription = false }

        XCTAssertEqual("\"DuckDuckGo\"®".escapedUnicodeHtmlString(), "&quot;DuckDuckGo&quot;®")
        XCTAssertEqual("i don‘t want to 'sleep'™".escapedUnicodeHtmlString(), "i don‘t want to &apos;sleep&apos;™")
        XCTAssertEqual("{ $embraced [&text]}".escapedUnicodeHtmlString(), "&#123; &#36;embraced &#91;&amp;text&#93;&#125;")
        XCTAssertEqual("X ^ 2 + y / 2 = 4 < 6%".escapedUnicodeHtmlString(), "X &#94; 2 + y &#x2F; 2 &#61; 4 &lt; 6&percnt;")
        XCTAssertEqual("<some&tag>".escapedUnicodeHtmlString(), "&lt;some&amp;tag&gt;")
        XCTAssertEqual("© “text” with «emojis» 🩷🦆".escapedUnicodeHtmlString(), "© “text” with «emojis» 🩷🦆")
        XCTAssertEqual("`my.mail@duck.com`".escapedUnicodeHtmlString(), "&#97;my.mail&#64;duck.com&#97;")
        XCTAssertEqual("<hey beep=\\\"#test\\\" boop='#' fool=1 >floop!<b>burp</b></hey>".escapedUnicodeHtmlString(),
                       "&lt;hey beep&#61;&#92;&quot;&#35;test&#92;&quot; boop&#61;&apos;&#35;&apos; fool&#61;1 &gt;floop&excl;&lt;b&gt;burp&lt;&#x2F;b&gt;&lt;&#x2F;hey&gt;")

        XCTAssertEqual(URLError(URLError.Code.cannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "Could not connect to the server."]).localizedDescription.escapedUnicodeHtmlString(), "Could not connect to the server.")
    }

    func testStringContainsAny() {
        // Positive cases - exact matches
        XCTAssertTrue("a".containsAny(of: ["a", "b"]))
        XCTAssertTrue("hello world".containsAny(of: ["hello", "goodbye"]))
        XCTAssertTrue("test".containsAny(of: ["test"]))

        // Case-insensitive matching
        XCTAssertTrue("AAA".containsAny(of: ["a", "b"]))
        XCTAssertTrue("Hello World".containsAny(of: ["hello", "goodbye"]))
        XCTAssertTrue("UPPERCASE".containsAny(of: ["upper"]))
        XCTAssertTrue("lowercase".containsAny(of: ["LOWER"]))

        // Partial matches
        XCTAssertTrue("bAb".containsAny(of: ["a", "b"]))
        XCTAssertTrue("bAbBb".containsAny(of: ["a", "bbb"]))
        XCTAssertTrue("The quick brown fox".containsAny(of: ["quick", "slow"]))

        // Multiple potential matches (should match on first found)
        XCTAssertTrue("abc".containsAny(of: ["a", "b", "c"]))
        XCTAssertTrue("hello".containsAny(of: ["goodbye", "hello", "hi"]))

        // Negative cases - no matches
        XCTAssertFalse("xyz".containsAny(of: ["a", "b", "c"]))
        XCTAssertFalse("hello".containsAny(of: ["goodbye", "farewell"]))
        XCTAssertFalse("test".containsAny(of: ["different", "words"]))

        // Edge cases
        XCTAssertFalse("".containsAny(of: ["a", "b"]))
        XCTAssertFalse("test".containsAny(of: []))
        XCTAssertFalse("".containsAny(of: []))

        // Empty string in search array
        XCTAssertFalse("test".containsAny(of: ["", "a"]))
        XCTAssertFalse("anything".containsAny(of: [""]))
    }

    func testDropSubdomainDoesntDropDomainWhenTLDHasTwoComponents() {
        let sample = [
            ("lantean.com.ar", "lantean.com.ar"),
        ]

        for (source, expected) in sample {
            XCTAssertEqual(source.dropSubdomain(), expected)
        }
    }

    func testDropSubdomainEffectivelyDropsDomainComponent() {
        let sample = [
            ("www.duckduckgo.com", "duckduckgo.com"),
            ("hostname.duckduckgo.com", "duckduckgo.com"),
            ("www.lantean.co", "lantean.co"),
            ("www.lantean.com.ar", "lantean.com.ar")
        ]

        for (source, expected) in sample {
            XCTAssertEqual(source.dropSubdomain(), expected)
        }
    }
}
