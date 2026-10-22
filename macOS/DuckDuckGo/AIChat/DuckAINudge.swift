//
//  DuckAINudge.swift
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
import AppKit
import EventKit
import Foundation
import FoundationModels
import NaturalLanguage
import os.log
import SwiftUI

struct DuckAINudge: Equatable {

    enum Kind: String, CaseIterable {
        case translate, summarize, product, recipe, event, legal, code, compare, travel, video, paper, thread
    }

    struct Prompt: Equatable {
        let label: String
        let text: String
        var autoSubmit = true
        var includesOtherTabs = false
    }

    let kind: Kind
    let url: URL
    let title: String
    let subtitle: String
    /// Set for a single-action callout; nil shows `prompts` as chips.
    let actionTitle: String?
    let prompts: [Prompt]
    let isConfident: Bool
    let pageContext: AIChatPageContextData
    var compareTabIDs: [String] = []
}

// MARK: - Restraint

final class DuckAINudgeRestraint {

    static let shared = DuckAINudgeRestraint()

    private let defaults = UserDefaults.standard
    private let dismissalsKey = "duckai.nudge.dismissals"
    private static let quietAfterDismissals = 2
    private var autoOpenedURLs = Set<String>()

    func isQuiet(_ kind: DuckAINudge.Kind) -> Bool {
        dismissals[kind.rawValue, default: 0] >= Self.quietAfterDismissals
    }

    func recordDismissal(_ kind: DuckAINudge.Kind) {
        var all = dismissals
        all[kind.rawValue, default: 0] += 1
        defaults.set(all, forKey: dismissalsKey)
    }

    func recordUse(_ kind: DuckAINudge.Kind) {
        var all = dismissals
        all[kind.rawValue] = 0
        defaults.set(all, forKey: dismissalsKey)
    }

    func resetAll() {
        defaults.removeObject(forKey: dismissalsKey)
        autoOpenedURLs.removeAll()
    }

    /// Returns true once per page.
    func claimAutoOpen(for url: URL) -> Bool {
        autoOpenedURLs.insert(url.absoluteString).inserted
    }

    private var dismissals: [String: Int] {
        defaults.dictionary(forKey: dismissalsKey) as? [String: Int] ?? [:]
    }

    static func isBlocked(_ url: URL, signals: AIChatPageTypeSignals?) -> Bool {
        guard let host = url.host?.lowercased(), ["http", "https"].contains(url.scheme?.lowercased()) else { return true }
        let blockedHosts = ["duckduckgo.com", "duck.ai", "duck.co"]
        if blockedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        if host.contains("bank") || host.hasPrefix("login.") || host.hasPrefix("accounts.") || host.hasPrefix("signin.") { return true }
        let path = url.path.lowercased()
        let blockedPathWords = ["login", "signin", "sign-in", "signup", "checkout", "/cart", "/basket", "payment", "/account", "password"]
        if blockedPathWords.contains(where: { path.contains($0) }) { return true }
        if signals?.sensitive?.any == true { return true }
        return false
    }
}

// MARK: - Engine

@MainActor
final class DuckAINudgeEngine {

    static let shared = DuckAINudgeEngine()

    struct OpenTab {
        let id: String
        let url: URL
    }

    func nudge(for context: AIChatPageContextData, url: URL, otherTabs: [OpenTab]) async -> DuckAINudge? {
        let signals = context.pageTypeSignals
        guard !DuckAINudgeRestraint.isBlocked(url, signals: signals) else {
            Logger.aiChat.notice("[Nudge] blocked \(url.absoluteString, privacy: .public)")
            return nil
        }

        var candidate = classify(context: context, url: url, otherTabs: otherTabs)
        if candidate == nil {
            candidate = await classifyWithModel(context: context)
        }
        guard let candidate, !DuckAINudgeRestraint.shared.isQuiet(candidate.kind) else { return nil }

        var nudge = template(for: candidate, context: context, url: url)
        if candidate.wantsGeneratedCopy, let subtitle = await generatedSubtitle(for: candidate.kind, context: context) {
            nudge = DuckAINudge(kind: nudge.kind, url: nudge.url, title: nudge.title, subtitle: subtitle,
                                actionTitle: nudge.actionTitle, prompts: nudge.prompts, isConfident: nudge.isConfident,
                                pageContext: nudge.pageContext, compareTabIDs: nudge.compareTabIDs)
        }
        Logger.aiChat.notice("[Nudge] \(nudge.kind.rawValue, privacy: .public) confident=\(nudge.isConfident) \(url.absoluteString, privacy: .public)")
        return nudge
    }

    // MARK: Heuristics

    struct Candidate {
        let kind: DuckAINudge.Kind
        let isConfident: Bool
        var languageName: String?
        var readMinutes: Int?
        var compareTabIDs: [String] = []
        var generated: GeneratedCopy?

        var wantsGeneratedCopy: Bool {
            generated == nil && ![.translate, .summarize, .compare, .code].contains(kind)
        }
    }

    struct GeneratedCopy {
        let title: String
        let subtitle: String
        let prompts: [String]
    }

    private func classify(context: AIChatPageContextData, url: URL, otherTabs: [OpenTab]) -> Candidate? {
        let signals = context.pageTypeSignals
        let types = Set((signals?.jsonLdType ?? []).map { $0.lowercased() })
        let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
        let path = url.path.lowercased()
        let title = context.title.lowercased()

        let isProduct = signals?.jsonLd?.product != nil || types.contains("product") || signals?.ogType?.lowercased().contains("product") == true
        let similarTabs = otherTabs.filter { tab in
            tab.url.host?.lowercased().replacingOccurrences(of: "www.", with: "") == host && tab.url.path.count > 1 && tab.url.path != url.path
        }
        if isProduct, similarTabs.count >= 2 {
            var candidate = Candidate(kind: .compare, isConfident: true)
            candidate.compareTabIDs = Array(similarTabs.prefix(3).map(\.id))
            return candidate
        }

        if signals?.youtube != nil || (host.hasSuffix("youtube.com") && path == "/watch") {
            return Candidate(kind: .video, isConfident: true)
        }

        if signals?.jsonLd?.reservation != nil || types.contains(where: { $0.hasSuffix("reservation") }) {
            return Candidate(kind: .travel, isConfident: true)
        }
        if signals?.jsonLd?.recipe != nil || types.contains("recipe") {
            return Candidate(kind: .recipe, isConfident: true)
        }
        if signals?.jsonLd?.event != nil || types.contains(where: { $0 == "event" || $0.hasSuffix("event") }) {
            return Candidate(kind: .event, isConfident: true)
        }
        if signals?.jsonLd?.product != nil || types.contains("product") || signals?.ogType?.lowercased().contains("product") == true {
            return Candidate(kind: .product, isConfident: true)
        }

        if let languageName = foreignLanguageName(context: context) {
            var candidate = Candidate(kind: .translate, isConfident: true)
            candidate.languageName = languageName
            return candidate
        }

        if signals?.legalHint != nil {
            return Candidate(kind: .legal, isConfident: true)
        }
        let legalWords = ["terms of service", "terms of use", "terms and conditions", "privacy policy", "privacy notice"]
        if legalWords.contains(where: { title.contains($0) }) || ["/terms", "/tos", "/privacy", "/legal"].contains(where: { path.hasPrefix($0) }) {
            return Candidate(kind: .legal, isConfident: false)
        }

        if host == "github.com" && path.contains("/blob/") || (signals?.codeRatio ?? 0) > 0.25 || (signals?.codeBlockCount ?? 0) >= 4 {
            return Candidate(kind: .code, isConfident: false)
        }
        if ["arxiv.org", "biorxiv.org", "pubmed.ncbi.nlm.nih.gov"].contains(where: { host.hasSuffix($0) }) || context.mimeType == AIChatPageContextData.pdfMIMEType {
            return Candidate(kind: .paper, isConfident: false)
        }
        if host.hasSuffix("reddit.com") && path.contains("/comments/") || host == "news.ycombinator.com" && path == "/item" {
            return Candidate(kind: .thread, isConfident: false)
        }

        let minutes = readMinutes(context: context)
        if minutes >= 6 {
            var candidate = Candidate(kind: .summarize, isConfident: false)
            candidate.readMinutes = minutes
            return candidate
        }
        return nil
    }

    private func readMinutes(context: AIChatPageContextData) -> Int {
        if let minutes = context.pageTypeSignals?.readMinutes { return minutes }
        let words = context.pageTypeSignals?.wordCount ?? context.fullContentLength / 6
        return words / 230
    }

    private func foreignLanguageName(context: AIChatPageContextData) -> String? {
        let sample = String(context.content.prefix(3000))
        guard sample.count >= 400 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence > 0.8 else { return nil }
        let userLanguage = Locale.preferredLanguages.first.map { Locale(identifier: $0).languageCode ?? $0 } ?? "en"
        guard language.rawValue.prefix(2) != userLanguage.prefix(2) else { return nil }
        return Locale.current.localizedString(forLanguageCode: language.rawValue)
    }

    // MARK: Copy

    private func template(for candidate: Candidate, context: AIChatPageContextData, url: URL) -> DuckAINudge {
        func chips(_ labels: [String]) -> [DuckAINudge.Prompt] {
            labels.map { DuckAINudge.Prompt(label: $0, text: $0) }
        }
        let title: String
        let subtitle: String
        var actionTitle: String?
        var prompts: [DuckAINudge.Prompt]

        switch candidate.kind {
        case .translate:
            let language = candidate.languageName ?? "another language"
            let target = Locale.current.localizedString(forLanguageCode: Locale.preferredLanguages.first ?? "en") ?? "English"
            title = "Translate this page?"
            subtitle = "Duck.ai can translate it from \(language)."
            actionTitle = "Translate"
            prompts = [.init(label: "Translate", text: "Translate this page into \(target).")]
        case .summarize:
            let minutes = candidate.readMinutes ?? readMinutes(context: context)
            title = "Short on time?"
            subtitle = "This is a \(minutes) min read."
            actionTitle = "Summarize it"
            prompts = [.init(label: "Summarize it", text: "Summarize this article.")]
        case .compare:
            let count = candidate.compareTabIDs.count + 1
            title = "Comparing options?"
            subtitle = "You have \(count) similar tabs open."
            actionTitle = "Compare these \(count) tabs"
            prompts = [.init(label: "Compare these \(count) tabs", text: "Compare these \(count) tabs.")]
        case .event:
            title = "Going to this event?"
            subtitle = "Duck.ai can pull out the date, time and place."
            actionTitle = "Get the event details"
            prompts = [.init(label: "Get the event details", text: "Get the event details.")]
        case .product:
            title = "Thinking of buying this?"
            subtitle = "Duck.ai can help you decide."
            prompts = chips(["Pros and cons", "What do reviewers complain about?"])
            prompts.insert(.init(label: "Compare with my other open tabs", text: "Compare this with my other open tabs.", includesOtherTabs: true), at: 1)
        case .recipe:
            title = "Cooking this?"
            subtitle = "Duck.ai can adapt the recipe for you."
            prompts = chips(["Scale to 2 servings", "Make it vegan", "Make a shopping list"])
        case .legal:
            title = "What are you agreeing to?"
            subtitle = "Duck.ai can explain this in plain words."
            prompts = chips(["What am I agreeing to?", "What data do they collect and share?", "How do I opt out?"])
        case .code:
            title = "Reading code?"
            let fileName = url.lastPathComponent
            subtitle = fileName.contains(".") ? "Duck.ai can walk you through \(fileName)." : "Duck.ai can walk you through it."
            prompts = chips(["Explain this code", "Show me an example", "What are the gotchas?"])
        case .travel:
            title = "Getting ready for your trip?"
            subtitle = "Duck.ai can plan around your booking."
            prompts = chips(["Plan my days", "What should I pack?", "Get the booking details"])
        case .video:
            title = "Short on time?"
            subtitle = "Duck.ai can tell you what this video covers."
            prompts = chips(["Key points", "Is it worth watching?"])
            prompts.append(.init(label: "Jump to the part about…", text: "Jump to the part about ", autoSubmit: false))
        case .paper:
            title = "Dense reading?"
            subtitle = "Duck.ai can explain it simply."
            actionTitle = "Explain it like I'm new to this"
            prompts = [.init(label: "Explain it like I'm new to this", text: "Explain it like I'm new to this.")]
        case .thread:
            title = "Long discussion?"
            subtitle = "Duck.ai can sum up what people think."
            actionTitle = "What's the consensus?"
            prompts = [.init(label: "What's the consensus?", text: "What's the consensus in this thread?")]
        }

        if let generated = candidate.generated {
            return DuckAINudge(kind: candidate.kind, url: url, title: generated.title, subtitle: generated.subtitle,
                               actionTitle: nil, prompts: chips(generated.prompts), isConfident: candidate.isConfident,
                               pageContext: context, compareTabIDs: candidate.compareTabIDs)
        }
        return DuckAINudge(kind: candidate.kind, url: url, title: title, subtitle: subtitle, actionTitle: actionTitle,
                           prompts: prompts, isConfident: candidate.isConfident, pageContext: context,
                           compareTabIDs: candidate.compareTabIDs)
    }

    // MARK: On-device model

    private var isModelAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
    }

    private func excerpt(_ context: AIChatPageContextData) -> String {
        "Title: \(context.title)\nURL: \(context.url)\n\n\(context.content.prefix(2500))"
    }

    private func classifyWithModel(context: AIChatPageContextData) async -> Candidate? {
        guard #available(macOS 26, *), isModelAvailable, context.content.count >= 800 else { return nil }
        let session = LanguageModelSession(instructions: """
            You look at a web page and decide whether an AI assistant could clearly help the reader with it. \
            Pick the single best category, or "none" if the page is a home page, search results, a list of links, \
            a login or shopping-cart page, or anything where help would be unwanted. Be conservative.
            """)
        let result = await withTimeout(seconds: 6) {
            try? await session.respond(to: self.excerpt(context), generating: DuckAINudgeClassification.self).content
        }
        guard let result = result ?? nil, let kind = DuckAINudge.Kind(rawValue: result.category) else { return nil }
        Logger.aiChat.notice("[Nudge] model classified \(result.category, privacy: .public)")
        var candidate = Candidate(kind: kind, isConfident: false)
        if [.recipe, .event, .travel, .product, .legal, .code, .video].contains(kind) == false {
            candidate.generated = GeneratedCopy(title: result.title, subtitle: result.subtitle, prompts: Array(result.prompts.prefix(3)))
        }
        return candidate
    }

    private func generatedSubtitle(for kind: DuckAINudge.Kind, context: AIChatPageContextData) async -> String? {
        guard #available(macOS 26, *), isModelAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You write the one-line subtitle of a small browser popup offering AI help with the current page. \
            Write at most 9 words, plain and friendly, specific to this page (name the dish, product, event, \
            destination, video or library). No quotes, no emoji, no exclamation marks.
            """)
        let task: String
        switch kind {
        case .recipe: task = "adapting this recipe"
        case .event: task = "getting this event's details"
        case .product: task = "deciding whether to buy this product"
        case .legal: task = "understanding these terms"
        case .code: task = "understanding this code"
        case .travel: task = "planning this trip"
        case .video: task = "deciding whether to watch this video"
        default: task = "understanding this page"
        }
        let subtitle = await withTimeout(seconds: 5) {
            try? await session.respond(to: "Task: \(task)\n\n\(self.excerpt(context))", generating: DuckAINudgeSubtitle.self).content.subtitle
        }
        guard let subtitle = subtitle ?? nil else { return nil }
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
        guard trimmed.count > 8, trimmed.count <= 70, Self.isGrounded(trimmed, in: context) else {
            Logger.aiChat.notice("[Nudge] dropped generated subtitle: \(trimmed, privacy: .public)")
            return nil
        }
        return trimmed
    }

    /// The on-device model sometimes writes a subtitle about a different page; keep it only if it
    /// shares a meaningful word with this page's title or opening text.
    static func isGrounded(_ text: String, in context: AIChatPageContextData) -> Bool {
        func words(_ string: String) -> Set<String> {
            Set(string.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 })
        }
        let generic: Set<String> = ["this", "that", "with", "your", "help", "page", "duck"]
        let source = words(context.title + " " + context.content.prefix(600))
        return !words(text).subtracting(generic).isDisjoint(with: source)
    }

    private func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

@available(macOS 26, *)
@Generable
struct DuckAINudgeClassification {
    @Guide(description: "The page category", .anyOf(["recipe", "event", "travel", "product", "legal", "code", "video", "paper", "thread", "none"]))
    var category: String

    @Guide(description: "A short question offering help with this page, at most 6 words, ending with a question mark")
    var title: String

    @Guide(description: "One plain sentence, at most 9 words, saying what the assistant can do with this page")
    var subtitle: String

    @Guide(description: "Short requests the reader could send to the assistant about this page, at most 6 words each", .count(3))
    var prompts: [String]
}

@available(macOS 26, *)
@Generable
struct DuckAINudgeSubtitle {
    @Guide(description: "The subtitle, at most 9 words")
    var subtitle: String
}

// MARK: - Callout

struct DuckAINudgeCalloutView: View {

    let nudge: DuckAINudge
    let onPrompt: (DuckAINudge.Prompt) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: NSImage(resource: .aiChat))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(nudge.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(nudge.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityIdentifier("DuckAINudge.dismiss")
            }

            if let actionTitle = nudge.actionTitle, let prompt = nudge.prompts.first {
                Button(action: { onPrompt(prompt) }) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("DuckAINudge.action")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(nudge.prompts, id: \.label) { prompt in
                        Button(action: { onPrompt(prompt) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(prompt.label)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .accessibilityIdentifier("DuckAINudge.chip")
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}

final class DuckAINudgePopover: NSPopover {

    let nudge: DuckAINudge

    init(nudge: DuckAINudge, onPrompt: @escaping (DuckAINudge.Prompt) -> Void, onDismiss: @escaping () -> Void) {
        self.nudge = nudge
        super.init()
        behavior = .semitransient
        animates = true
        let view = DuckAINudgeCalloutView(nudge: nudge, onPrompt: onPrompt, onDismiss: onDismiss)
        let controller = NSHostingController(rootView: view)
        if #available(macOS 13, *) {
            controller.sizingOptions = .preferredContentSize
        }
        contentViewController = controller
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Page actions (Calendar / Reminders)

struct DuckAIPageActionResponse: Encodable {
    let ok: Bool
    let message: String?
}

@MainActor
enum DuckAIPageActionPerformer {

    private static let eventStore = EKEventStore()

    static func perform(params: Any) async -> DuckAIPageActionResponse {
        guard let dict = params as? [String: Any], let action = dict["action"] else {
            return .init(ok: false, message: "Missing action")
        }
        let actions: [[String: Any]] = (action as? [[String: Any]]) ?? [(action as? [String: Any])].compactMap { $0 }
        guard !actions.isEmpty else { return .init(ok: false, message: "Missing action") }
        let sourceURL = (dict["sourceURL"] as? String).flatMap(URL.init(string:))

        var messages: [String] = []
        for action in actions {
            do {
                switch action["type"] as? String {
                case "calendar.addEvent":
                    messages.append(try await addEvent(action, sourceURL: sourceURL))
                case "reminders.addList":
                    messages.append(try await addReminders(action))
                default:
                    return .init(ok: false, message: "Unsupported action")
                }
            } catch {
                Logger.aiChat.error("[Nudge] action failed: \(error.localizedDescription, privacy: .public)")
                return .init(ok: false, message: error.localizedDescription)
            }
        }
        return .init(ok: true, message: messages.joined(separator: " "))
    }

    enum ActionError: LocalizedError {
        case accessDenied(String)
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied(let app): return "DuckDuckGo doesn't have access to \(app)."
            case .invalid(let reason): return reason
            }
        }
    }

    private static func addEvent(_ action: [String: Any], sourceURL: URL?) async throws -> String {
        guard let title = action["title"] as? String, let startString = action["start"] as? String,
              let (start, isAllDay) = parseDate(startString) else {
            throw ActionError.invalid("The event is missing a title or start time.")
        }
        guard #available(macOS 14, *), try await eventStore.requestFullAccessToEvents() else { throw ActionError.accessDenied("Calendar") }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.isAllDay = isAllDay
        if let endString = action["end"] as? String, let (end, _) = parseDate(endString), end > start {
            event.endDate = end
        } else {
            event.endDate = isAllDay ? start : start.addingTimeInterval(2 * 60 * 60)
        }
        event.location = action["location"] as? String
        event.notes = action["notes"] as? String
        event.url = (action["url"] as? String).flatMap(URL.init(string:)) ?? sourceURL
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return "Added “\(title)” to Calendar."
    }

    private static func addReminders(_ action: [String: Any]) async throws -> String {
        guard let title = action["title"] as? String, let items = action["items"] as? [String], !items.isEmpty else {
            throw ActionError.invalid("The list is empty.")
        }
        guard #available(macOS 14, *), try await eventStore.requestFullAccessToReminders() else { throw ActionError.accessDenied("Reminders") }

        var list = eventStore.calendars(for: .reminder).first { $0.title == title }
        if list == nil, let source = eventStore.defaultCalendarForNewReminders()?.source {
            let newList = EKCalendar(for: .reminder, eventStore: eventStore)
            newList.title = title
            newList.source = source
            if (try? eventStore.saveCalendar(newList, commit: true)) != nil {
                list = newList
            }
        }
        guard let list = list ?? eventStore.defaultCalendarForNewReminders() else {
            throw ActionError.invalid("No Reminders list available.")
        }
        for item in items {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = item
            reminder.calendar = list
            try eventStore.save(reminder, commit: false)
        }
        try eventStore.commit()
        return "Added \(items.count) items to “\(list.title)” in Reminders."
    }

    private static func parseDate(_ string: String) -> (Date, isAllDay: Bool)? {
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            iso.formatOptions = options
            if let date = iso.date(from: string) { return (date, false) }
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: string) { return (date, false) }
        }
        local.dateFormat = "yyyy-MM-dd"
        if let date = local.date(from: string) { return (date, true) }
        return nil
    }
}
