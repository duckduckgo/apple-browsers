//
//  DaxPetViewModel.swift
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
import Combine
import os.log

@MainActor
protocol DaxPetPromptSubmitting {
    /// `payload` carries attachments and is applied once Duck.ai is open, as the address bar does.
    func submit(prompt: String, payload: AIChatNativePrompt?)
    func openDuckAI()
    /// Brings the browser forward, where Duck.ai's answer is waiting.
    func showBrowser()

    /// Whether the browser has a web page open that Duck.ai could summarize.
    var canSummarizeCurrentPage: Bool { get }
    /// Sends `request` to Duck.ai beside the open page, with the page attached; `false` when there's no page.
    func askAboutCurrentPage(_ request: String) async -> Bool
    /// Reopens the most recent Duck.ai chat; `false` when there are none.
    func continueLastChat() async -> Bool

    /// Whether several tabs' pages can go to Duck.ai with one prompt.
    var canCompareTabs: Bool { get }
    /// Sends `prompt` to Duck.ai with the pages of `tabs`; `false` when none of them could be read.
    func compare(_ prompt: String, tabs: [DaxPetTab]) async -> Bool
    /// Sends `request` to Duck.ai with the page of `tab`; `false` when it couldn't be read.
    func ask(_ request: String, about tab: DaxPetTab) async -> Bool

    /// What the selected Duck.ai model accepts, to check items dropped on Dax against.
    func attachmentCapabilities() async -> DaxPetAttachmentCapabilities

    /// The text of the web page open in the browser, if there is one.
    func currentPageContent() async -> DaxPetPageContent?
    /// Brings the open page forward and lights up `text` on it; `false` when it isn't there.
    func showOnCurrentPage(_ text: String) async -> Bool
}

struct DaxPetPageContent: Equatable {
    let url: String
    let title: String
    let text: String
}

/// A dropped link the browser already knows: open in a tab, or visited before.
enum DaxPetDropOffer: Equatable {
    case openTab(DaxPetTab)
    case visited(DaxPetVisit)
}

/// What Dax found in the browser for a request, offered as chips, with Duck.ai as the way on.
struct DaxPetFindings: Equatable {

    enum Item: Equatable, Identifiable {
        case tab(DaxPetTab)
        case visit(DaxPetVisit)

        var id: String {
            switch self {
            case .tab(let tab): return tab.id
            case .visit(let visit): return visit.url.absoluteString
            }
        }

        var title: String {
            switch self {
            case .tab(let tab): return tab.title
            case .visit(let visit): return visit.title
            }
        }

        var url: URL {
            switch self {
            case .tab(let tab): return tab.url
            case .visit(let visit): return visit.url
            }
        }

        var favicon: NSImage? {
            switch self {
            case .tab(let tab): return tab.favicon
            case .visit(let visit): return visit.favicon
            }
        }

        /// Where it is: the site, and whether it's open now or when it was seen. Among tabs alone, being
        /// open goes without saying.
        func detail(relativeTo now: Date, amongPagesSeenBefore: Bool) -> String {
            let site = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url.absoluteString
            switch self {
            case .tab:
                return amongPagesSeenBefore ? site + " · " + UserText.daxPetFoundOpenInATab : site
            case .visit(let visit):
                let formatter = RelativeDateTimeFormatter()
                formatter.dateTimeStyle = .named
                return site + " · " + formatter.localizedString(for: visit.date, relativeTo: now)
            }
        }
    }

    enum Content: Equatable {
        case items([Item])
        /// Dax asks before he first searches the history.
        case askingToSearchHistory
    }

    let headline: String
    let content: Content
    /// How many there are in all, shown beside the headline.
    var total: Int?
}

@MainActor
final class DaxPetViewModel: ObservableObject {

    @Published private(set) var isComposing = false
    @Published private(set) var speech: String?
    @Published private(set) var isAsleep = false
    /// Changes each time hearts should pop out of Dax; `nil` when there are none.
    @Published private(set) var heartBurst: Int?
    /// Items dropped on Dax, going along with the prompt.
    @Published private(set) var attachments: [DaxPetAttachment] = []
    /// Requests the on-device model came up with for what was dropped, offered as chips.
    @Published private(set) var suggestions: [String] = []
    /// What Dax guesses the user wants done with the drop; the prompt field's hint, sent on a bare Return.
    @Published private(set) var dropAction: DaxPetDropAction?
    /// The on-device gist of the page open in the browser and follow-ups to it, offered when the pointer
    /// rests on Dax.
    @Published private(set) var glance: DaxPetPageGlance?
    /// Tabs or pages Dax found on the Mac for the request, before anything goes to Duck.ai.
    @Published private(set) var findings: DaxPetFindings?
    /// Tabs Dax chose to send along for a comparison, shown as chips in the prompt field.
    @Published private(set) var comparedTabs: [DaxPetTab] = []
    /// What Dax offers for a dropped link the browser already knows.
    @Published private(set) var dropOffer: DaxPetDropOffer?

    /// Dax won't sum up the same page again for this long.
    var glanceCooldown: TimeInterval = 600
    var now: () -> Date = Date.init
    private var lastGlance: (url: String, time: Date)?
    private var glanceWork: DispatchWorkItem?

    var promptPlaceholder: String {
        dropAction?.prompt ?? UserText.daxPetPromptPlaceholder
    }

    var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (dropAction != nil && !attachments.isEmpty)
    }
    @Published var prompt = "" {
        didSet { promptDidChange(from: oldValue) }
    }

    let character: DaxCharacterView

    /// How long Dax shows he's on it before Duck.ai takes over the screen.
    var submissionDelay: TimeInterval = 0.7
    /// How tall the bubble above Dax is now, as laid out, so only it takes clicks.
    var bubbleContentHeight: CGFloat?

    /// How long he waits for Duck.ai to start answering, and then to finish, before he stops thinking.
    var answerStartTimeout: TimeInterval = 15
    var answerFinishTimeout: TimeInterval = 120

    /// Waiting on Duck.ai to finish an answer.
    private(set) var isAwaitingAnswer = false
    /// An answer finished while the browser was in the background, and Dax is pointing it out.
    private(set) var hasUnseenAnswer = false
    /// Duck.ai asked for the user's OK in the chat, and Dax is pointing it out until it's answered.
    private(set) var isPointingAtPermission = false
    private var permissionCallID: String?

    var onHide: (() -> Void)?
    /// Asks the window to take keyboard focus.
    var onNeedsKeyboard: (() -> Void)?
    /// Where the end of the typed prompt sits, in screen coordinates, for Dax to watch it.
    var caretLocation: ((_ promptWidth: CGFloat) -> NSPoint?)?

    private let submitter: DaxPetPromptSubmitting
    private let intelligence: DaxPetIntelligence
    private let screenLooker: DaxPetScreenLooking?
    private let canSeeForegroundApp: () -> Bool
    private let browsing: DaxPetBrowsing?
    private let historyConsent: DaxPetHistoryConsent?
    /// The prompt Dax last looked up in the browser, so the next Return sends rather than looks again.
    private var lookedUpPrompt: String?
    /// The search to run once the user lets Dax look through the history.
    private var pendingHistorySearch: (() async -> Void)?
    private(set) var isLookingUp = false
    /// The prompt the screen was last checked for, so the next Return sends rather than checks again.
    private var screenCheckedPrompt: String?
    private(set) var isCheckingScreen = false
    /// Rewordings of Dax's lines from the on-device model, by the line they replace.
    private var lineVariations: [String: [String]] = [:]
    private var speechWork: DispatchWorkItem?
    private var answerTimeoutWork: DispatchWorkItem?
    private var attachmentCapabilities = DaxPetAttachmentCapabilities.unknown

    init(submitter: DaxPetPromptSubmitting,
         character: DaxCharacterView? = nil,
         intelligence: DaxPetIntelligence? = nil,
         screenLooker: DaxPetScreenLooking? = nil,
         canSeeForegroundApp: @escaping () -> Bool = { false },
         browsing: DaxPetBrowsing? = nil,
         historyConsent: DaxPetHistoryConsent? = nil) {
        self.submitter = submitter
        self.intelligence = intelligence ?? DaxPetNoIntelligence()
        self.screenLooker = screenLooker
        self.canSeeForegroundApp = canSeeForegroundApp
        self.browsing = browsing
        self.historyConsent = historyConsent
        self.character = character ?? DaxCharacterView()
        self.character.onSleepChange = { [weak self] isAsleep in
            self?.isAsleep = isAsleep
            if isAsleep { self?.say(nil) }
        }
        self.character.onLovedPetting = { [weak self] in self?.showHearts() }
    }

    func sayHello() {
        character.wave()
        say(UserText.daxPetHello, for: 3)
    }

    func characterClicked() {
        if isPointingAtPermission {
            character.hop()
            submitter.showBrowser()
        } else if hasUnseenAnswer {
            hasUnseenAnswer = false
            say(nil)
            character.hop()
            submitter.showBrowser()
        } else if isComposing {
            endComposing()
        } else {
            startComposing()
        }
    }

    func characterHovered() {
        character.wave()
    }

    func startComposing() {
        guard !isComposing else { return }
        hasUnseenAnswer = false
        clearGlance()
        isComposing = true
        character.mood = .listening
        character.wave()
        say(line(UserText.daxPetGreeting))
        onNeedsKeyboard?()
        updateLookTarget()
    }

    func endComposing() {
        guard isComposing else { return }
        isComposing = false
        prompt = ""
        attachments = []
        screenCheckedPrompt = nil
        lookedUpPrompt = nil
        findings = nil
        comparedTabs = []
        clearSuggestions()
        character.mood = isAwaitingAnswer ? .thinking : .idle
        character.lookTarget = nil
        say(nil)
    }

    /// Focus moved elsewhere: only an untouched prompt is dropped.
    func keyboardFocusLost() {
        if prompt.isEmpty { endComposing() }
    }

    func submit() {
        let typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = typed.isEmpty && !attachments.isEmpty ? dropAction?.prompt ?? "" : typed
        guard !prompt.isEmpty, !isCheckingScreen, !isLookingUp else {
            Logger.aiChat.notice("Dax: Return ignored (checking screen: \(self.isCheckingScreen, privacy: .public), looking up: \(self.isLookingUp, privacy: .public))")
            return
        }
        if shouldLookUp(prompt) {
            Logger.aiChat.notice("Dax: looking \(prompt, privacy: .private) up on the device first")
            Task { await lookUp(prompt) }
            return
        }
        Logger.aiChat.notice("""
            Dax: not looking up (on device: \(self.intelligence.isOnDevice, privacy: .public), \
            browser: \(self.browsing != nil, privacy: .public), attachments: \(self.attachments.count, privacy: .public), \
            tabs to compare: \(self.comparedTabs.count, privacy: .public), looked up already: \(self.lookedUpPrompt == prompt, privacy: .public))
            """)
        if shouldCheckScreen(for: prompt), let screenLooker, let app = screenLooker.foregroundApp {
            Logger.aiChat.notice("Dax: checking whether it's about \(app.name, privacy: .public)")
            Task { await checkScreen(for: prompt, in: app, with: screenLooker) }
            return
        }
        screenCheckedPrompt = nil
        lookedUpPrompt = nil
        findings = nil
        let (query, payload) = DaxPetAttachmentLoader.prompt(prompt, attachments: attachments, capabilities: attachmentCapabilities)
        let tabs = comparedTabs
        isComposing = false
        self.prompt = ""
        attachments = []
        comparedTabs = []
        clearSuggestions()
        character.lookTarget = nil
        character.mood = .thinking
        say(line(UserText.daxPetThinking))

        Logger.aiChat.notice("""
            Dax: sending to Duck.ai, with attachments: \(payload != nil, privacy: .public), \
            tabs to compare: \(tabs.count, privacy: .public)
            """)
        DispatchQueue.main.asyncAfter(deadline: .now() + submissionDelay) { [weak self] in
            guard let self else { return }
            if tabs.isEmpty {
                submitter.submit(prompt: query, payload: payload)
            } else {
                // Tabs that can't be read leave the question to Duck.ai on its own.
                Task { [submitter] in
                    if await !submitter.compare(query, tabs: tabs) {
                        submitter.submit(prompt: query, payload: nil)
                    }
                }
            }
            say(nil)
            // He keeps thinking until Duck.ai is done, or gives up if it never says it started.
            isAwaitingAnswer = true
            scheduleAnswerTimeout(after: answerStartTimeout)
        }
    }

    // MARK: - Lookups in the browser

    /// Typed requests only, with the on-device model to tell what they are, and only once each.
    private func shouldLookUp(_ prompt: String) -> Bool {
        browsing != nil && intelligence.isOnDevice && attachments.isEmpty && comparedTabs.isEmpty && lookedUpPrompt != prompt
    }

    /// Tabs and pages Dax can find on the Mac he finds at once; anything else, or nothing found, goes on to Duck.ai.
    private func lookUp(_ prompt: String) async {
        isLookingUp = true
        lookedUpPrompt = prompt
        character.mood = .thinking
        let lookup = await intelligence.lookup(prompt)
        isLookingUp = false
        guard isStillAsking(prompt) else { return }
        character.mood = .listening

        guard let lookup, let browsing else {
            Logger.aiChat.notice("Dax: nothing to look up in the browser, so it's for Duck.ai")
            return submit()
        }
        switch lookup.kind {
        case .listTabs:
            listTabs(in: browsing)
        case .compareTabs:
            guard submitter.canCompareTabs else { return submit() }
            await chooseTabsToCompare(for: prompt, lookup, in: browsing)
        case .openTab, .history:
            if let screenLooker, let app = await appTheRequestIsAbout(prompt) {
                await withHistoryConsent { [weak self] canSearchHistory in
                    await self?.findFromScreen(for: prompt, in: app, with: screenLooker, browsing, includingHistory: canSearchHistory)
                }
            } else if lookup.kind == .openTab {
                await findTab(for: prompt, lookup, in: browsing)
            } else {
                await withHistoryConsent { [weak self] canSearchHistory in
                    guard canSearchHistory else { self?.submit(); return }
                    await self?.findPage(for: prompt, lookup, in: browsing)
                }
            }
        }
    }

    /// Runs `search` with whether the history may be searched, asking the user the first time.
    private func withHistoryConsent(_ search: @escaping (Bool) async -> Void) async {
        Logger.aiChat.notice("Dax: history search allowed: \(String(describing: self.historyConsent?.canSearchHistory), privacy: .public)")
        switch historyConsent?.canSearchHistory {
        case true?:
            await search(true)
        case nil where historyConsent != nil:
            pendingHistorySearch = { await search(true) }
            say(nil)
            findings = DaxPetFindings(headline: UserText.daxPetHistoryAsk, content: .askingToSearchHistory)
        default:
            await search(false)
        }
    }

    /// The app in front, when the request is about what the user has open in it.
    private func appTheRequestIsAbout(_ prompt: String) async -> DaxPetForegroundApp? {
        guard canSeeForegroundApp(), let app = screenLooker?.foregroundApp else { return nil }
        return await intelligence.refersToScreen(prompt, appName: app.name) ? app : nil
    }

    /// Dax reads the app in front on the Mac and finds the tabs and pages about what's in it. Finding
    /// none, the request goes on to Duck.ai with a screenshot offered, as any question about the screen.
    private func findFromScreen(for prompt: String, in app: DaxPetForegroundApp, with screenLooker: DaxPetScreenLooking,
                                _ browsing: DaxPetBrowsing, includingHistory: Bool) async {
        character.mood = .thinking
        say(UserText.daxPetScreenLooking(at: app.name))
        var topic: DaxPetScreenTopic?
        if let text = await screenLooker.readText(of: app) {
            topic = await intelligence.screenTopic(text, appName: app.name)
        }
        guard isStillAsking(prompt) else { return }
        Logger.aiChat.notice("Dax: read \(app.name, privacy: .public): \(topic?.topic ?? "nothing", privacy: .private)")
        guard let topic else { return goOnToDuckAI() }

        let tabs = browsing.openTabs.filter { tab in topic.terms.contains { DaxPetBrowser.mentions(tab.title + " " + tab.url.absoluteString, $0) } }
        let openURLs = Set(tabs.map(\.url))
        let visits = includingHistory ? browsing.history(matching: topic.terms, limit: Self.maximumCandidates).filter { !openURLs.contains($0.url) } : []
        let candidates = Array((tabs.map(DaxPetFindings.Item.tab) + visits.map(DaxPetFindings.Item.visit)).prefix(Self.maximumCandidates))
        Logger.aiChat.notice("Dax: \(tabs.count, privacy: .public) tabs and \(visits.count, privacy: .public) history pages about the screen")
        guard !candidates.isEmpty else { return goOnToDuckAI() }

        let pages = candidates.map { item -> String in
            switch item {
            case .tab(let tab): return "\(tab.title) — \(tab.url.host ?? ""), open now"
            case .visit(let visit): return "\(visit.title) — \(visit.url.host ?? ""), \(Self.modelDateFormatter.localizedString(for: visit.date, relativeTo: now()))"
            }
        }
        let picks = await intelligence.pick("\(topic.topic): \(topic.terms.joined(separator: ", "))", from: pages, maximum: 3)
        guard isStillAsking(prompt) else { return }
        guard !picks.isEmpty else { return goOnToDuckAI() }
        character.mood = .listening
        show(picks.map { candidates[$0] }, headline: UserText.daxPetFoundFromScreen)
    }

    private func goOnToDuckAI() {
        character.mood = .listening
        say(nil)
        submit()
    }

    /// Every open tab, to pick from; no model needed.
    private func listTabs(in browsing: DaxPetBrowsing) {
        let tabs = browsing.openTabs
        Logger.aiChat.notice("Dax: listing \(tabs.count, privacy: .public) open tabs")
        guard !tabs.isEmpty else { return say(UserText.daxPetNoTabs, for: 4) }
        say(nil)
        findings = DaxPetFindings(headline: UserText.daxPetYourTabs, content: .items(tabs.map(DaxPetFindings.Item.tab)), total: tabs.count)
    }

    /// Tabs open at most this long go to the on-device model to choose from.
    static let maximumCandidates = 30

    private func findTab(for prompt: String, _ lookup: DaxPetLookup, in browsing: DaxPetBrowsing) async {
        let tabs = browsing.openTabs
        let matching = tabs.filter { tab in lookup.terms.contains { DaxPetBrowser.mentions(tab.title + " " + tab.url.absoluteString, $0) } }
        let candidates = Array((matching.isEmpty ? tabs : matching).prefix(Self.maximumCandidates))
        character.mood = .thinking
        let picks = await intelligence.pick(prompt, from: candidates.map { "\($0.title) — \($0.url.host ?? "")" }, maximum: 3)
        guard isStillAsking(prompt) else { return }
        character.mood = .listening
        let found = picks.map { candidates[$0] }
        Logger.aiChat.notice("""
            Dax: found \(found.count, privacy: .public) of \(candidates.count, privacy: .public) tabs \
            (\(matching.count, privacy: .public) had the words)
            """)
        switch found.count {
        case 0:
            submit()
        case 1:
            openFinding(.tab(found[0]))
        default:
            show(found.map(DaxPetFindings.Item.tab), headline: UserText.daxPetFoundTabs)
        }
    }

    /// A comparison takes this many tabs at most.
    static let maximumComparedTabs = 5

    /// The tabs to compare join the prompt as chips, and the next Return sends them along.
    private func chooseTabsToCompare(for prompt: String, _ lookup: DaxPetLookup, in browsing: DaxPetBrowsing) async {
        let tabs = browsing.openTabs
        let matching = tabs.filter { tab in lookup.terms.contains { DaxPetBrowser.mentions(tab.title + " " + tab.url.absoluteString, $0) } }
        let candidates = Array((matching.count >= 2 ? matching : tabs).prefix(Self.maximumCandidates))
        character.mood = .thinking
        let picks = await intelligence.pick(prompt, from: candidates.map { "\($0.title) — \($0.url.host ?? "")" },
                                            maximum: Self.maximumComparedTabs)
        guard isStillAsking(prompt) else { return }
        character.mood = .listening
        Logger.aiChat.notice("Dax: \(picks.count, privacy: .public) of \(candidates.count, privacy: .public) tabs to compare")
        guard picks.count >= 2 else { return submit() }
        comparedTabs = picks.map { candidates[$0] }
        updateLookTarget()
        say(UserText.daxPetCompareReady)
    }

    func leaveOut(_ tab: DaxPetTab) {
        comparedTabs.removeAll { $0.id == tab.id }
        updateLookTarget()
    }

    private func findPage(for prompt: String, _ lookup: DaxPetLookup, in browsing: DaxPetBrowsing) async {
        let visits = browsing.history(matching: lookup.terms, limit: Self.maximumCandidates * 2)
        // The model's sense of time is loose, so a date the user gave only puts the pages from then first.
        let since = now().addingTimeInterval(-Double(lookup.daysBack + 1) * 24 * 60 * 60)
        let ordered = lookup.daysBack > 0 ? visits.filter { $0.date >= since } + visits.filter { $0.date < since } : visits
        let candidates = Array(ordered.prefix(Self.maximumCandidates))
        Logger.aiChat.notice("Dax: \(visits.count, privacy: .public) history pages have the words")
        guard !candidates.isEmpty else { return submit() }
        character.mood = .thinking
        let pages = candidates.map { "\($0.title) — \($0.url.host ?? ""), \(Self.modelDateFormatter.localizedString(for: $0.date, relativeTo: now()))" }
        let picks = await intelligence.pick(prompt, from: pages, maximum: 3)
        guard isStillAsking(prompt) else { return }
        character.mood = .listening
        guard !picks.isEmpty else { return submit() }
        show(picks.map { .visit(candidates[$0]) }, headline: UserText.daxPetFoundHistory)
    }

    private func show(_ items: [DaxPetFindings.Item], headline: String) {
        say(nil)
        findings = DaxPetFindings(headline: headline, content: .items(items))
    }

    /// Brings the tab forward or opens the page, and Dax is done.
    func openFinding(_ item: DaxPetFindings.Item) {
        guard let browsing else { return }
        switch item {
        case .tab(let tab): browsing.switchTo(tab)
        case .visit(let visit): browsing.open(visit.url)
        }
        endComposing()
        character.hop()
        say(UserText.daxPetFoundHere(Self.shortened(item.title) ?? item.url.host ?? ""), for: 4)
    }

    /// The user would rather Duck.ai answered; turning down the history search also means not asking again.
    func askDuckAIInstead() {
        if findings?.content == .askingToSearchHistory {
            historyConsent?.canSearchHistory = false
        }
        findings = nil
        pendingHistorySearch = nil
        submit()
    }

    func allowHistorySearch() {
        historyConsent?.canSearchHistory = true
        findings = nil
        guard let search = pendingHistorySearch else { return }
        pendingHistorySearch = nil
        Task { await search() }
    }

    private func isStillAsking(_ prompt: String) -> Bool {
        let isStillAsking = isComposing && lookedUpPrompt == prompt && self.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == prompt
        if !isStillAsking {
            Logger.aiChat.notice("Dax: the request was closed or changed while he looked, so he dropped it")
        }
        return isStillAsking
    }

    /// For the on-device model, which reads English best.
    private static let modelDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - The app in front

    /// Only typed questions, with the user's say-so and the on-device model to judge them, and only once each.
    private func shouldCheckScreen(for prompt: String) -> Bool {
        canSeeForegroundApp() && intelligence.isOnDevice && attachments.isEmpty && comparedTabs.isEmpty && screenCheckedPrompt != prompt
    }

    /// When the question is about the app in front, a screenshot of it joins the prompt as a chip, and Dax
    /// waits for another Return before anything is sent; otherwise the question goes as it is.
    private func checkScreen(for prompt: String, in app: DaxPetForegroundApp, with screenLooker: DaxPetScreenLooking) async {
        isCheckingScreen = true
        screenCheckedPrompt = prompt
        character.mood = .thinking
        let refersToScreen = await intelligence.refersToScreen(prompt, appName: app.name)
        let capabilities = refersToScreen ? await submitter.attachmentCapabilities() : attachmentCapabilities
        Logger.aiChat.notice("""
            Dax: about \(app.name, privacy: .public): \(refersToScreen, privacy: .public), \
            model takes images: \(capabilities.validator(pendingImageCount: 0, pendingFiles: []).canAttachImages, privacy: .public)
            """)
        isCheckingScreen = false
        guard isComposing, screenCheckedPrompt == prompt else { return }
        character.mood = .listening

        let canSendImages = capabilities.validator(pendingImageCount: 0, pendingFiles: []).canAttachImages
        guard refersToScreen, canSendImages else {
            submit()
            return
        }
        attachmentCapabilities = capabilities
        say(UserText.daxPetScreenLooking(at: app.name))
        guard let screenshot = await screenLooker.captureWindow(of: app), isComposing else {
            say(UserText.daxPetScreenNoPermission(app.name), for: 6)
            return
        }
        attachments.append(.image(AIChatImageAttachment(image: screenshot,
                                                        fileName: UserText.daxPetScreenFileName(app.name) + ".jpg",
                                                        skipResize: true)))
        updateLookTarget()
        say(UserText.daxPetScreenReady(app.name))
    }

    // MARK: - Duck.ai answers

    /// Duck.ai started working on an answer, whoever asked.
    func answerStarted() {
        isAwaitingAnswer = true
        hasUnseenAnswer = false
        if !isComposing {
            character.mood = .thinking
        }
        scheduleAnswerTimeout(after: answerFinishTimeout)
    }

    /// Duck.ai is done. If the browser is out of sight, Dax lets you know the answer is in.
    func answerFinished(succeeded: Bool, isBrowserActive: Bool) {
        guard isAwaitingAnswer else { return }
        stopAwaitingAnswer()
        stopPointingAtPermission()
        guard !isComposing else { return }
        if succeeded {
            character.celebrate()
            if !isBrowserActive {
                hasUnseenAnswer = true
                say(UserText.daxPetAnswerReady, for: 8)
            }
        } else {
            say(UserText.daxPetAnswerFailed, for: 4)
        }
    }

    private func stopAwaitingAnswer() {
        answerTimeoutWork?.cancel()
        answerTimeoutWork = nil
        isAwaitingAnswer = false
        if character.mood == .thinking {
            character.mood = .idle
        }
    }

    private func scheduleAnswerTimeout(after delay: TimeInterval) {
        answerTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopAwaitingAnswer() }
        answerTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Duck.ai in the browser

    /// Dax follows along as Duck.ai uses the browser: he says what it's doing, looks the part, and points
    /// out when it needs the user's OK. Typing and sleeping aren't interrupted.
    func browserToolActivity(_ activity: AIChatBrowserToolActivity) {
        switch activity.phase {
        case .started:
            guard !isComposing, !isAsleep, let narration = narration(for: activity) else { return }
            act(for: activity.toolName)
            if !isPointingAtPermission { say(narration, for: 4) }
        case .awaitingPermission:
            guard !isComposing else { return }
            permissionCallID = activity.callID
            isPointingAtPermission = true
            character.marvel()
            say(Self.permissionLine(for: activity))
        case .finished:
            guard activity.callID == permissionCallID else { return }
            stopPointingAtPermission()
        }
    }

    private func stopPointingAtPermission() {
        guard isPointingAtPermission else { return }
        permissionCallID = nil
        isPointingAtPermission = false
        say(nil)
    }

    private func act(for toolName: String) {
        switch toolName {
        case "readTabContent": character.look(.read, for: 3)
        case "listOpenTabs", "searchHistory", "findInPage": character.look(.search, for: 3)
        case "highlightInPage": character.celebrate()
        case "switchToTab": character.hop()
        default: break
        }
    }

    /// Titles and search words are cut to fit the bubble.
    static let maximumSubjectLength = 28

    static func shortened(_ subject: String?) -> String? {
        guard let subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty else { return nil }
        return subject.count > maximumSubjectLength ? String(subject.prefix(maximumSubjectLength - 1)) + "…" : subject
    }

    /// What Dax says Duck.ai is doing; `nil` for tools he doesn't know.
    private func narration(for activity: AIChatBrowserToolActivity) -> String? {
        let subject = Self.shortened(activity.subject)
        switch activity.toolName {
        case "listOpenTabs": return line(UserText.daxPetToolTabs)
        case "searchHistory": return subject.map(UserText.daxPetToolHistory(for:)) ?? line(UserText.daxPetToolHistoryAny)
        case "readTabContent": return subject.map(UserText.daxPetToolReading) ?? line(UserText.daxPetToolReadingPage)
        case "findInPage": return subject.map(UserText.daxPetToolFinding) ?? line(UserText.daxPetToolFindingAny)
        case "highlightInPage": return line(UserText.daxPetToolHighlighting)
        case "switchToTab": return subject.map(UserText.daxPetToolSwitching) ?? line(UserText.daxPetToolSwitchingAny)
        default: return nil
        }
    }

    /// Names what Duck.ai is asking to do, where the chat only says it wants a browser tool.
    static func permissionLine(for activity: AIChatBrowserToolActivity) -> String {
        let subject = shortened(activity.subject)
        switch activity.toolName {
        case "listOpenTabs": return UserText.daxPetPermissionTabs
        case "searchHistory": return UserText.daxPetPermissionHistory
        case "readTabContent": return subject.map(UserText.daxPetPermissionReading) ?? UserText.daxPetPermissionReadingPage
        case "findInPage": return subject.map(UserText.daxPetPermissionFinding) ?? UserText.daxPetPermissionAny
        default: return UserText.daxPetPermissionAny
        }
    }

    func openDuckAI() {
        endComposing()
        character.hop()
        submitter.openDuckAI()
    }

    func hide() {
        endComposing()
        onHide?()
    }

    // MARK: - Drops

    /// Takes what was dropped on him, as far as the selected model allows, and asks what to do with it.
    func receive(_ items: [DaxPetDroppedItem]) async {
        guard !items.isEmpty else { return }
        let capabilities = await submitter.attachmentCapabilities()
        attachmentCapabilities = capabilities
        let (accepted, rejection) = DaxPetAttachmentLoader.load(items, adding: attachments, capabilities: capabilities)
        hasUnseenAnswer = false
        if !accepted.isEmpty {
            startComposing()
            attachments += accepted
            character.hop()
            updateLookTarget()
        }
        if let rejection {
            say(rejection, for: 5)
        } else if let offer = offer(for: attachments) {
            dropOffer = offer
            say(Self.speech(for: offer, now: now()))
        } else if !accepted.isEmpty {
            say(line(UserText.daxPetDropQuestion))
        }
        if !accepted.isEmpty {
            await suggestRequests()
        }
    }

    func removeAttachments() {
        attachments = []
        clearSuggestions()
        updateLookTarget()
    }

    /// A single dropped link that's open in a tab, or that was visited, as long as Dax may look at the history.
    private func offer(for attachments: [DaxPetAttachment]) -> DaxPetDropOffer? {
        guard let browsing, attachments.count == 1, case .link(_, let url) = attachments[0] else { return nil }
        let page = DaxPetBrowser.samePageKey(url)
        if let tab = browsing.openTabs.first(where: { DaxPetBrowser.samePageKey($0.url) == page }) {
            return .openTab(tab)
        }
        guard historyConsent?.canSearchHistory == true, let visit = browsing.lastVisit(to: url) else { return nil }
        return .visited(visit)
    }

    static func speech(for offer: DaxPetDropOffer, now: Date) -> String {
        switch offer {
        case .openTab:
            return UserText.daxPetDropOpenTab
        case .visited(let visit):
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            return UserText.daxPetDropVisited(formatter.localizedString(for: visit.date, relativeTo: now))
        }
    }

    func goToDroppedTab() {
        guard case .openTab(let tab) = dropOffer, let browsing else { return }
        browsing.switchTo(tab)
        endComposing()
        character.hop()
        say(UserText.daxPetFoundHere(Self.shortened(tab.title) ?? tab.url.host ?? ""), for: 4)
    }

    /// An open tab is recapped with its page as it is now; a page visited before goes to Duck.ai as the link.
    func recapDrop() async {
        switch dropOffer {
        case .openTab(let tab):
            endComposing()
            if await submitter.ask(UserText.daxPetRecapPrompt, about: tab) {
                character.hop()
            } else {
                say(UserText.daxPetAnswerFailed, for: 4)
            }
        case .visited:
            useSuggestion(UserText.daxPetRecapPrompt)
        case nil:
            break
        }
    }

    /// Sends a suggested request as the prompt, with what was dropped.
    func useSuggestion(_ suggestion: String) {
        prompt = suggestion
        submit()
    }

    /// Asks the on-device model what to do with the drop; the question bubble gives way to its answers,
    /// unless the user has moved on by then.
    private func suggestRequests() async {
        let attachments = self.attachments
        dropAction = DaxPetDropAction.guess(for: attachments, kind: nil)
        async let kind = intelligence.kind(of: attachments)
        async let suggestions = intelligence.suggestions(for: attachments)
        let (guessedKind, suggested) = await (kind, suggestions)

        guard isComposing, self.attachments.map(\.id) == attachments.map(\.id) else { return }
        dropAction = DaxPetDropAction.guess(for: attachments, kind: guessedKind)
        guard prompt.isEmpty, !suggested.isEmpty else { return }
        // With an offer up, its line stays and the suggestions join its chips.
        self.suggestions = Array(suggested.prefix(dropOffer == nil ? 3 : 2))
        if dropOffer == nil { say(nil) }
    }

    private func clearSuggestions() {
        suggestions = []
        dropAction = nil
        dropOffer = nil
    }

    // MARK: - Page glance

    /// With the pointer resting on him, Dax reads the open page on the device and sums it up in a bubble.
    func glanceAtPage() async {
        guard intelligence.isOnDevice, !isComposing, !isAsleep, !isAwaitingAnswer, speech == nil, glance == nil, findings == nil,
              suggestions.isEmpty, let page = await submitter.currentPageContent(), !page.text.isEmpty else { return }
        if let last = lastGlance, last.url == page.url, now().timeIntervalSince(last.time) < glanceCooldown { return }
        lastGlance = (page.url, now())

        character.mood = .thinking
        let pageGlance = await intelligence.pageGlance(title: page.title, content: page.text)
        guard character.mood == .thinking, !isAwaitingAnswer else { return }
        character.mood = .idle
        guard let pageGlance, !isComposing, speech == nil else { return }
        // Only words really on the page can be lit up there.
        let quote = pageGlance.quote.flatMap { DaxPetPageQuote.fragment(matching: $0, in: page.text) }
        glance = DaxPetPageGlance(summary: pageGlance.summary, followUps: Array(pageGlance.followUps.prefix(3)), quote: quote)
        let work = DispatchWorkItem { [weak self] in self?.glance = nil }
        glanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    /// From the gist to Duck.ai: one of the follow-ups, or a full summary when there are none.
    func askAboutGlance(_ followUp: String? = nil) async {
        clearGlance()
        await ask(followUp ?? UserText.daxPetSummarizePrompt)
    }

    /// Lights up on the page where the gist comes from.
    func showWhereOnPage() async {
        guard let quote = glance?.quote else { return }
        clearGlance()
        if await submitter.showOnCurrentPage(quote) {
            character.hop()
            say(UserText.daxPetShowWhereFound, for: 3)
        } else {
            say(UserText.daxPetShowWhereMissed, for: 4)
        }
    }

    private func clearGlance() {
        glanceWork?.cancel()
        glanceWork = nil
        glance = nil
    }

    // MARK: - Debug

    enum DebugAction: Hashable {
        case pose(DaxCharacterView.DebugPose)
        case answerReady
        case answerFailed

        static var allCases: [DebugAction] {
            DaxCharacterView.DebugPose.allCases.map(DebugAction.pose) + [.answerReady, .answerFailed]
        }

        var title: String {
            switch self {
            case .pose(let pose): return pose.rawValue
            case .answerReady: return "Answer Ready (Bubble)"
            case .answerFailed: return "Answer Failed (Bubble)"
            }
        }
    }

    func debugPlay(_ action: DebugAction) {
        switch action {
        case .pose(let pose):
            endComposing()
            character.debugPlay(pose)
        case .answerReady, .answerFailed:
            answerStarted()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.answerFinished(succeeded: action == .answerReady, isBrowserActive: false)
            }
        }
    }

    // MARK: - Quick actions

    var canSummarizeCurrentPage: Bool { submitter.canSummarizeCurrentPage }

    func summarizePage() async {
        await ask(UserText.daxPetSummarizePrompt)
    }

    private func ask(_ request: String) async {
        endComposing()
        hasUnseenAnswer = false
        if await submitter.askAboutCurrentPage(request) {
            say(nil)
            character.hop()
        } else {
            say(UserText.daxPetSummarizeNoPage, for: 4)
        }
    }

    func continueLastChat() async {
        endComposing()
        hasUnseenAnswer = false
        if await submitter.continueLastChat() {
            say(nil)
            character.hop()
        } else {
            say(UserText.daxPetContinueNoChat, for: 4)
        }
    }

    /// A prompt this long makes Dax's eyes go wide.
    static let longPromptLength = 200

    private func promptDidChange(from oldValue: String) {
        guard isComposing, prompt != oldValue else { return }
        if !prompt.isEmpty, speech != nil { say(nil) }
        if !prompt.isEmpty {
            suggestions = []
            dropOffer = nil
        }
        findings = nil
        pendingHistorySearch = nil
        updateLookTarget()

        character.noticeTyping()
        if prompt.count > oldValue.count, let last = prompt.last, last.isWhitespace || last.isPunctuation,
           oldValue.last.map({ !$0.isWhitespace && !$0.isPunctuation }) == true {
            character.nod()
        }
        if prompt.count >= Self.longPromptLength, oldValue.count < Self.longPromptLength {
            character.marvel()
        }
    }

    private func updateLookTarget() {
        let width = (prompt as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        character.lookTarget = caretLocation?(width + DaxPetView.Metrics.attachmentsWidth(count: attachments.count)
                                              + DaxPetView.Metrics.tabChipsWidth(count: comparedTabs.count))
    }

    private func showHearts() {
        let burst = (heartBurst ?? 0) + 1
        heartBurst = burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.heartBurst == burst { self?.heartBurst = nil }
        }
    }

    // MARK: - Lines

    /// The chatter Dax says often enough to want some variety. Lines that tell the user what to do are
    /// left as written, so their meaning can't drift.
    static let variedLines: [String] = [UserText.daxPetGreeting, UserText.daxPetThinking, UserText.daxPetDropQuestion,
                                        UserText.daxPetToolTabs, UserText.daxPetToolHistoryAny, UserText.daxPetToolReadingPage,
                                        UserText.daxPetToolFindingAny, UserText.daxPetToolHighlighting, UserText.daxPetToolSwitchingAny]

    /// A bubble holds this much; longer rewordings are thrown away.
    static let maximumLineLength = 60

    /// Has the on-device model reword Dax's lines in the background, so he doesn't repeat himself.
    func prepareLineVariations() async {
        for line in Self.variedLines where lineVariations[line] == nil {
            let variations = await intelligence.variations(of: line)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”"))) }
                .filter { !$0.isEmpty && $0.count <= Self.maximumLineLength && $0 != line }
                // A question stays a question.
                .filter { !line.hasSuffix("?") || $0.hasSuffix("?") }
                // Dax doesn't name himself.
                .filter { !$0.localizedCaseInsensitiveContains("Dax") }
            lineVariations[line] = variations
        }
    }

    /// `text`, or now and then one of its rewordings.
    private func line(_ text: String) -> String {
        guard let variations = lineVariations[text], !variations.isEmpty else { return text }
        return ([text] + variations).randomElement() ?? text
    }

    private func say(_ text: String?, for duration: TimeInterval? = nil) {
        speechWork?.cancel()
        speech = text
        guard text != nil, let duration else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.speech = nil
            self?.hasUnseenAnswer = false
        }
        speechWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
