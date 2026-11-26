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

@Suite("Address bar paste: URLs wrapped across lines")
struct AddressBarTextEditorPasteTests {

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func lineBreakInQueryValueIsRemoved(useUnifiedLogic: Bool) {
        let result = AddressBarTextEditor.urlStringRemovingLineBreaks(from: "https://duckduckgo.com/?q=duck\nduckgo&ia=web", useUnifiedLogic: useUnifiedLogic)
        #expect(result == "https://duckduckgo.com/?q=duckduckgo&ia=web")
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func lineBreakInParameterNameIsRemoved(useUnifiedLogic: Bool) {
        let result = AddressBarTextEditor.urlStringRemovingLineBreaks(from: "https://claude.ai/oauth/authorize?code=true&redir\nect_uri=https%3A%2F%2Fexample.com", useUnifiedLogic: useUnifiedLogic)
        #expect(result == "https://claude.ai/oauth/authorize?code=true&redirect_uri=https%3A%2F%2Fexample.com")
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func crlfAndMultipleBreaksAreRemoved(useUnifiedLogic: Bool) {
        let result = AddressBarTextEditor.urlStringRemovingLineBreaks(from: "https://duck\r\nduckgo.com/?q=a\rb\nc\n", useUnifiedLogic: useUnifiedLogic)
        #expect(result == "https://duckduckgo.com/?q=abc")
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func multiLineSearchTextIsLeftAlone(useUnifiedLogic: Bool) {
        let result = AddressBarTextEditor.urlStringRemovingLineBreaks(from: "best pizza\nnear me", useUnifiedLogic: useUnifiedLogic)
        #expect(result == nil)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func singleLineTextIsLeftAlone(useUnifiedLogic: Bool) {
        let result = AddressBarTextEditor.urlStringRemovingLineBreaks(from: "https://duckduckgo.com", useUnifiedLogic: useUnifiedLogic)
        #expect(result == nil)
    }
}
