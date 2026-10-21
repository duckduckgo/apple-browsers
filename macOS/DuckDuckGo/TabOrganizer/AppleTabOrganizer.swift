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
    You sort a person's open browser tabs into a few broad topics. \
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
            return TabOrganizerProposalBuilder.proposal(from: try await topicLabels(for: tabs), tabs: tabs)
        case .instruction(let text):
            let session = LanguageModelSession(instructions: Self.instructionInstructions)
            let prompt = "Tabs:\n\(tabList)\n\nRequest: \(text)"
            let response = try await session.respond(to: prompt, generating: GeneratedInstructionResponse.self).content
            return TabOrganizerProposalBuilder.proposal(from: response.contract, tabs: tabs)
        }
    }

    private static let suggestionInstructions = """
    You suggest ways a person could tidy their open browser tabs. \
    Each suggestion is an action plus a broad category of tabs, like news, streaming, shopping, travel or work. \
    Never name a single site or brand. Use a different category for each suggestion.
    """

    static let topicBatchSize = 10

    /// The model is reliable on short lists only, so tabs go in batches of 10. Each batch sees the topics
    /// found so far and reuses them or adds new ones; one last pass catches tabs any batch skipped.
    private func topicLabels(for tabs: [TabSnapshot]) async throws -> TopicResponse {
        var labels: [TopicResponse.Label] = []
        let numbers = Array(1...tabs.count)
        for start in stride(from: 0, to: numbers.count, by: Self.topicBatchSize) {
            let batch = Array(numbers[start..<min(start + Self.topicBatchSize, numbers.count)])
            labels += try await labelTopics(for: batch, in: tabs, existingTopics: Self.topics(in: labels))
        }
        let labelled = Set(labels.map(\.tabNumber))
        let skipped = numbers.filter { !labelled.contains($0) }
        if !skipped.isEmpty {
            labels += try await labelTopics(for: skipped, in: tabs, existingTopics: Self.topics(in: labels))
        }
        return TopicResponse(labels: labels)
    }

    private func labelTopics(for numbers: [Int], in tabs: [TabSnapshot], existingTopics: [String]) async throws -> [TopicResponse.Label] {
        var prompt = ""
        if !existingTopics.isEmpty {
            prompt += "Existing topics: \(existingTopics.joined(separator: ", "))\n"
            prompt += "Reuse an existing topic when a tab fits it. Only add a new topic when none fits.\n\n"
        }
        prompt += "Tabs:\n\(Self.tabList(for: numbers.map { tabs[$0 - 1] }, numbers: numbers))"
        let session = LanguageModelSession(instructions: Self.topicInstructions)
        return try await session.respond(to: prompt, generating: GeneratedTopicResponse.self).content.contract.labels
    }

    /// Topics in order of first use, case-insensitively unique.
    private static func topics(in labels: [TopicResponse.Label]) -> [String] {
        var seen = Set<String>()
        return labels.map(\.topic).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Commands tailored to the open tabs, shown as one-click suggestions.
    func suggestions(for tabs: [TabSnapshot]) async throws -> [String] {
        guard !tabs.isEmpty, case .available = SystemLanguageModel.default.availability else { return [] }
        let session = LanguageModelSession(instructions: Self.suggestionInstructions)
        let response = try await session.respond(to: "Tabs:\n\(Self.tabList(for: tabs))", generating: GeneratedSuggestions.self).content
        var seen = Set<String>()
        return response.suggestions.compactMap { suggestion in
            let category = suggestion.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !category.isEmpty, seen.insert(category).inserted else { return nil }
            return suggestion.verb.command(for: category)
        }
    }

    /// One line per tab: "3. Title — host/path [pageType]: excerpt". Excerpts shrink until the list fits.
    /// `numbers` are the tabs' positions in the full list; 1, 2, 3… when omitted.
    static func tabList(for tabs: [TabSnapshot], numbers: [Int]? = nil) -> String {
        let numbers = numbers ?? Array(1...max(tabs.count, 1))
        func lines(excerptLimit: Int) -> String {
            zip(numbers, tabs).map { number, tab in
                var line = "\(number). \(tab.title) — \(tab.host)\(tab.path)"
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
    case bookmark
    case addToFavorites

    var contract: TabGroupAction {
        switch self {
        case .keep: return .keep
        case .close: return .close
        case .moveToNewWindow: return .moveToNewWindow
        case .bookmark: return .bookmark
        case .addToFavorites: return .addToFavorites
        }
    }
}

@available(macOS 26.0, *)
@Generable
enum GeneratedSuggestionVerb {
    case close
    case moveToNewWindow
    case keepOnly
    case find
    case bookmark

    func command(for category: String) -> String {
        switch self {
        case .close: return "Close \(category) tabs"
        case .moveToNewWindow: return "Move \(category) tabs to a new window"
        case .keepOnly: return "Keep only \(category) tabs"
        case .find: return "Find \(category) tabs"
        case .bookmark: return "Bookmark \(category) tabs"
        }
    }
}

@available(macOS 26.0, *)
@Generable
struct GeneratedSuggestion {
    var verb: GeneratedSuggestionVerb
    @Guide(description: "Broad category of several tabs, 1 or 2 lowercase words, like news, streaming, shopping, travel. Never a site or brand name")
    var category: String
}

@available(macOS 26.0, *)
@Generable
struct GeneratedSuggestions {
    @Guide(description: "Suggestions about different categories, using a mix of actions", .count(5))
    var suggestions: [GeneratedSuggestion]
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
