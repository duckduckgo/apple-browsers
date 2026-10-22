//
//  DaxPetViewModelTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
private final class RecordingDaxPetPromptSubmitter: DaxPetPromptSubmitting {
    var submittedPrompts: [String] = []
    var submittedPayloads: [AIChatNativePrompt?] = []
    var capabilities = DaxPetAttachmentCapabilities.unknown
    var openDuckAICount = 0
    var showBrowserCount = 0
    var onSubmit: (() -> Void)?

    func submit(prompt: String, payload: AIChatNativePrompt?) {
        submittedPrompts.append(prompt)
        submittedPayloads.append(payload)
        onSubmit?()
    }

    func openDuckAI() {
        openDuckAICount += 1
    }

    func showBrowser() {
        showBrowserCount += 1
    }

    var canSummarizeCurrentPage = true
    var summarizeResult = true
    var pageRequests: [String] = []
    var summarizeCount: Int { pageRequests.count }
    func askAboutCurrentPage(_ request: String) async -> Bool {
        pageRequests.append(request)
        return summarizeResult
    }

    func attachmentCapabilities() async -> DaxPetAttachmentCapabilities {
        capabilities
    }

    var page: DaxPetPageContent?
    func currentPageContent() async -> DaxPetPageContent? {
        page
    }

    var continueResult = true
    var continueCount = 0
    func continueLastChat() async -> Bool {
        continueCount += 1
        return continueResult
    }
}

@MainActor
private final class StubDaxPetIntelligence: DaxPetIntelligence {
    var suggestions: [String] = []
    var onSuggest: (() -> Void)?
    var variations: [String: [String]] = [:]
    var kind: DaxPetDropKind?
    var isOnDevice = true
    var pageGlance: DaxPetPageGlance?
    var pageSummaryCount = 0

    var refersToScreen = false
    var screenChecks: [String] = []
    func refersToScreen(_ prompt: String, appName: String) async -> Bool {
        screenChecks.append(prompt)
        return refersToScreen
    }

    func pageGlance(title: String, content: String) async -> DaxPetPageGlance? {
        pageSummaryCount += 1
        return pageGlance
    }

    func kind(of attachments: [DaxPetAttachment]) async -> DaxPetDropKind? {
        kind
    }

    func variations(of line: String) async -> [String] {
        variations[line] ?? []
    }

    func suggestions(for attachments: [DaxPetAttachment]) async -> [String] {
        onSuggest?()
        return suggestions
    }

    var lookup: DaxPetLookup?
    var lookups: [String] = []
    func lookup(_ prompt: String) async -> DaxPetLookup? {
        lookups.append(prompt)
        return lookup
    }

    var picks: [Int] = []
    var pickedFrom: [[String]] = []
    func pick(_ prompt: String, from pages: [String], maximum: Int) async -> [Int] {
        pickedFrom.append(pages)
        return picks
    }
}

@MainActor
private final class StubDaxPetBrowser: DaxPetBrowsing {
    var openTabs: [DaxPetTab] = []
    var visits: [DaxPetVisit] = []
    var switchedTo: [DaxPetTab] = []
    var opened: [URL] = []
    var searches: [[String]] = []

    func switchTo(_ tab: DaxPetTab) {
        switchedTo.append(tab)
    }

    func history(matching terms: [String], limit: Int) -> [DaxPetVisit] {
        searches.append(terms)
        return Array(visits.prefix(limit))
    }

    func open(_ url: URL) {
        opened.append(url)
    }
}

@MainActor
private final class StubDaxPetHistoryConsent: DaxPetHistoryConsent {
    var canSearchHistory: Bool?
}

@MainActor
private final class StubDaxPetScreenLooker: DaxPetScreenLooking {
    var foregroundApp: DaxPetForegroundApp? = DaxPetForegroundApp(name: "Mail", processIdentifier: 42)
    var screenshot: NSImage? = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
        NSColor.blue.setFill()
        rect.fill()
        return true
    }
    var captures = 0

    func captureWindow(of app: DaxPetForegroundApp) async -> NSImage? {
        captures += 1
        return screenshot
    }
}

@MainActor
final class DaxPetViewModelTests: XCTestCase {

    private var submitter: RecordingDaxPetPromptSubmitter!
    private var model: DaxPetViewModel!

    override func setUp() {
        super.setUp()
        submitter = RecordingDaxPetPromptSubmitter()
        model = DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { true }))
        model.submissionDelay = 0
    }

    override func tearDown() {
        model = nil
        submitter = nil
        super.tearDown()
    }

    func testWhenDaxIsClickedThenPromptFieldOpensAndAsksForKeyboard() {
        var keyboardRequests = 0
        model.onNeedsKeyboard = { keyboardRequests += 1 }

        model.characterClicked()

        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.character.mood, .listening)
        XCTAssertEqual(model.speech, UserText.daxPetGreeting)
        XCTAssertEqual(keyboardRequests, 1)
    }

    func testWhenDaxIsClickedWhileComposingThenPromptFieldCloses() {
        model.characterClicked()
        model.prompt = "draft"

        model.characterClicked()

        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.prompt, "")
        XCTAssertEqual(model.character.mood, .idle)
        XCTAssertNil(model.speech)
    }

    func testWhenTypingThenDaxWatchesTheCaretAndStopsTalking() {
        var requestedWidths: [CGFloat] = []
        model.caretLocation = { width in
            requestedWidths.append(width)
            return NSPoint(x: 100 + width, y: 10)
        }
        model.startComposing()

        model.prompt = "Hello"

        XCTAssertNil(model.speech)
        XCTAssertGreaterThan(requestedWidths.last ?? 0, 0)
        XCTAssertEqual(model.character.lookTarget, NSPoint(x: 100 + (requestedWidths.last ?? 0), y: 10))
    }

    func testWhenPromptIsSubmittedThenItIsTrimmedAndHandedToDuckAI() {
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "  What's a duck?  \n"

        model.submit()

        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.character.mood, .thinking)
        XCTAssertEqual(model.speech, UserText.daxPetThinking)
        wait(for: [submitted], timeout: 1)
        XCTAssertEqual(submitter.submittedPrompts, ["What's a duck?"])
        XCTAssertNil(model.speech)
    }

    func testWhenPromptIsBlankThenNothingIsSubmitted() {
        model.startComposing()
        model.prompt = "   "

        model.submit()

        XCTAssertTrue(model.isComposing)
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)
    }

    func testWhenFocusIsLostWithADraftThenTheDraftIsKept() {
        model.startComposing()
        model.prompt = "draft"

        model.keyboardFocusLost()

        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.prompt, "draft")
    }

    func testWhenFocusIsLostWithoutADraftThenPromptFieldCloses() {
        model.startComposing()

        model.keyboardFocusLost()

        XCTAssertFalse(model.isComposing)
    }

    func testWhenHiddenThenComposingEndsAndOwnerIsTold() {
        var hideCount = 0
        model.onHide = { hideCount += 1 }
        model.startComposing()

        model.hide()

        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(hideCount, 1)
    }

    func testWhenDaxFallsAsleepThenTheViewShowsItAndHeStopsTalking() {
        var idleTime: TimeInterval = 0
        model = DaxPetViewModel(submitter: submitter,
                                character: DaxCharacterView(reduceMotion: { true }, idleTime: { idleTime }))
        model.sayHello()

        idleTime = DaxCharacterView.sleepDelay
        model.character.step()

        XCTAssertTrue(model.isAsleep)
        XCTAssertNil(model.speech)

        idleTime = 0
        model.character.step()

        XCTAssertFalse(model.isAsleep)
    }

    func testWhenDaxLovesBeingPettedThenHeartsPopOut() {
        XCTAssertNil(model.heartBurst)

        model.character.onLovedPetting?()
        let first = model.heartBurst
        model.character.onLovedPetting?()

        XCTAssertNotNil(first)
        XCTAssertNotEqual(model.heartBurst, first)
    }

    // MARK: - Duck.ai answers

    func testWhenDuckAIStartsAnsweringThenDaxThinksUntilItIsDone() {
        model.answerStarted()

        XCTAssertEqual(model.character.mood, .thinking)
        XCTAssertTrue(model.isAwaitingAnswer)

        model.answerFinished(succeeded: true, isBrowserActive: true)

        XCTAssertEqual(model.character.mood, .idle)
        XCTAssertFalse(model.isAwaitingAnswer)
        XCTAssertNil(model.speech)
    }

    func testWhenTheAnswerIsReadyWithTheBrowserInTheBackgroundThenDaxPointsItOut() {
        model.answerStarted()

        model.answerFinished(succeeded: true, isBrowserActive: false)

        XCTAssertEqual(model.speech, UserText.daxPetAnswerReady)
        XCTAssertTrue(model.hasUnseenAnswer)
    }

    func testWhenDaxIsClickedWithAnUnseenAnswerThenTheBrowserComesForward() {
        model.answerStarted()
        model.answerFinished(succeeded: true, isBrowserActive: false)

        model.characterClicked()

        XCTAssertEqual(submitter.showBrowserCount, 1)
        XCTAssertFalse(model.isComposing)
        XCTAssertFalse(model.hasUnseenAnswer)
        XCTAssertNil(model.speech)
    }

    func testWhenDuckAIFailsThenDaxSaysSo() {
        model.answerStarted()

        model.answerFinished(succeeded: false, isBrowserActive: true)

        XCTAssertEqual(model.speech, UserText.daxPetAnswerFailed)
        XCTAssertFalse(model.hasUnseenAnswer)
    }

    func testWhenAnAnswerFinishesThatDaxNeverSawStartThenHeIgnoresIt() {
        model.answerFinished(succeeded: true, isBrowserActive: false)

        XCTAssertNil(model.speech)
        XCTAssertFalse(model.hasUnseenAnswer)
    }

    func testWhenDuckAIAnswersWhileAPromptIsTypedThenDaxKeepsListeningAndThinksAfterwards() {
        model.startComposing()

        model.answerStarted()
        XCTAssertEqual(model.character.mood, .listening)

        model.endComposing()
        XCTAssertEqual(model.character.mood, .thinking)
    }

    func testWhenAPromptIsSentThenDaxKeepsThinkingUntilTheAnswerIsIn() {
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What's a duck?"

        model.submit()
        wait(for: [submitted], timeout: 1)

        XCTAssertEqual(model.character.mood, .thinking)
        XCTAssertTrue(model.isAwaitingAnswer)
    }

    // MARK: - Quick actions

    func testWhenAskedToSummarizeThenThePageIsHandedToDuckAIAndComposingEnds() async {
        model.startComposing()

        await model.summarizePage()

        XCTAssertEqual(submitter.summarizeCount, 1)
        XCTAssertFalse(model.isComposing)
        XCTAssertNil(model.speech)
    }

    func testWhenThereIsNoPageToSummarizeThenDaxSaysSo() async {
        submitter.summarizeResult = false

        await model.summarizePage()

        XCTAssertEqual(model.speech, UserText.daxPetSummarizeNoPage)
    }

    func testWhenAskedToContinueTheLastChatThenItReopens() async {
        await model.continueLastChat()

        XCTAssertEqual(submitter.continueCount, 1)
        XCTAssertNil(model.speech)
    }

    func testWhenThereIsNoChatToContinueThenDaxSaysSo() async {
        submitter.continueResult = false

        await model.continueLastChat()

        XCTAssertEqual(model.speech, UserText.daxPetContinueNoChat)
    }

    func testWhetherAPageCanBeSummarizedComesFromTheBrowser() {
        submitter.canSummarizeCurrentPage = false
        XCTAssertFalse(model.canSummarizeCurrentPage)

        submitter.canSummarizeCurrentPage = true
        XCTAssertTrue(model.canSummarizeCurrentPage)
    }

    // MARK: - Drops

    func testWhenTextIsDroppedThenDaxAsksAboutItWithThePromptOpen() async {
        await model.receive([.text("Ducks can sleep with one eye open.")])

        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.attachments.count, 1)
        XCTAssertEqual(model.speech, UserText.daxPetDropQuestion)
    }

    func testWhenADroppedItemIsRefusedThenDaxSaysWhyAndStaysPut() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try "PK".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.receive([.file(url)])

        XCTAssertFalse(model.isComposing)
        XCTAssertTrue(model.attachments.isEmpty)
        XCTAssertNotNil(model.speech)
    }

    func testWhenAPromptIsSentWithDroppedTextThenTheTextGoesWithIt() async {
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        await model.receive([.text("Quack")])
        model.prompt = "Translate"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submitter.submittedPrompts, ["Translate\n\nQuack"])
        XCTAssertTrue(model.attachments.isEmpty)
    }

    func testWhenAttachmentsAreRemovedThenThePromptStaysOpen() async {
        await model.receive([.text("Quack")])

        model.removeAttachments()

        XCTAssertTrue(model.attachments.isEmpty)
        XCTAssertTrue(model.isComposing)
    }

    func testWhenComposingEndsThenDroppedItemsAreDropped() async {
        await model.receive([.text("Quack")])

        model.endComposing()

        XCTAssertTrue(model.attachments.isEmpty)
    }

    // MARK: - On-device suggestions

    private func makeModel(suggesting suggestions: [String]) -> (DaxPetViewModel, StubDaxPetIntelligence) {
        let intelligence = StubDaxPetIntelligence()
        intelligence.suggestions = suggestions
        let model = DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { true }), intelligence: intelligence)
        model.submissionDelay = 0
        return (model, intelligence)
    }

    func testWhenSomethingIsDroppedThenTheOnDeviceSuggestionsReplaceTheQuestion() async {
        let (model, _) = makeModel(suggesting: ["Summarize it", "List the dates", "Explain the jargon", "One too many"])

        await model.receive([.text("Quack")])

        XCTAssertEqual(model.suggestions, ["Summarize it", "List the dates", "Explain the jargon"])
        XCTAssertNil(model.speech)
    }

    func testWhenThereAreNoSuggestionsThenDaxKeepsAsking() async {
        let (model, _) = makeModel(suggesting: [])

        await model.receive([.text("Quack")])

        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertEqual(model.speech, UserText.daxPetDropQuestion)
    }

    func testWhenTheUserTypesBeforeTheSuggestionsArriveThenTheyAreNotShown() async {
        let (model, intelligence) = makeModel(suggesting: ["Summarize it"])
        intelligence.onSuggest = { model.prompt = "My own question" }

        await model.receive([.text("Quack")])

        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testWhenASuggestionIsChosenThenItIsSentWithTheDrop() async {
        let (model, _) = makeModel(suggesting: ["Summarize it"])
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        await model.receive([.text("Quack")])

        model.useSuggestion("Summarize it")
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submitter.submittedPrompts, ["Summarize it\n\nQuack"])
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testWhenTypingStartsThenTheSuggestionsGo() async {
        let (model, _) = makeModel(suggesting: ["Summarize it"])
        await model.receive([.text("Quack")])

        model.prompt = "T"

        XCTAssertTrue(model.suggestions.isEmpty)
    }

    // MARK: - Guessed action

    func testWhenTheOnDeviceModelRecognizesCodeThenDaxOffersToExplainIt() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.kind = .code

        await model.receive([.text("let quack = Duck()")])

        XCTAssertEqual(model.dropAction, .explainCode)
        XCTAssertEqual(model.promptPlaceholder, UserText.daxPetActionExplainCode)
        XCTAssertTrue(model.canSubmit)
    }

    func testWhenReturnIsPressedWithNothingTypedThenTheGuessedActionIsSent() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.kind = .article
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        await model.receive([.text("Ducks can sleep with one eye open.")])

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submitter.submittedPrompts, [UserText.daxPetActionSummarize + "\n\nDucks can sleep with one eye open."])
    }

    func testWhatTheUserTypesWinsOverTheGuess() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.kind = .article
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        await model.receive([.text("Quack")])
        model.prompt = "Make it rhyme"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submitter.submittedPrompts, ["Make it rhyme\n\nQuack"])
    }

    func testWhenTypingIsDeletedThenTheGuessComesBack() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.kind = .message
        await model.receive([.text("Hi Dax, are you free tomorrow?")])

        model.prompt = "W"
        model.prompt = ""

        XCTAssertEqual(model.promptPlaceholder, UserText.daxPetActionReply)
    }

    func testWithNoDropThereIsNoGuessAndAnEmptyPromptCantBeSent() {
        model.startComposing()

        XCTAssertNil(model.dropAction)
        XCTAssertEqual(model.promptPlaceholder, UserText.daxPetPromptPlaceholder)
        XCTAssertFalse(model.canSubmit)
    }

    // MARK: - Page glance

    private let page = DaxPetPageContent(url: "https://duckduckgo.com/about", title: "About", text: "We protect your privacy.")

    func testWhenThePointerRestsOnDaxThenHeSumsUpTheOpenPage() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "DuckDuckGo explains how it protects privacy.",
                                                   followUps: ["Compare with other browsers", "Explain tracker blocking", "List the features", "One too many"])
        submitter.page = page

        await model.glanceAtPage()

        XCTAssertEqual(model.glance?.summary, "DuckDuckGo explains how it protects privacy.")
        XCTAssertEqual(model.glance?.followUps, ["Compare with other browsers", "Explain tracker blocking", "List the features"])
        XCTAssertEqual(model.character.mood, .idle)
    }

    func testDaxDoesNotSumUpTheSamePageTwiceInAWhile() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "A page.", followUps: [])
        submitter.page = page
        var now = Date()
        model.now = { now }
        await model.glanceAtPage()
        model.startComposing()
        model.endComposing()

        await model.glanceAtPage()
        XCTAssertEqual(intelligence.pageSummaryCount, 1)

        now += model.glanceCooldown
        await model.glanceAtPage()
        XCTAssertEqual(intelligence.pageSummaryCount, 2)
    }

    func testWithoutTheOnDeviceModelOrAPageThereIsNoGlance() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "A page.", followUps: [])

        await model.glanceAtPage()
        XCTAssertNil(model.glance)

        submitter.page = page
        intelligence.isOnDevice = false
        await model.glanceAtPage()
        XCTAssertNil(model.glance)
        XCTAssertEqual(intelligence.pageSummaryCount, 0)
    }

    func testWhenDaxIsBusyThereIsNoGlance() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "A page.", followUps: [])
        submitter.page = page
        model.startComposing()

        await model.glanceAtPage()

        XCTAssertNil(model.glance)
        XCTAssertEqual(intelligence.pageSummaryCount, 0)
    }

    func testWithoutFollowUpsAskingForMoreGetsTheWholePageSummarized() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "A page.", followUps: [])
        submitter.page = page
        await model.glanceAtPage()

        await model.askAboutGlance()

        XCTAssertNil(model.glance)
        XCTAssertEqual(submitter.pageRequests, [UserText.daxPetSummarizePrompt])
    }

    func testAChosenFollowUpIsSentToDuckAIWithThePage() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "A page.", followUps: ["Explain tracker blocking"])
        submitter.page = page
        await model.glanceAtPage()

        await model.askAboutGlance("Explain tracker blocking")

        XCTAssertNil(model.glance)
        XCTAssertEqual(submitter.pageRequests, ["Explain tracker blocking"])
    }

    func testOpeningThePromptPutsTheGlanceAway() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.pageGlance = DaxPetPageGlance(summary: "A page.", followUps: [])
        submitter.page = page
        await model.glanceAtPage()

        model.startComposing()

        XCTAssertNil(model.glance)
    }

    // MARK: - The app in front

    private static let imageCapabilities = DaxPetAttachmentCapabilities(
        model: AIChatModel(id: "model", name: "Model", provider: .openAI, supportsImageUpload: true,
                           supportedImageFormats: ["png", "jpeg"], entityHasAccess: true),
        limits: AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 10, maxTotalFileSizeBytes: 30_000_000, maxPagesPerFile: 100),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 10, maxInputCharsWithAttachments: 10_000)))

    private func makeSeeingModel(canSee: Bool = true, refersToScreen: Bool = true)
        -> (DaxPetViewModel, StubDaxPetIntelligence, StubDaxPetScreenLooker) {
        let intelligence = StubDaxPetIntelligence()
        intelligence.refersToScreen = refersToScreen
        let looker = StubDaxPetScreenLooker()
        submitter.capabilities = Self.imageCapabilities
        let model = DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { true }),
                                    intelligence: intelligence, screenLooker: looker, canSeeForegroundApp: { canSee })
        model.submissionDelay = 0
        return (model, intelligence, looker)
    }

    /// Lets the screen check, which runs in a task off `submit()`, finish; its stubs never suspend for long.
    private func settle(_ model: DaxPetViewModel) async {
        for _ in 0..<50 { await Task.yield() }
    }

    func testWhenAskedAboutTheScreenThenAScreenshotIsAddedAndNothingIsSentYet() async {
        let (model, intelligence, looker) = makeSeeingModel()
        model.startComposing()
        model.prompt = "What is this?"

        model.submit()
        await settle(model)

        XCTAssertEqual(intelligence.screenChecks, ["What is this?"])
        XCTAssertEqual(looker.captures, 1)
        XCTAssertEqual(model.attachments.map(\.name), [UserText.daxPetScreenFileName("Mail") + ".jpg"])
        XCTAssertEqual(model.speech, UserText.daxPetScreenReady("Mail"))
        XCTAssertTrue(model.isComposing)
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)
    }

    func testTheNextReturnSendsTheQuestionWithTheScreenshot() async throws {
        let (model, _, looker) = makeSeeingModel()
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What is this?"
        model.submit()
        await settle(model)

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(looker.captures, 1)
        XCTAssertEqual(submitter.submittedPrompts, ["What is this?"])
        guard case .query(let query) = try XCTUnwrap(submitter.submittedPayloads.last??.tool) else { return XCTFail("Expected a query") }
        XCTAssertEqual(query.images?.count, 1)
        XCTAssertEqual(query.images?.first?.format, "jpeg")
    }

    func testRemovingTheScreenshotSendsTheQuestionWithoutIt() async {
        let (model, _, _) = makeSeeingModel()
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What is this?"
        model.submit()
        await settle(model)

        model.removeAttachments()
        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submitter.submittedPrompts, ["What is this?"])
        XCTAssertNil(submitter.submittedPayloads.last ?? nil)
    }

    func testAQuestionThatStandsOnItsOwnIsSentWithoutLooking() async {
        let (model, intelligence, looker) = makeSeeingModel(refersToScreen: false)
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "Write a poem about ducks"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(intelligence.screenChecks, ["Write a poem about ducks"])
        XCTAssertEqual(looker.captures, 0)
        XCTAssertEqual(submitter.submittedPrompts, ["Write a poem about ducks"])
    }

    func testWithoutTheSettingDaxNeverLooks() async {
        let (model, intelligence, looker) = makeSeeingModel(canSee: false)
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What is this?"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertTrue(intelligence.screenChecks.isEmpty)
        XCTAssertEqual(looker.captures, 0)
    }

    func testWhenSomethingWasDroppedDaxDoesNotLookAtTheScreen() async {
        let (model, intelligence, _) = makeSeeingModel()
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        await model.receive([.text("Quack")])
        model.prompt = "What is this?"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertTrue(intelligence.screenChecks.isEmpty)
    }

    func testWhenTheModelCannotTakeImagesTheQuestionGoesWithoutAScreenshot() async {
        let (model, _, looker) = makeSeeingModel()
        submitter.capabilities = .unknown
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What is this?"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(looker.captures, 0)
        XCTAssertEqual(submitter.submittedPrompts, ["What is this?"])
    }

    func testWhenTheScreenCannotBeCapturedDaxSaysWhyAndTheNextReturnSendsAnyway() async {
        let (model, _, looker) = makeSeeingModel()
        looker.screenshot = nil
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What is this?"
        model.submit()
        await settle(model)

        XCTAssertEqual(model.speech, UserText.daxPetScreenNoPermission("Mail"))
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(submitter.submittedPrompts, ["What is this?"])
    }

    func testWithNoOtherAppInFrontDaxDoesNotLook() async {
        let (model, intelligence, looker) = makeSeeingModel()
        looker.foregroundApp = nil
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "What is this?"

        model.submit()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertTrue(intelligence.screenChecks.isEmpty)
    }

    // MARK: - Varied lines

    func testWhenTheOnDeviceModelRewordsALineThenDaxSaysBothVersions() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.variations[UserText.daxPetGreeting] = ["Hi! What shall we ask?"]
        await model.prepareLineVariations()

        var said = Set<String>()
        for _ in 0..<50 {
            model.startComposing()
            said.insert(model.speech ?? "")
            model.endComposing()
        }

        XCTAssertEqual(said, [UserText.daxPetGreeting, "Hi! What shall we ask?"])
    }

    func testRewordingsThatAreTooLongBlankOrUnchangedAreThrownAway() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.variations[UserText.daxPetGreeting] = [
            String(repeating: "Quack ", count: 20), "   ", "\"\"", UserText.daxPetGreeting
        ]
        await model.prepareLineVariations()

        for _ in 0..<20 {
            model.startComposing()
            XCTAssertEqual(model.speech, UserText.daxPetGreeting)
            model.endComposing()
        }
    }

    func testARewordedQuestionMustStillBeAQuestion() async {
        let (model, intelligence) = makeModel(suggesting: [])
        intelligence.variations[UserText.daxPetGreeting] = ["Let's find out!"]
        await model.prepareLineVariations()

        for _ in 0..<20 {
            model.startComposing()
            XCTAssertEqual(model.speech, UserText.daxPetGreeting)
            model.endComposing()
        }
    }

    func testWithoutTheOnDeviceModelDaxSaysHisUsualLines() async {
        await model.prepareLineVariations()

        model.startComposing()

        XCTAssertEqual(model.speech, UserText.daxPetGreeting)
    }

    // MARK: - Debug

    func testTheDebugMenuOffersEveryPoseAndBothAnswerBubbles() {
        let actions = DaxPetViewModel.DebugAction.allCases

        XCTAssertEqual(actions.count, DaxCharacterView.DebugPose.allCases.count + 2)
        XCTAssertEqual(Set(actions.map(\.title)).count, actions.count)
    }

    // MARK: - Typing

    private func makeLivelyModel() -> DaxPetViewModel {
        DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { false }, idleTime: { 0 }))
    }

    func testWhenAWordIsFinishedThenDaxNods() {
        model = makeLivelyModel()
        model.startComposing()

        model.prompt = "Hello"
        XCTAssertFalse(model.character.isNodding)

        model.prompt = "Hello "
        XCTAssertTrue(model.character.isNodding)
    }

    func testWhenDeletingBackToASpaceThenDaxDoesNotNod() {
        model = makeLivelyModel()
        model.startComposing()
        model.prompt = "Hello w"

        model.prompt = "Hello "

        XCTAssertFalse(model.character.isNodding)
    }

    func testWhenThePromptGetsLongThenDaxMarvels() {
        model = makeLivelyModel()
        model.startComposing()
        model.prompt = String(repeating: "a", count: DaxPetViewModel.longPromptLength - 1)
        XCTAssertFalse(model.character.isMarveling)

        model.prompt += "a"

        XCTAssertTrue(model.character.isMarveling)
    }

    func testWhenTypingPausesThenDaxGivesOneSlowBlink() {
        model = makeLivelyModel()
        model.startComposing()
        model.prompt = "Hello"

        var slowBlinks = 0
        var wasSlowBlinking = false
        for _ in 0..<Int((DaxCharacterView.typingPause + 3) * 30) {
            model.character.step()
            if model.character.isSlowBlinking, !wasSlowBlinking { slowBlinks += 1 }
            wasSlowBlinking = model.character.isSlowBlinking
        }

        XCTAssertEqual(slowBlinks, 1)
    }

    func testWhenNotComposingThenAPauseBringsNoSlowBlink() {
        model = makeLivelyModel()
        model.character.noticeTyping()

        for _ in 0..<Int((DaxCharacterView.typingPause + 1) * 30) {
            model.character.step()
            XCTAssertFalse(model.character.isSlowBlinking)
        }
    }

    func testWhenOpenDuckAIIsTappedThenANewChatOpens() {
        model.openDuckAI()

        XCTAssertEqual(submitter.openDuckAICount, 1)
    }

    // MARK: - Lookups in the browser

    private static let flights = DaxPetTab(id: "1", title: "Google Flights", url: URL(string: "https://www.google.com/travel/flights")!)
    private static let github = DaxPetTab(id: "2", title: "Pull requests", url: URL(string: "https://github.com/pulls")!)
    private static let hotel = DaxPetTab(id: "3", title: "Hotel Adlon", url: URL(string: "https://www.booking.com/adlon")!)

    private func makeLookingModel(isOnDevice: Bool = true, consent: Bool? = true)
        -> (DaxPetViewModel, StubDaxPetIntelligence, StubDaxPetBrowser, StubDaxPetHistoryConsent) {
        let intelligence = StubDaxPetIntelligence()
        intelligence.isOnDevice = isOnDevice
        let browser = StubDaxPetBrowser()
        browser.openTabs = [Self.flights, Self.github, Self.hotel]
        let historyConsent = StubDaxPetHistoryConsent()
        historyConsent.canSearchHistory = consent
        let model = DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { true }),
                                    intelligence: intelligence, browsing: browser, historyConsent: historyConsent)
        model.submissionDelay = 0
        return (model, intelligence, browser, historyConsent)
    }

    private func ask(_ model: DaxPetViewModel, _ prompt: String) async {
        model.startComposing()
        model.prompt = prompt
        model.submit()
        await settle(model)
    }

    func testWhenTheOneTabAskedForIsFoundThenItComesForwardAndNothingGoesToDuckAI() async {
        let (model, intelligence, browser, _) = makeLookingModel()
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["flights"], daysBack: 0)
        intelligence.picks = [0]

        await ask(model, "where's my flights tab?")

        XCTAssertEqual(intelligence.pickedFrom, [["Google Flights — www.google.com"]])
        XCTAssertEqual(browser.switchedTo, [Self.flights])
        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.speech, UserText.daxPetFoundHere)
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)
    }

    func testWhenNoTabHasTheWordsThenTheModelChoosesFromThemAll() async {
        let (model, intelligence, _, _) = makeLookingModel()
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["email"], daysBack: 0)

        await ask(model, "take me to my email")

        XCTAssertEqual(intelligence.pickedFrom.first?.count, 3)
    }

    func testWhenSeveralTabsMatchThenTheyAreOfferedWithDuckAIAsTheWayOn() async {
        let (model, intelligence, browser, _) = makeLookingModel()
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["o"], daysBack: 0)
        intelligence.picks = [2, 0]

        await ask(model, "which tab was it?")

        XCTAssertEqual(model.findings, DaxPetFindings(headline: UserText.daxPetFoundTabs, content: .items([.tab(Self.hotel), .tab(Self.flights)])))
        XCTAssertTrue(model.isComposing)

        model.openFinding(.tab(Self.hotel))

        XCTAssertEqual(browser.switchedTo, [Self.hotel])
        XCTAssertNil(model.findings)
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)
    }

    func testWhenNothingIsFoundThenTheRequestGoesToDuckAI() async {
        let (model, intelligence, browser, _) = makeLookingModel()
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["weather"], daysBack: 0)
        intelligence.picks = []

        await ask(model, "where's the weather tab?")

        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(submitter.submittedPrompts, ["where's the weather tab?"])
        XCTAssertTrue(browser.switchedTo.isEmpty)
        XCTAssertNil(model.findings)
    }

    func testAQuestionForDuckAIGoesStraightOn() async {
        let (model, intelligence, browser, _) = makeLookingModel()
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        intelligence.lookup = nil

        await ask(model, "what's the capital of France?")

        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(intelligence.lookups, ["what's the capital of France?"])
        XCTAssertTrue(intelligence.pickedFrom.isEmpty)
        XCTAssertTrue(browser.searches.isEmpty)
        XCTAssertEqual(submitter.submittedPrompts, ["what's the capital of France?"])
    }

    func testWithoutAppleIntelligenceEveryRequestGoesStraightToDuckAI() async {
        let (model, intelligence, browser, _) = makeLookingModel(isOnDevice: false)
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["flights"], daysBack: 0)

        await ask(model, "where's my flights tab?")

        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertTrue(intelligence.lookups.isEmpty)
        XCTAssertTrue(browser.switchedTo.isEmpty)
        XCTAssertEqual(submitter.submittedPrompts, ["where's my flights tab?"])
    }

    func testWhenPagesFromTheHistoryMatchThenTheyAreOfferedAndOneOpens() async throws {
        let (model, intelligence, browser, _) = makeLookingModel()
        let recipe = DaxPetVisit(title: "Carbonara", url: try XCTUnwrap(URL(string: "https://food.example/carbonara")), date: Date())
        browser.visits = [recipe]
        intelligence.lookup = DaxPetLookup(kind: .history, terms: ["recipe"], daysBack: 1)
        intelligence.picks = [0]

        await ask(model, "the recipe I looked at yesterday")

        XCTAssertEqual(browser.searches, [["recipe"]])
        XCTAssertEqual(model.findings, DaxPetFindings(headline: UserText.daxPetFoundHistory, content: .items([.visit(recipe)])))

        model.openFinding(.visit(recipe))

        XCTAssertEqual(browser.opened, [recipe.url])
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)
    }

    func testThePagesFromWhenTheUserSaidComeFirst() async throws {
        let (model, intelligence, browser, _) = makeLookingModel()
        let now = Date()
        model.now = { now }
        let old = DaxPetVisit(title: "Old", url: try XCTUnwrap(URL(string: "https://a.example/")), date: now.addingTimeInterval(-30 * 86_400))
        let recent = DaxPetVisit(title: "Recent", url: try XCTUnwrap(URL(string: "https://b.example/")), date: now.addingTimeInterval(-3_600))
        browser.visits = [old, recent]
        intelligence.lookup = DaxPetLookup(kind: .history, terms: ["a"], daysBack: 1)

        await ask(model, "that page from yesterday")

        XCTAssertEqual(intelligence.pickedFrom.first?.map { $0.components(separatedBy: " — ").first }, ["Recent", "Old"])
    }

    func testBeforeTheFirstHistorySearchDaxAsksAndAYesSearchesFromThenOn() async throws {
        let (model, intelligence, browser, consent) = makeLookingModel(consent: nil)
        browser.visits = [DaxPetVisit(title: "Carbonara", url: try XCTUnwrap(URL(string: "https://food.example/")), date: Date())]
        intelligence.lookup = DaxPetLookup(kind: .history, terms: ["recipe"], daysBack: 0)
        intelligence.picks = [0]

        await ask(model, "the recipe from yesterday")

        XCTAssertEqual(model.findings, DaxPetFindings(headline: UserText.daxPetHistoryAsk, content: .askingToSearchHistory))
        XCTAssertTrue(browser.searches.isEmpty)

        model.allowHistorySearch()
        await settle(model)

        XCTAssertEqual(consent.canSearchHistory, true)
        XCTAssertEqual(browser.searches, [["recipe"]])
        XCTAssertEqual(model.findings?.headline, UserText.daxPetFoundHistory)
    }

    func testTurningDownTheHistorySearchSendsTheRequestToDuckAIAndDaxDoesNotAskAgain() async {
        let (model, intelligence, browser, consent) = makeLookingModel(consent: nil)
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        intelligence.lookup = DaxPetLookup(kind: .history, terms: ["recipe"], daysBack: 0)
        await ask(model, "the recipe from yesterday")

        model.askDuckAIInstead()

        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(consent.canSearchHistory, false)
        XCTAssertTrue(browser.searches.isEmpty)
        XCTAssertEqual(submitter.submittedPrompts, ["the recipe from yesterday"])
    }

    func testWithoutLeaveToSearchTheHistoryTheRequestGoesToDuckAI() async {
        let (model, intelligence, browser, _) = makeLookingModel(consent: false)
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        intelligence.lookup = DaxPetLookup(kind: .history, terms: ["recipe"], daysBack: 0)

        await ask(model, "the recipe from yesterday")

        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertTrue(browser.searches.isEmpty)
        XCTAssertNil(model.findings)
    }

    func testAskingDuckAIInsteadSendsTheRequestWithoutLookingAgain() async {
        let (model, intelligence, _, _) = makeLookingModel()
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["o"], daysBack: 0)
        intelligence.picks = [0, 1]
        await ask(model, "which tab was it?")

        model.askDuckAIInstead()

        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(intelligence.lookups.count, 1)
        XCTAssertEqual(submitter.submittedPrompts, ["which tab was it?"])
    }

    func testTypingPutsTheFindingsAway() async {
        let (model, intelligence, _, _) = makeLookingModel()
        intelligence.lookup = DaxPetLookup(kind: .openTab, terms: ["o"], daysBack: 0)
        intelligence.picks = [0, 1]
        await ask(model, "which tab was it?")

        model.prompt = "which tab was it? the blue one"

        XCTAssertNil(model.findings)
    }

    // MARK: - Duck.ai in the browser

    private func activity(_ tool: String, _ phase: AIChatBrowserToolActivity.Phase, subject: String? = nil, callID: String = "call") -> AIChatBrowserToolActivity {
        AIChatBrowserToolActivity(callID: callID, toolName: tool, subject: subject, phase: phase)
    }

    func testWhenDuckAIReadsAPageThenDaxSaysWhichAndReadsAlong() {
        model.browserToolActivity(activity("readTabContent", .started, subject: "Hotel Adlon"))

        XCTAssertEqual(model.speech, UserText.daxPetToolReading("Hotel Adlon"))
        XCTAssertEqual(model.character.currentGaze, .read)
    }

    func testWhenDuckAILooksThroughTabsOrHistoryThenDaxLooksAround() {
        model.browserToolActivity(activity("listOpenTabs", .started))
        XCTAssertEqual(model.speech, UserText.daxPetToolTabs)
        XCTAssertEqual(model.character.currentGaze, .search)

        model.browserToolActivity(activity("searchHistory", .started, subject: "rust"))
        XCTAssertEqual(model.speech, UserText.daxPetToolHistory(for: "rust"))
    }

    func testLongTitlesAreCutToFitTheBubble() {
        model.browserToolActivity(activity("readTabContent", .started, subject: String(repeating: "a", count: 60)))

        XCTAssertEqual(model.speech, UserText.daxPetToolReading(String(repeating: "a", count: 27) + "…"))
    }

    func testToolsDaxDoesNotKnowPassUnremarked() {
        model.browserToolActivity(activity("openTab", .started, subject: "Something"))

        XCTAssertNil(model.speech)
    }

    func testWhileTheUserTypesDaxKeepsQuietAboutTheBrowser() {
        model.startComposing()
        model.prompt = "draft"

        model.browserToolActivity(activity("listOpenTabs", .started))
        model.browserToolActivity(activity("listOpenTabs", .awaitingPermission))

        XCTAssertNil(model.speech)
        XCTAssertFalse(model.isPointingAtPermission)
    }

    func testWhenDuckAIWaitsForTheUsersOKThenDaxSaysWhatForUntilItIsAnswered() {
        model.browserToolActivity(activity("readTabContent", .started, subject: "Hotel Adlon"))
        model.browserToolActivity(activity("readTabContent", .awaitingPermission, subject: "Hotel Adlon"))

        XCTAssertEqual(model.speech, UserText.daxPetPermissionReading("Hotel Adlon"))
        XCTAssertTrue(model.isPointingAtPermission)

        model.browserToolActivity(activity("listOpenTabs", .finished(succeeded: true), callID: "another"))
        XCTAssertTrue(model.isPointingAtPermission)

        model.browserToolActivity(activity("readTabContent", .finished(succeeded: true), subject: "Hotel Adlon"))
        XCTAssertFalse(model.isPointingAtPermission)
        XCTAssertNil(model.speech)
    }

    func testWhileDuckAIWaitsForTheUsersOKClickingDaxBringsTheChatForward() {
        model.browserToolActivity(activity("searchHistory", .awaitingPermission))

        model.characterClicked()

        XCTAssertEqual(submitter.showBrowserCount, 1)
        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.speech, UserText.daxPetPermissionHistory)
    }

    func testWhileDuckAIWaitsForTheUsersOKOtherCallsDoNotTalkOverIt() {
        model.browserToolActivity(activity("listOpenTabs", .awaitingPermission))

        model.browserToolActivity(activity("findInPage", .started, subject: "price", callID: "another"))

        XCTAssertEqual(model.speech, UserText.daxPetPermissionTabs)
    }

    func testRewordingsInWhichDaxNamesHimselfAreThrownAway() async {
        let intelligence = StubDaxPetIntelligence()
        intelligence.variations = [UserText.daxPetToolTabs: ["Dax is peeking at your tabs!"]]
        let model = DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { true }), intelligence: intelligence)

        await model.prepareLineVariations()
        model.browserToolActivity(activity("listOpenTabs", .started))

        XCTAssertEqual(model.speech, UserText.daxPetToolTabs)
    }
}
