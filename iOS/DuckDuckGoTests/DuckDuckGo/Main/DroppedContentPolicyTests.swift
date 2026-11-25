//
//  DroppedContentPolicyTests.swift
//  DuckDuckGo
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

import Foundation
import Testing
@testable import DuckDuckGo

struct DroppedContentPolicyTests {

    @available(iOS 16, macOS 13, *)
    @Test(
        "A dropped URL that doesn't run script is allowed",
        .timeLimit(.minutes(1)),
        arguments: ["https://duckduckgo.com", "http://example.com/path?q=1", "HTTPS://EXAMPLE.COM", "file:///private/var/mobile/Documents/report.pdf", "mailto:someone@example.com"]
    )
    func allowsNonScriptURL(_ string: String) throws {
        // GIVEN
        let url = try #require(URL(string: string))

        // WHEN
        let result = DroppedContentPolicy.allows(url)

        // THEN
        #expect(result)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "A dropped URL with a script scheme is rejected",
        .timeLimit(.minutes(1)),
        arguments: ["javascript:prompt(1337);//", "JavaScript:prompt(1337)"]
    )
    func rejectsScriptURL(_ string: String) throws {
        // GIVEN
        let url = try #require(URL(string: string))

        // WHEN
        let result = DroppedContentPolicy.allows(url)

        // THEN
        #expect(!result)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "Dropped text that is a search or an address is allowed",
        .timeLimit(.minutes(1)),
        arguments: ["duck ducks", "duckduckgo.com", "https://duckduckgo.com", "how to use javascript: a guide"]
    )
    func allowsSearchText(_ string: String) {
        // GIVEN
        let text = string

        // WHEN
        let result = DroppedContentPolicy.allows(text)

        // THEN
        #expect(result)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "Dropped text naming a script scheme is rejected",
        .timeLimit(.minutes(1)),
        arguments: ["javascript:prompt(1337);//", "JAVASCRIPT:prompt(1337)", "   javascript:prompt(1337)", "\njavascript:prompt(1337)"]
    )
    func rejectsScriptText(_ string: String) {
        // GIVEN
        let text = string

        // WHEN
        let result = DroppedContentPolicy.allows(text)

        // THEN
        #expect(!result)
    }
}
