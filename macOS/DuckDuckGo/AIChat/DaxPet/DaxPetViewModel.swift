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

import AppKit
import Combine

@MainActor
protocol DaxPetPromptSubmitting {
    func submit(prompt: String)
    func openDuckAI()
    /// Brings the browser forward, where Duck.ai's answer is waiting.
    func showBrowser()

    /// Whether the browser has a web page open that Duck.ai could summarize.
    var canSummarizeCurrentPage: Bool { get }
    /// Asks Duck.ai, beside the page, to summarize it; `false` when there's no page to summarize.
    func summarizeCurrentPage() async -> Bool
    /// Reopens the most recent Duck.ai chat; `false` when there are none.
    func continueLastChat() async -> Bool
}

@MainActor
final class DaxPetViewModel: ObservableObject {

    @Published private(set) var isComposing = false
    @Published private(set) var speech: String?
    @Published private(set) var isAsleep = false
    /// Changes each time hearts should pop out of Dax; `nil` when there are none.
    @Published private(set) var heartBurst: Int?
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
    private var speechWork: DispatchWorkItem?
    private var answerTimeoutWork: DispatchWorkItem?

    init(submitter: DaxPetPromptSubmitting, character: DaxCharacterView? = nil) {
        self.submitter = submitter
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
        say(UserText.daxPetGreeting)
        onNeedsKeyboard?()
        updateLookTarget()
    }

    func endComposing() {
        guard isComposing else { return }
        isComposing = false
        prompt = ""
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
        isComposing = false
        self.prompt = ""
        character.lookTarget = nil
        character.mood = .thinking
        say(UserText.daxPetThinking)

        DispatchQueue.main.asyncAfter(deadline: .now() + submissionDelay) { [weak self] in
            guard let self else { return }
            submitter.submit(prompt: prompt)
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
            character.hop()
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
        character.lookTarget = caretLocation?(width)
    }

    private func showHearts() {
        let burst = (heartBurst ?? 0) + 1
        heartBurst = burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.heartBurst == burst { self?.heartBurst = nil }
        }
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
