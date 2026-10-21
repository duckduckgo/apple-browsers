//
//  InlineVoiceToTextSession.swift
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

import Foundation

/// One dictation into an existing text field: speech is transcribed live and appended to the text
/// the field held when listening started, so the field can show it as the user speaks.
@MainActor
final class InlineVoiceToTextSession {

    enum EndReason: Equatable {
        /// The recognizer decided the user stopped speaking.
        case speechFinished
        /// The user ended listening, keeping what was transcribed.
        case stopped
        /// Recording failed or could not start.
        case failed
    }

    /// The field's text with the transcript so far appended, on every partial result.
    var onTextChange: ((String) -> Void)?
    /// Called once, with the final composed text.
    var onEnd: ((_ text: String, _ reason: EndReason) -> Void)?

    private(set) var isListening = false
    private(set) var transcript = ""

    private let baseText: String
    private let speechRecognizer: SpeechRecognizerProtocol
    private let dispatchToMain: (@escaping @MainActor () -> Void) -> Void
    private var hasEnded = false

    init(baseText: String,
         speechRecognizer: SpeechRecognizerProtocol = SpeechRecognizer(),
         dispatchToMain: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
             DispatchQueue.main.async { MainActor.assumeIsolated(work) }
         }) {
        self.baseText = baseText
        self.speechRecognizer = speechRecognizer
        self.dispatchToMain = dispatchToMain
    }

    var composedText: String {
        Self.compose(baseText: baseText, transcript: transcript)
    }

    func start() {
        guard !isListening, !hasEnded else { return }
        isListening = true
        let dispatchToMain = dispatchToMain
        speechRecognizer.startRecording { [weak self] text, error, speechDidFinish in
            dispatchToMain {
                self?.handleResult(text: text, error: error, speechDidFinish: speechDidFinish)
            }
        } volumeCallback: { _ in }
    }

    /// Ends listening and keeps what was transcribed so far.
    func stop() {
        end(reason: .stopped)
    }

    private func handleResult(text: String?, error: Error?, speechDidFinish: Bool) {
        guard isListening else { return }
        if let text, text != transcript {
            transcript = text
            onTextChange?(composedText)
        }
        if error != nil, transcript.isEmpty {
            end(reason: .failed)
        } else if speechDidFinish || error != nil {
            end(reason: .speechFinished)
        }
    }

    private func end(reason: EndReason) {
        guard !hasEnded else { return }
        hasEnded = true
        isListening = false
        speechRecognizer.stopRecording()
        onEnd?(composedText, reason)
    }

    /// Joins the dictated words to what was already typed, with a single space between them.
    static func compose(baseText: String, transcript: String) -> String {
        guard !transcript.isEmpty else { return baseText }
        guard let last = baseText.last else { return transcript }
        return last.isWhitespace ? baseText + transcript : baseText + " " + transcript
    }
}
