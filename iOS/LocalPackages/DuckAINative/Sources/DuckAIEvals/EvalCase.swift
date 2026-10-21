//
//  EvalCase.swift
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

import DuckAIChatCore
import DuckAILocalTasks
import Foundation

/// One fixed input the evals run through every provider. Codable so a set can be stored, shared and replayed.
public struct EvalCase: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let task: EvalTask
    public let page: EvalPage?
    public let selection: String?
    /// Target language for translate tasks, and the UI language for suggested prompts, e.g. "German".
    public let languageName: String?

    public init(id: String, task: EvalTask, page: EvalPage?, selection: String?, languageName: String?) {
        self.id = id
        self.task = task
        self.page = page
        self.selection = selection
        self.languageName = languageName
    }
}

public enum EvalTask: String, Codable, CaseIterable, Sendable {
    case summarizePage
    case translatePage
    case summarizeSelection
    case translateSelection
    case suggestPrompts
}

public struct EvalPage: Codable, Equatable, Sendable {
    public let title: String
    public let url: URL?
    public let content: String
    public let language: String?

    public init(title: String, url: URL?, content: String, language: String?) {
        self.title = title
        self.url = url
        self.content = content
        self.language = language
    }
}

public extension EvalCase {
    /// The exact turn the app would send for this case: summarize and translate go through `PromptBuilder` from the same
    /// first user message the contextual sheet builds; suggested prompts go through `SuggestedPromptsPrompt`.
    /// Throws for a case missing what its task needs (no page for a page task, no selection for a selection task).
    func turn(conversation: ConversationID, budget: PromptBudget) throws -> ProviderTurn {
        if task == .suggestPrompts {
            guard let page else { throw EvalCaseError.missingInput(caseID: id) }
            return SuggestedPromptsPrompt.turn(
                for: PageSnapshot(title: page.title, url: page.url, content: page.content, language: page.language),
                count: 4, uiLanguageName: languageName ?? "English", conversation: conversation)
        }
        let request: ChatRequest
        switch task {
        case .translatePage, .translateSelection:
            request = .translate(into: TargetLanguage(code: "", name: languageName ?? "English"))
        default:
            request = .summarize
        }
        let context: ChatContext
        switch task {
        case .summarizeSelection, .translateSelection:
            guard let selection else { throw EvalCaseError.missingInput(caseID: id) }
            context = try ChatContext(page: nil, selections: [Selection(title: page?.title ?? "", url: page?.url, content: selection)],
                                      opening: .request(request))
        default:
            guard let page else { throw EvalCaseError.missingInput(caseID: id) }
            context = try ChatContext(page: PageContext(title: page.title, url: page.url, content: page.content),
                                      selections: [], opening: .request(request))
        }
        let message = UserMessage(id: MessageID(rawValue: 1), createdAt: Date(), parts: context.contextParts.map(UserPart.context))
        return try PromptBuilder.turn(conversation: conversation, messages: [.user(message)], budget: budget).get()
    }
}

public enum EvalCaseError: Error, Equatable {
    case missingInput(caseID: String)
}
