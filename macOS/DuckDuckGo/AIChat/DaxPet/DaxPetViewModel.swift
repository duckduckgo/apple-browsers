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

@MainActor
protocol DaxPetPromptSubmitting {
    /// `payload` carries attachments and is applied once Duck.ai is open, as the address bar does.
    func submit(prompt: String, payload: AIChatNativePrompt?)
    func openDuckAI()
    /// Brings the browser forward, where Duck.ai's answer is waiting.
    func showBrowser()

    /// Whether the browser has a web page open that Duck.ai could summarize.
    var canSummarizeCurrentPage: Bool { get }
    /// Asks Duck.ai, beside the page, to summarize it; `false` when there's no page to summarize.
    func summarizeCurrentPage() async -> Bool
    /// Reopens the most recent Duck.ai chat; `false` when there are none.
    func continueLastChat() async -> Bool

    /// What the selected Duck.ai model accepts, to check items dropped on Dax against.
    func attachmentCapabilities() async -> DaxPetAttachmentCapabilities
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
    @Published var prompt = "" {
        didSet { promptDidChange(from: oldValue) }
    }

    let character: DaxCharacterView

    /// How long Dax shows he's on it before Duck.ai takes over the screen.
    var submissionDelay: TimeInterval = 0.7
    /// How long he waits for Duck.ai to start answering, and then to finish, before he stops thinking.
    var answerStartTimeout: TimeInterval = 15
    var answerFinishTimeout: TimeInterval = 120

    /// Waiting on Duck.ai to finish an answer.
    private(set) var isAwaitingAnswer = false
    /// An answer finished while the browser was in the background, and Dax is pointing it out.
    private(set) var hasUnseenAnswer = false

    var onHide: (() -> Void)?
    /// Asks the window to take keyboard focus.
    var onNeedsKeyboard: (() -> Void)?
    /// Where the end of the typed prompt sits, in screen coordinates, for Dax to watch it.
    var caretLocation: ((_ promptWidth: CGFloat) -> NSPoint?)?

    private let submitter: DaxPetPromptSubmitting
    private let intelligence: DaxPetIntelligence
    /// Rewordings of Dax's lines from the on-device model, by the line they replace.
    private var lineVariations: [String: [String]] = [:]
    private var speechWork: DispatchWorkItem?
    private var answerTimeoutWork: DispatchWorkItem?
    private var attachmentCapabilities = DaxPetAttachmentCapabilities.unknown

    init(submitter: DaxPetPromptSubmitting, character: DaxCharacterView? = nil, intelligence: DaxPetIntelligence? = nil) {
        self.submitter = submitter
        self.intelligence = intelligence ?? DaxPetNoIntelligence()
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
        if hasUnseenAnswer {
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
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let (query, payload) = DaxPetAttachmentLoader.prompt(prompt, attachments: attachments, capabilities: attachmentCapabilities)
        isComposing = false
        self.prompt = ""
        attachments = []
        clearSuggestions()
        character.lookTarget = nil
        character.mood = .thinking
        say(line(UserText.daxPetThinking))

        DispatchQueue.main.asyncAfter(deadline: .now() + submissionDelay) { [weak self] in
            guard let self else { return }
            submitter.submit(prompt: query, payload: payload)
            say(nil)
            // He keeps thinking until Duck.ai is done, or gives up if it never says it started.
            isAwaitingAnswer = true
            scheduleAnswerTimeout(after: answerStartTimeout)
        }
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

    /// Sends a suggested request as the prompt, with what was dropped.
    func useSuggestion(_ suggestion: String) {
        prompt = suggestion
        submit()
    }

    /// Asks the on-device model what to do with the drop; the question bubble gives way to its answers,
    /// unless the user has moved on by then.
    private func suggestRequests() async {
        let attachments = self.attachments
        let suggestions = await intelligence.suggestions(for: attachments)
        guard isComposing, prompt.isEmpty, !suggestions.isEmpty, self.attachments.map(\.id) == attachments.map(\.id) else { return }
        self.suggestions = Array(suggestions.prefix(3))
        say(nil)
    }

    private func clearSuggestions() {
        suggestions = []
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
        endComposing()
        hasUnseenAnswer = false
        if await submitter.summarizeCurrentPage() {
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
        if !prompt.isEmpty { clearSuggestions() }
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
        character.lookTarget = caretLocation?(width + DaxPetView.Metrics.attachmentsWidth(count: attachments.count))
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
    static let variedLines: [String] = [UserText.daxPetGreeting, UserText.daxPetThinking, UserText.daxPetDropQuestion]

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
