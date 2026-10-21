//
//  LocalAIResultViewController.swift
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

import LocalAI
import SwiftUI
import UIKit

/// PoC: an on-device chat inside the contextual sheet, laid out like Duck.ai's.
final class LocalAIResultViewController: UIHostingController<LocalAIConversationView> {

    private let model: LocalAIChatViewModel

    /// `prompt` is the suggestion's text as Duck.ai would show it, e.g. "Translate this page into English."
    init(prompt: String, request: LocalAIRequest, engine: LocalAIEngine, onContinueInDuckAI: @escaping () -> Void) {
        model = LocalAIChatViewModel(firstPrompt: prompt, request: request, engine: engine)
        super.init(rootView: LocalAIConversationView(model: model, onContinueInDuckAI: onContinueInDuckAI))
        view.backgroundColor = LocalAIChatPalette.background
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.start()
    }

    func stop() {
        model.stop()
    }
}

struct LocalAIChatTurn: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    var reply = ""
    var isStreaming = true
    /// What the engine is doing before the first words, and since when.
    var status: LocalAIStatus?
    var statusSince = Date()
    var error: String?
    var stats: String?
}

/// One on-device conversation. The first turn sends the suggestion with the page or selection; follow-ups
/// go to the same engine conversation, so the model still has the page.
@MainActor
final class LocalAIChatViewModel: ObservableObject {

    @Published private(set) var turns: [LocalAIChatTurn] = []
    @Published var draft = ""

    var isRunning: Bool { turns.last?.isStreaming == true }
    var canSend: Bool { !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var modelName: String { engine.modelName }

    private let firstPrompt: String
    private let request: LocalAIRequest
    private let engine: LocalAIEngine
    private let conversation: LocalAIConversation
    private var task: Task<Void, Never>?
    /// Set when the first answer was a translation sent in pieces, which the conversation never saw.
    private var followUpNeedsContext = false

    static let followUpMaxTokens = 1_024
    /// Prompt tokens read per second, from the last reply that reported it; drives the progress bar.
    private(set) static var readTokensPerSecond: Double = 400

    init(firstPrompt: String, request: LocalAIRequest, engine: LocalAIEngine) {
        self.firstPrompt = firstPrompt
        self.request = request
        self.engine = engine
        let prompt = LocalAIPromptBuilder.prompt(for: request)
        conversation = engine.makeConversation(instructions: prompt.instructions)
    }

    func start() {
        guard turns.isEmpty else { return }
        if LocalAIPromptBuilder.prompts(for: request).count > 1 {
            followUpNeedsContext = true
            translateInPieces()
            return
        }
        let prompt = LocalAIPromptBuilder.prompt(for: request)
        send(shown: firstPrompt, message: prompt.message, maxTokens: prompt.maxTokens)
    }

    func sendDraft() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        let message = followUpNeedsContext ? LocalAIPromptBuilder.followUpContext(for: request) + text : text
        followUpNeedsContext = false
        send(shown: text, message: message, maxTokens: Self.followUpMaxTokens)
    }

    func stop() {
        task?.cancel()
    }

    deinit {
        task?.cancel()
    }

    private func send(shown: String, message: String, maxTokens: Int) {
        turns.append(LocalAIChatTurn(prompt: shown))
        let index = turns.count - 1
        let events = conversation.send(message, maxTokens: maxTokens)
        task = Task { [weak self] in
            guard let self else { return }
            let (record, error) = await LocalAIRunner.measure(events, request: self.request, engine: self.engine,
                                                              onStatus: { [weak self] in self?.setStatus($0, at: index) }) { [weak self] chunk in
                self?.append(chunk, at: index)
            }
            self.finish(at: index, record: record, error: error)
        }
    }

    private func translateInPieces() {
        turns.append(LocalAIChatTurn(prompt: firstPrompt))
        task = Task { [weak self] in
            guard let self else { return }
            let (record, error) = await LocalAIRunner.runAsShown(self.request, engine: self.engine,
                                                                 onStatus: { [weak self] in self?.setStatus($0, at: 0) }) { [weak self] chunk in
                self?.append(chunk, at: 0)
            }
            self.finish(at: 0, record: record, error: error)
        }
    }

    private func setStatus(_ status: LocalAIStatus, at index: Int) {
        guard turns[index].reply.isEmpty else { return }
        turns[index].status = status
        turns[index].statusSince = Date()
    }

    private func append(_ chunk: String, at index: Int) {
        turns[index].status = nil
        turns[index].reply += chunk
    }

    private func finish(at index: Int, record: LocalAIRunRecord, error: Error?) {
        turns[index].status = nil
        turns[index].isStreaming = false
        turns[index].error = error?.localizedDescription
        turns[index].stats = Self.describe(record)
        if let tokens = record.promptTokens, let seconds = record.promptTime, seconds > 0, tokens > 50 {
            Self.readTokensPerSecond = Double(tokens) / seconds
        }
    }

    private static func describe(_ record: LocalAIRunRecord) -> String {
        var parts = ["On device"]
        if let load = record.loadTime {
            parts.append(String(format: "load %.1fs", load))
        }
        if let prompt = record.promptTime, let tokens = record.promptTokens {
            parts.append(String(format: "read %d tokens in %.1fs", tokens, prompt))
        }
        if let firstToken = record.timeToFirstToken {
            parts.append(String(format: "first word %.1fs", firstToken))
        }
        if let rate = record.tokensPerSecond {
            parts.append(String(format: "%.0f tok/s", rate))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: record.peakFootprintBytes, countStyle: .memory) + " peak")
        return parts.joined(separator: " · ")
    }
}
