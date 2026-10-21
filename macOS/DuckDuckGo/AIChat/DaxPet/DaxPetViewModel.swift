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

    var onHide: (() -> Void)?
    /// Asks the window to take keyboard focus.
    var onNeedsKeyboard: (() -> Void)?
    /// Where the end of the typed prompt sits, in screen coordinates, for Dax to watch it.
    var caretLocation: ((_ promptWidth: CGFloat) -> NSPoint?)?

    private let submitter: DaxPetPromptSubmitting
    private var speechWork: DispatchWorkItem?

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
        if isComposing {
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
        character.mood = .idle
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
            character.mood = .idle
            character.hop()
            say(nil)
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
        let work = DispatchWorkItem { [weak self] in self?.speech = nil }
        speechWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
