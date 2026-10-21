//
//  DuckAIRoutingTests.swift
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

import DuckAINative
import Testing

@Suite struct DuckAIRoutingTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func everythingIsWebByDefault() {
        let routing = DuckAIRouting()

        #expect(!routing.answersNatively(.chat))
        #expect(!routing.answersNatively(.pageAction))
        #expect(!routing.answersNatively(.selectionAction))
        #expect(!routing.generatesSuggestedPromptsLocally)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func localActionsLeaveChatOnTheWeb() {
        let routing = DuckAIRouting(pageActions: .local, selectionActions: .local)

        #expect(routing.answersNatively(.pageAction))
        #expect(routing.answersNatively(.selectionAction))
        #expect(!routing.answersNatively(.chat))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func eachRowIsIndependent() {
        #expect(DuckAIRouting(chat: .native).answersNatively(.chat))
        #expect(!DuckAIRouting(chat: .native).answersNatively(.pageAction))
        #expect(DuckAIRouting(selectionActions: .local).answersNatively(.selectionAction))
        #expect(!DuckAIRouting(selectionActions: .local).answersNatively(.pageAction))
        #expect(DuckAIRouting(suggestedPrompts: .localModel).generatesSuggestedPromptsLocally)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func suggestionIDsMapToTheirEntry() {
        #expect(DuckAIRouting.entry(forSuggestionID: "summarize-page") == .pageAction)
        #expect(DuckAIRouting.entry(forSuggestionID: "translate-page") == .pageAction)
        #expect(DuckAIRouting.entry(forSuggestionID: "summarize-selection") == .selectionAction)
        #expect(DuckAIRouting.entry(forSuggestionID: "translate-selection") == .selectionAction)
        #expect(DuckAIRouting.entry(forSuggestionID: "key-takeaways") == .chat)
    }
}
