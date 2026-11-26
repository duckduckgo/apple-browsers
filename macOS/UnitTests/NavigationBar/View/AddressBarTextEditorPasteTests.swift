//
//  AddressBarTextEditorPasteTests.swift
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

@testable import DuckDuckGo_Privacy_Browser

@Suite("Address bar paste: multi-line text")
struct AddressBarTextEditorPasteTests {

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        ("https://duckduckgo.com/?q=duck\nduckgo&ia=web", "https://duckduckgo.com/?q=duckduckgo&ia=web"),
        ("https://claude.ai/oauth/authorize?code=true&redir\nect_uri=https%3A%2F%2Fexample.com", "https://claude.ai/oauth/authorize?code=true&redirect_uri=https%3A%2F%2Fexample.com"),
        ("https://duck\r\nduckgo.com/?q=a\rb\nc\n", "https://duckduckgo.com/?q=abc"),
        ("\n  https://duck\n\nduckgo.com  \n", "https://duckduckgo.com"),
    ])
    func textWithoutSpacesIsJoined(pasted: String, expected: String) {
        #expect(AddressBarTextEditor.singleLineTextForPaste(pasted) == expected)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        ("best pizza\nnear me", "best pizza near me"),
        ("best pizza \n near me", "best pizza near me"),
        ("TODO:\nbuy milk", "TODO: buy milk"),
        ("one two\r\n\r\nthree", "one two three"),
    ])
    func textWithSpacesIsJoinedWithSpaces(pasted: String, expected: String) {
        #expect(AddressBarTextEditor.singleLineTextForPaste(pasted) == expected)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["https://duckduckgo.com", "best pizza near me"])
    func singleLineTextIsLeftToTheDefaultPaste(pasted: String) {
        #expect(AddressBarTextEditor.singleLineTextForPaste(pasted) == nil)
    }
}
