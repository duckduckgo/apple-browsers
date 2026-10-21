//
//  AppleTabOrganizer.swift
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
import FoundationModels

/// Organizes tabs with Apple's on-device model. Its context is ~4k tokens, so the tab list is kept short.
@available(macOS 26.0, *)
final class AppleTabOrganizer: TabOrganizing {

    static let maxPromptCharacters = 10_000

    private static let topicInstructions = """
    You sort a person's open browser tabs into at most 5 broad topics. \
    Tabs about the same trip, project or purchase share one topic. \
    Give every tab in the list exactly one label.
    """

    private static let instructionInstructions = """
    You help a person act on their open browser tabs. Judge each tab by its title, site and content. \
    Only use tab numbers from the list.
    """

    func organize(_ tabs: [TabSnapshot], request: TabOrganizerRequest) async throws -> TabOrganizerProposal {
        guard !tabs.isEmpty else { throw TabOrganizerError.noTabs }
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            throw TabOrganizerError.modelUnavailable(String(describing: reason))
        }

        let tabList = Self.tabList(for: tabs)
        switch request {
        case .groupByTopic:
            let session = LanguageModelSession(instructions: Self.topicInstructions)
            let response = try await session.respond(to: "Tabs:\n\(tabList)", generating: GeneratedTopicResponse.self).content
            return TabOrganizerProposalBuilder.proposal(from: response.contract, tabs: tabs)
        case .instruction(let text):
            let session = LanguageModelSession(instructions: Self.instructionInstructions)
            let prompt = "Tabs:\n\(tabList)\n\nRequest: \(text)"
            let response = try await session.respond(to: prompt, generating: GeneratedInstructionResponse.self).content
            return TabOrganizerProposalBuilder.proposal(from: response.contract, tabs: tabs)
        }
    }

    /// One line per tab: "3. Title — host/path [pageType]: excerpt". Excerpts shrink until the list fits.
    static func tabList(for tabs: [TabSnapshot]) -> String {
        func lines(excerptLimit: Int) -> String {
            tabs.enumerated().map { index, tab in
                var line = "\(index + 1). \(tab.title) — \(tab.host)\(tab.path)"
                if let pageType = tab.pageType { line += " [\(pageType)]" }
                if let excerpt = tab.excerpt, excerptLimit > 0 { line += ": \(excerpt.prefix(excerptLimit))" }
                return line
            }.joined(separator: "\n")
        }

        var excerptLimit = tabs.compactMap { $0.excerpt?.count }.max() ?? 0
        var list = lines(excerptLimit: excerptLimit)
        while list.count > maxPromptCharacters, excerptLimit > 0 {
            excerptLimit /= 2
            list = lines(excerptLimit: excerptLimit)
        }
        return list
    }
}

// MARK: - Generable mirrors of the response contract

@available(macOS 26.0, *)
@Generable
enum GeneratedTabAction {
    case keep
    case close
    case moveToNewWindow

    var contract: TabGroupAction {
        switch self {
        case .keep: return .keep
        case .close: return .close
        case .moveToNewWindow: return .moveToNewWindow
        }
    }
}

@available(macOS 26.0, *)
@Generable
struct GeneratedTopicLabel {
    var tabNumber: Int
    @Guide(description: "Broad topic, 1 to 2 words, reused across tabs")
    var topic: String
}

@available(macOS 26.0, *)
@Generable
struct GeneratedTopicResponse {
    @Guide(description: "Exactly one entry for every tab in the list")
    var labels: [GeneratedTopicLabel]

    var contract: TopicResponse {
        TopicResponse(labels: labels.map { TopicResponse.Label(tabNumber: $0.tabNumber, topic: $0.topic) })
    }
}

@available(macOS 26.0, *)
@Generable
struct GeneratedInstructionResponse {
    @Guide(description: "Short name for the matching tabs, 1 to 3 words")
    var name: String
    @Guide(description: "Numbers of the tabs the request is about")
    var matchingTabNumbers: [Int]
    @Guide(description: "What the request asks to do with the matching tabs")
    var actionForMatching: GeneratedTabAction
    @Guide(description: "What the request asks to do with all other tabs. keep unless the request says otherwise")
    var actionForOthers: GeneratedTabAction

    var contract: InstructionResponse {
        InstructionResponse(name: name,
                            matchingTabNumbers: matchingTabNumbers,
                            actionForMatching: actionForMatching.contract,
                            actionForOthers: actionForOthers.contract)
    }
}
