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
    You find the few broad topics a person's open browser tabs are about. \
    Topics are general categories like Dogs, News, Shopping, Travel, Coding or Streaming, \
    never a single site, product or breed. Each topic should cover several tabs.
    """

    private static let assignInstructions = """
    You sort a person's open browser tabs into given topics. Judge each tab by its title and site.
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
            let response = Self.applyingKeepOnly(text, to: try await session.respond(to: prompt, generating: GeneratedInstructionResponse.self).content.contract)
            // The small model invents criteria, so only split when the request asks for it.
            if let criterion = response.groupBy, Self.asksToSplit(text) {
                return try await split(response, by: criterion, tabs: tabs)
            }
            // "the shopping group": a tab group named in the request is matched in code, not by the model.
            let namedGroups = Self.groupNames(mentionedIn: text, tabs: tabs)
            if !namedGroups.isEmpty, response.actionForMatching != .keep {
                return Self.proposal(for: namedGroups, action: response.actionForMatching, tabs: tabs)
            }
            return TabOrganizerProposalBuilder.proposal(from: response, tabs: tabs)
        }
    }

    private static let suggestionInstructions = """
    You suggest ways a person could tidy their open browser tabs. \
    Each suggestion is an action plus a broad category of tabs, like news, streaming, shopping, travel or work. \
    Never name a single site or brand. Use a different category for each suggestion.
    """

    /// Groups the matching tabs by `criterion` with the same two phases as group by topic.
    private func split(_ response: InstructionResponse, by criterion: String, tabs: [TabSnapshot]) async throws -> TabOrganizerProposal {
        let matching = TabOrganizerProposalBuilder.proposal(from: response, tabs: tabs).groups.first { $0.name != TabOrganizerProposalBuilder.everythingElseGroupName }
        let matchingTabs = tabs.filter { matching?.tabIDs.contains($0.id) == true }
        guard !matchingTabs.isEmpty else { return TabOrganizerProposalBuilder.proposal(from: response, tabs: tabs) }

        // Splitting regroups the matching tabs whatever groups they are in now.
        let ungroupedMatchingTabs = matchingTabs.map { tab in
            var tab = tab
            tab.groupName = nil
            return tab
        }
        let labels = try await topicLabels(for: ungroupedMatchingTabs, criterion: criterion)
        var groups = TabOrganizerProposalBuilder.proposal(from: labels, tabs: matchingTabs).groups
        for index in groups.indices {
            groups[index].action = response.actionForMatching
        }
        let others = tabs.map(\.id).filter { id in !matchingTabs.contains { $0.id == id } }
        if !others.isEmpty {
            groups.append(ProposedGroup(name: TabOrganizerProposalBuilder.everythingElseGroupName, tabIDs: others, action: response.actionForOthers))
        }
        return TabOrganizerProposal(groups: groups)
    }

    static func asksToSplit(_ text: String) -> Bool {
        let words = Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        return !words.isDisjoint(with: ["separate", "split", "by"])
    }

    /// "keep only X" and "close everything except X" mean: X stays, the rest closes. The small model tends to
    /// keep the rest, or to close X, so these phrasings are read in code.
    static func applyingKeepOnly(_ text: String, to response: InstructionResponse) -> InstructionResponse {
        let words = Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        let isKeepOnly = !words.isDisjoint(with: ["only", "just"]) && response.actionForMatching == .keep
        let isCloseExcept = !words.isDisjoint(with: ["except", "but"]) && !words.isDisjoint(with: ["close", "delete", "remove"])
        guard isKeepOnly || isCloseExcept else { return response }
        var response = response
        response.actionForMatching = .keep
        response.actionForOthers = .close
        return response
    }

    /// Existing tab group names that appear in the request, whole words, ignoring case.
    static func groupNames(mentionedIn text: String, tabs: [TabSnapshot]) -> [String] {
        let request = " " + text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ") + " "
        var names: [String] = []
        for name in tabs.compactMap(\.groupName) where !names.contains(name) {
            let normalized = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
            if request.contains(" \(normalized) ") {
                names.append(name)
            }
        }
        return names
    }

    static func proposal(for groupNames: [String], action: TabGroupAction, tabs: [TabSnapshot]) -> TabOrganizerProposal {
        var groups = groupNames.map { name in
            ProposedGroup(name: name, tabIDs: tabs.filter { $0.groupName == name }.map(\.id), action: action)
        }
        let others = tabs.filter { tab in !groupNames.contains { $0 == tab.groupName } }.map(\.id)
        if !others.isEmpty {
            groups.append(ProposedGroup(name: TabOrganizerProposalBuilder.everythingElseGroupName, tabIDs: others, action: .keep))
        }
        return TabOrganizerProposal(groups: groups)
    }

    static let topicBatchSize = 10
    static let otherTopic = "Other"

    /// Two phases, because the model is reliable on short outputs only: first it names a few broad topics
    /// for the whole window, then it assigns tabs to exactly those topics in batches of 10.
    /// Tabs that are already in a tab group keep it; only the other tabs are sorted, into those groups or new topics.
    /// To regroup everything, callers pass snapshots without group names.
    private func topicLabels(for tabs: [TabSnapshot], criterion: String? = nil) async throws -> TopicResponse {
        var labels = tabs.enumerated().compactMap { index, tab in
            tab.groupName.map { TopicResponse.Label(tabNumber: index + 1, topic: $0) }
        }
        let existingGroups = Self.unique(labels.map(\.topic))
        let numbers = tabs.indices.filter { tabs[$0].groupName == nil }.map { $0 + 1 }
        guard !numbers.isEmpty else { return TopicResponse(labels: labels) }

        let newTopics = try await broadTopics(for: numbers.map { tabs[$0 - 1] }, criterion: criterion, existingGroups: existingGroups)
        let topics = Self.unique(existingGroups + newTopics)
        guard !topics.isEmpty else { return TopicResponse(labels: labels) }

        for start in stride(from: 0, to: numbers.count, by: Self.topicBatchSize) {
            let batch = Array(numbers[start..<min(start + Self.topicBatchSize, numbers.count)])
            labels += try await assign(batch, in: tabs, to: topics)
        }
        let labelled = Set(labels.map(\.tabNumber))
        let skipped = numbers.filter { !labelled.contains($0) }
        if !skipped.isEmpty {
            labels += try await assign(skipped, in: tabs, to: topics)
        }
        // "Other" is a choice, not a topic: leaving those tabs unlabelled puts them in the builder's Other group.
        return TopicResponse(labels: labels.filter { $0.topic != Self.otherTopic })
    }

    /// Case-insensitively unique, in order of first use.
    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    private func broadTopics(for tabs: [TabSnapshot], criterion: String?, existingGroups: [String]) async throws -> [String] {
        let instructions = criterion.map { "You group a person's open browser tabs by \($0). Name each group after its \($0)." }
        let session = LanguageModelSession(instructions: instructions ?? Self.topicInstructions)
        var prompt = "Tabs:\n\(Self.tabList(for: tabs))"
        if !existingGroups.isEmpty {
            prompt = "The person already has these tab groups: \(existingGroups.joined(separator: ", ")). "
                + "Only add topics for tabs that fit none of them.\n\n" + prompt
        }
        let response = try await session.respond(to: prompt, generating: GeneratedTopicList.self).content
        var seen = Set<String>()
        return response.topics
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(Self.otherTopic) != .orderedSame && seen.insert($0.lowercased()).inserted }
    }

    /// The topic is constrained to the given list with a dynamic schema, so the model can't invent new ones.
    private func assign(_ numbers: [Int], in tabs: [TabSnapshot], to topics: [String]) async throws -> [TopicResponse.Label] {
        let topicSchema = DynamicGenerationSchema(name: "Topic", anyOf: topics + [Self.otherTopic])
        let labelSchema = DynamicGenerationSchema(name: "Label", properties: [
            DynamicGenerationSchema.Property(name: "tabNumber", schema: DynamicGenerationSchema(type: Int.self)),
            DynamicGenerationSchema.Property(name: "topic", schema: DynamicGenerationSchema(referenceTo: "Topic"))
        ])
        let rootSchema = DynamicGenerationSchema(name: "Labels", properties: [
            DynamicGenerationSchema.Property(name: "labels",
                                             description: "Exactly one entry for every tab in the list",
                                             schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(referenceTo: "Label")))
        ])
        let schema = try GenerationSchema(root: rootSchema, dependencies: [topicSchema, labelSchema])

        let prompt = """
        Topics: \(topics.joined(separator: ", "))
        Put every tab into the topic it is about. Use \(Self.otherTopic) only when no topic fits.

        Tabs:
        \(Self.tabList(for: numbers.map { tabs[$0 - 1] }, numbers: numbers))
        """
        let session = LanguageModelSession(instructions: Self.assignInstructions)
        let content = try await session.respond(to: prompt, schema: schema).content
        return try content.value([GeneratedContent].self, forProperty: "labels").compactMap { label in
            guard let number = try? label.value(Int.self, forProperty: "tabNumber"),
                  let topic = try? label.value(String.self, forProperty: "topic") else { return nil }
            return TopicResponse.Label(tabNumber: number, topic: topic)
        }
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
    case createTabGroup

    var contract: TabGroupAction {
        switch self {
        case .keep: return .keep
        case .close: return .close
        case .moveToNewWindow: return .moveToNewWindow
        case .bookmark: return .bookmark
        case .addToFavorites: return .addToFavorites
        case .createTabGroup: return .createTabGroup
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
struct GeneratedTopicList {
    @Guide(description: "2 to 7 broad topics, 1 or 2 words each, each covering several tabs", .count(2...7))
    var topics: [String]
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
    @Guide(description: "When the request asks to separate, split or group the matching tabs, what to group them by, like breed, country or price. Empty otherwise")
    var groupBy: String

    var contract: InstructionResponse {
        let criterion = groupBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return InstructionResponse(name: name,
                                   matchingTabNumbers: matchingTabNumbers,
                                   actionForMatching: actionForMatching.contract,
                                   actionForOthers: actionForOthers.contract,
                                   groupBy: criterion.isEmpty ? nil : criterion)
    }
}
