//
//  ContextualSuggestionsMatcher.swift
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

import AIChat
import Foundation
import os.log

struct SuggestionCatalog: Decodable {
    struct Entry: Decodable {
        let label: String
        let icon: String?
        let prompt: String
        let condition: String?
    }

    struct JSONLDMapping: Decodable {
        let type: String
        let ids: [String]
    }

    let maxSuggestedPrompts: Int
    let defaults: [String]
    let catalog: [String: Entry]
    let byJsonLdType: [JSONLDMapping]
    let byOgType: [String: [String]]
    let byDomain: [String: [String]]

    /// The bundled catalog, decoded once. `nil` if the resource is missing or malformed (a ship-time
    /// error, guarded defensively so the sheet still shows the defaults at runtime).
    static let bundled: SuggestionCatalog? = {
        guard let url = Bundle.main.url(forResource: "PageSuggestionsCatalog", withExtension: "json") else {
            Logger.aiChat.error("[Suggestions] PageSuggestionsCatalog.json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SuggestionCatalog.self, from: data)
        } catch {
            Logger.aiChat.error("[Suggestions] Failed to decode PageSuggestionsCatalog.json: \(error)")
            return nil
        }
    }()
}

// MARK: - Matcher

struct ContextualSuggestionsMatcher {

    private init() {}

    private static let summarizePageID = "summarize-page"

    static func resolve(_ input: ResolvePageSuggestionsInput, catalog: SuggestionCatalog) -> [ContextualSuggestedPrompt] {
        let candidateIds = collectCandidateIds(input, catalog: catalog)
        var seen = Set<String>()
        var resolved: [ContextualSuggestedPrompt] = []

        for id in candidateIds {
            if resolved.count >= catalog.maxSuggestedPrompts { break }
            if seen.contains(id) { continue }
            seen.insert(id)

            guard let entry = catalog.catalog[id], conditionPasses(entry.condition, input: input) else { continue }

            let copy = localizedCopy(for: id, entry: entry)
            resolved.append(ContextualSuggestedPrompt(
                id: id,
                label: copy.label,
                prompt: applyTemplate(copy.prompt, input: input),
                icon: entry.icon
            ))
        }

        return resolved
    }

    // MARK: Candidate collection

    private static func collectCandidateIds(_ input: ResolvePageSuggestionsInput, catalog: SuggestionCatalog) -> [String] {
        var contextual: [String]?

        if let signals = input.pageTypeSignals {
            contextual = matchByJsonLdType(signals.jsonLdType, catalog.byJsonLdType)
            if contextual == nil, let ogType = signals.ogType, !ogType.isEmpty {
                contextual = catalog.byOgType[ogType.trimmingCharacters(in: .whitespaces).lowercased()]
            }
        }
        if contextual == nil, let hostname = hostname(from: input.url) {
            contextual = matchByDomain(hostname, catalog.byDomain)
        }

        // "Summarize this page" is a generic fallback: when page-tailored suggestions matched, drop it
        // so it is only offered when nothing page-specific did. It is unconditional, so it is always
        // present otherwise — this is the never-empty floor for the start surface.
        let defaults = contextual != nil ? catalog.defaults.filter { $0 != summarizePageID } : catalog.defaults
        return (contextual ?? []) + defaults
    }

    private static func matchByJsonLdType(_ types: [String], _ mappings: [SuggestionCatalog.JSONLDMapping]) -> [String]? {
        guard !types.isEmpty else { return nil }
        let present = Set(types.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        for mapping in mappings where present.contains(mapping.type.lowercased()) {
            return mapping.ids
        }
        return nil
    }

    private static func matchByDomain(_ hostname: String, _ table: [String: [String]]) -> [String]? {
        // Domains in the catalog do not overlap, so dictionary iteration order is irrelevant here.
        for (domain, ids) in table where domainMatches(hostname, domain) {
            return ids
        }
        return nil
    }

    // MARK: Conditions & templating

    private static func conditionPasses(_ condition: String?, input: ResolvePageSuggestionsInput) -> Bool {
        guard let condition else { return true }
        switch condition {
        case "differentLanguage":
            let pageLang = pageLanguageSubtag(input.pageTypeSignals?.lang ?? "")
            let uiLang = uiLanguageSubtag(input.uiLocale)
            return !pageLang.isEmpty && !uiLang.isEmpty && pageLang != uiLang
        default:
            return false
        }
    }

    private static func applyTemplate(_ prompt: String, input: ResolvePageSuggestionsInput) -> String {
        guard prompt.contains("{language}") else { return prompt }
        return prompt.replacingOccurrences(of: "{language}", with: languageDisplayName(input.uiLocale))
    }

    // MARK: Localization

    private static func localizedCopy(for id: String, entry: SuggestionCatalog.Entry) -> (label: String, prompt: String) {
        localizedCopyByID[id] ?? (entry.label, entry.prompt)
    }

    /// Maps each catalog id to its native `UserText` copy. The `UserText` extension holds the strings
    /// (idiomatic for the codebase); this map is the id → strings glue the matcher needs.
    private static let localizedCopyByID: [String: (label: String, prompt: String)] = [
        "summarize-page": (UserText.aiChatSuggestionSummarizePageLabel, UserText.aiChatSuggestionSummarizePagePrompt),
        "translate-page": (UserText.aiChatSuggestionTranslatePageLabel, UserText.aiChatSuggestionTranslatePagePrompt),
        "key-takeaways": (UserText.aiChatSuggestionKeyTakeawaysLabel, UserText.aiChatSuggestionKeyTakeawaysPrompt),
        "explain-simply": (UserText.aiChatSuggestionExplainSimplyLabel, UserText.aiChatSuggestionExplainSimplyPrompt),
        "counterarguments": (UserText.aiChatSuggestionCounterargumentsLabel, UserText.aiChatSuggestionCounterargumentsPrompt),
        "related-articles": (UserText.aiChatSuggestionRelatedArticlesLabel, UserText.aiChatSuggestionRelatedArticlesPrompt),
        "shopping-list": (UserText.aiChatSuggestionShoppingListLabel, UserText.aiChatSuggestionShoppingListPrompt),
        "recipe-nutrition": (UserText.aiChatSuggestionRecipeNutritionLabel, UserText.aiChatSuggestionRecipeNutritionPrompt),
        "scale-recipe": (UserText.aiChatSuggestionScaleRecipeLabel, UserText.aiChatSuggestionScaleRecipePrompt),
        "product-pros-cons": (UserText.aiChatSuggestionProductProsConsLabel, UserText.aiChatSuggestionProductProsConsPrompt),
        "find-alternatives": (UserText.aiChatSuggestionFindAlternativesLabel, UserText.aiChatSuggestionFindAlternativesPrompt),
        "summarize-video": (UserText.aiChatSuggestionSummarizeVideoLabel, UserText.aiChatSuggestionSummarizeVideoPrompt),
        "video-key-points": (UserText.aiChatSuggestionVideoKeyPointsLabel, UserText.aiChatSuggestionVideoKeyPointsPrompt),
        "tailor-resume": (UserText.aiChatSuggestionTailorResumeLabel, UserText.aiChatSuggestionTailorResumePrompt),
        "interview-prep": (UserText.aiChatSuggestionInterviewPrepLabel, UserText.aiChatSuggestionInterviewPrepPrompt),
        "cover-letter": (UserText.aiChatSuggestionCoverLetterLabel, UserText.aiChatSuggestionCoverLetterPrompt),
        "event-details": (UserText.aiChatSuggestionEventDetailsLabel, UserText.aiChatSuggestionEventDetailsPrompt),
        "worth-watching": (UserText.aiChatSuggestionWorthWatchingLabel, UserText.aiChatSuggestionWorthWatchingPrompt),
        "similar-titles": (UserText.aiChatSuggestionSimilarTitlesLabel, UserText.aiChatSuggestionSimilarTitlesPrompt),
        "cast-crew": (UserText.aiChatSuggestionCastCrewLabel, UserText.aiChatSuggestionCastCrewPrompt),
        "summarize-book": (UserText.aiChatSuggestionSummarizeBookLabel, UserText.aiChatSuggestionSummarizeBookPrompt),
        "similar-books": (UserText.aiChatSuggestionSimilarBooksLabel, UserText.aiChatSuggestionSimilarBooksPrompt),
        "explain-paper": (UserText.aiChatSuggestionExplainPaperLabel, UserText.aiChatSuggestionExplainPaperPrompt),
        "paper-contributions": (UserText.aiChatSuggestionPaperContributionsLabel, UserText.aiChatSuggestionPaperContributionsPrompt),
        "menu-highlights": (UserText.aiChatSuggestionMenuHighlightsLabel, UserText.aiChatSuggestionMenuHighlightsPrompt),
        "place-hours": (UserText.aiChatSuggestionPlaceHoursLabel, UserText.aiChatSuggestionPlaceHoursPrompt),
        "place-reviews": (UserText.aiChatSuggestionPlaceReviewsLabel, UserText.aiChatSuggestionPlaceReviewsPrompt),
        "summarize-thread": (UserText.aiChatSuggestionSummarizeThreadLabel, UserText.aiChatSuggestionSummarizeThreadPrompt),
        "explain-repo": (UserText.aiChatSuggestionExplainRepoLabel, UserText.aiChatSuggestionExplainRepoPrompt),
        "explain-answer": (UserText.aiChatSuggestionExplainAnswerLabel, UserText.aiChatSuggestionExplainAnswerPrompt),
        "howto-steps": (UserText.aiChatSuggestionHowtoStepsLabel, UserText.aiChatSuggestionHowtoStepsPrompt),
        "howto-materials": (UserText.aiChatSuggestionHowtoMaterialsLabel, UserText.aiChatSuggestionHowtoMaterialsPrompt),
        "course-learn": (UserText.aiChatSuggestionCourseLearnLabel, UserText.aiChatSuggestionCourseLearnPrompt),
        "course-worth": (UserText.aiChatSuggestionCourseWorthLabel, UserText.aiChatSuggestionCourseWorthPrompt),
        "faq-answer": (UserText.aiChatSuggestionFaqAnswerLabel, UserText.aiChatSuggestionFaqAnswerPrompt),
        "faq-summary": (UserText.aiChatSuggestionFaqSummaryLabel, UserText.aiChatSuggestionFaqSummaryPrompt),
        "review-verdict": (UserText.aiChatSuggestionReviewVerdictLabel, UserText.aiChatSuggestionReviewVerdictPrompt),
        "review-summary": (UserText.aiChatSuggestionReviewSummaryLabel, UserText.aiChatSuggestionReviewSummaryPrompt),
        "who-is-this": (UserText.aiChatSuggestionWhoIsThisLabel, UserText.aiChatSuggestionWhoIsThisPrompt),
        "person-background": (UserText.aiChatSuggestionPersonBackgroundLabel, UserText.aiChatSuggestionPersonBackgroundPrompt)
    ]

    // MARK: Locale

    /// Page language arrives as a web BCP-47 tag (`<html lang>`), so mirror the frontend `primarySubtag`.
    private static func pageLanguageSubtag(_ tag: String) -> String {
        let normalized = tag.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized.split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    /// The UI locale is an Apple identifier (`en_US@rg=plzzzz`), not BCP-47, so use the native accessor
    /// rather than a `split("-")` that would mis-parse the underscore/extension format.
    private static func uiLanguageSubtag(_ uiLocale: String) -> String {
        Locale(identifier: uiLocale).languageCode?.lowercased() ?? ""
    }

    /// Language name in the UI locale, mirroring `Intl.DisplayNames`; falls back to the subtag.
    private static func languageDisplayName(_ uiLocale: String) -> String {
        let locale = Locale(identifier: uiLocale)
        let subtag = uiLanguageSubtag(uiLocale)
        if let name = locale.localizedString(forLanguageCode: subtag), name.lowercased() != subtag {
            return name
        }
        return subtag
    }

    // MARK: URL helpers

    private static func hostname(from url: String?) -> String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.lowercased()
    }

    private static func domainMatches(_ hostname: String, _ domain: String) -> Bool {
        let normalized = domain.trimmingCharacters(in: .whitespaces).lowercased()
        return hostname == normalized || hostname.hasSuffix(".\(normalized)")
    }
}

// MARK: - Provider

struct DefaultContextualSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    private let catalog: SuggestionCatalog?

    init(catalog: SuggestionCatalog? = SuggestionCatalog.bundled) {
        self.catalog = catalog
    }

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> [ContextualSuggestedPrompt] {
        guard let catalog else { return Self.decodeFailureFallback }
        return ContextualSuggestionsMatcher.resolve(input, catalog: catalog)
    }

    /// Last-resort floor if the bundled catalog cannot be decoded: a single unconditional
    /// "Summarize this page" so the start surface is never empty.
    private static var decodeFailureFallback: [ContextualSuggestedPrompt] {
        [ContextualSuggestedPrompt(
            id: "summarize-page",
            label: UserText.aiChatSuggestionSummarizePageLabel,
            prompt: UserText.aiChatSuggestionSummarizePagePrompt,
            icon: "summary"
        )]
    }
}
