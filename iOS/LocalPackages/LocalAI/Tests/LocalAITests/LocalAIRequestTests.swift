//
//  LocalAIRequestTests.swift
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
@testable import LocalAI

@Suite("Suggestion id → local request")
struct LocalAIRequestTests {

    let page = LocalAIPage(title: "Title", url: "https://example.com", content: "Body")

    @available(iOS 16, macOS 13, *)
    @Test("Each local suggestion maps to its task and source", .timeLimit(.minutes(1)),
          arguments: [
            ("summarize-page", LocalAITask.summarize, LocalAITarget.page),
            ("translate-page", .translate, .page),
            ("summarize-selection", .summarize, .selection),
            ("translate-selection", .translate, .selection)
          ])
    func mapsSuggestion(id: String, task: LocalAITask, target: LocalAITarget) throws {
        let request = try #require(LocalAIRequest(suggestionID: id, language: "English", page: page, selections: ["Selected"]))

        #expect(request.task == task)
        switch target {
        case .page: #expect(request.source == .page(page))
        case .selection: #expect(request.source == .selection(["Selected"]))
        }
        #expect(request.language == "English")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Other suggestions stay with Duck.ai", .timeLimit(.minutes(1)))
    func unknownSuggestionIsNotLocal() {
        #expect(LocalAIRequest(suggestionID: "key-takeaways", language: "English", page: page, selections: ["Selected"]) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page action without page content stays with Duck.ai", .timeLimit(.minutes(1)))
    func pageActionNeedsContent() {
        #expect(LocalAIRequest(suggestionID: "summarize-page", language: "English", page: nil, selections: []) == nil)
        let empty = LocalAIPage(title: "Title", url: "", content: "")
        #expect(LocalAIRequest(suggestionID: "summarize-page", language: "English", page: empty, selections: []) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A selection action without a selection stays with Duck.ai", .timeLimit(.minutes(1)))
    func selectionActionNeedsSelection() {
        #expect(LocalAIRequest(suggestionID: "translate-selection", language: "English", page: page, selections: [""]) == nil)
    }
}
