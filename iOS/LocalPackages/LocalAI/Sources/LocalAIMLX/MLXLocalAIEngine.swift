//
//  MLXLocalAIEngine.swift
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
import LocalAI
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs the model selected in `LocalAIModelStore` with MLX, inside our process. Device only: MLX
/// crashes on the iOS Simulator.
public final class MLXLocalAIEngine: LocalAIEngine {

    public let kind = LocalAIEngineKind.mlx

    private let store: LocalAIModelStore
    private let holder: ModelHolder
    private let settings = MLXGenerationSettings()

    /// How many prompt tokens MLX processes per step while reading the input. Larger steps read a page
    /// faster at the cost of a bigger transient buffer; MLX's default is 512.
    public var prefillStepSize: Int {
        get { settings.prefillStepSize }
        set { settings.prefillStepSize = newValue }
    }

    /// MLX keeps freed GPU buffers for reuse; uncapped, that cache grows towards the app's memory limit.
    public init(store: LocalAIModelStore, cacheLimitBytes: Int = 20 * 1024 * 1024) {
        self.store = store
        self.holder = ModelHolder(cacheLimitBytes: cacheLimitBytes)
    }

    @MainActor public var modelName: String { store.selectedModel.id }

    @MainActor public var unavailableReason: String? {
        #if targetEnvironment(simulator)
        return "MLX doesn't run on the simulator. Use a device, or the Stub engine."
        #else
        return store.directory(for: store.selectedModel) == nil ? "\(store.selectedModel.displayName) isn't downloaded." : nil
        #endif
    }

    public func makeConversation(instructions: String) -> LocalAIConversation {
        MLXConversation(store: store, holder: holder, settings: settings, instructions: instructions)
    }

    public func preload() {
        Task { [store, holder] in
            guard let (model, directory) = await MainActor.run(body: { () -> (LocalAIModel, URL)? in
                let model = store.selectedModel
                return store.directory(for: model).map { (model, $0) }
            }) else { return }
            _ = try? await holder.container(for: model, at: directory)
        }
    }

    public func unload() {
        Task { await holder.unload() }
    }
}

/// One `ChatSession` for the whole chat, so follow-ups reuse the history and its cache instead of
/// re-reading the page each turn. Created on the first message, once the model is loaded.
private final class MLXConversation: LocalAIConversation {

    private let store: LocalAIModelStore
    private let holder: ModelHolder
    private let settings: MLXGenerationSettings
    private let instructions: String
    private var session: ChatSession?

    init(store: LocalAIModelStore, holder: ModelHolder, settings: MLXGenerationSettings, instructions: String) {
        self.store = store
        self.holder = holder
        self.settings = settings
        self.instructions = instructions
    }

    /// The last reply's generation. A new message waits for it, so two generations never share the session.
    private var previousReply: Task<Void, Never>?

    /// Stopping never cancels MLX: cancelling while it reads the input (which it can't interrupt) leaves the
    /// session's cache half-written, and the next message then runs on it. Instead the reply is dropped at
    /// the next word, which ends MLX's generation cleanly with the cache intact for follow-ups.
    func send(_ message: String, maxTokens: Int) -> AsyncThrowingStream<LocalAIEvent, Error> {
        let stop = StopFlag()
        let previous = previousReply
        let stream = AsyncThrowingStream<LocalAIEvent, Error> { continuation in
            let reply = Task {
                await previous?.value
                do {
                    if await !self.isReady() {
                        continuation.yield(.status(.loadingModel))
                    }
                    let (session, loadTime) = try await self.chatSession()
                    continuation.yield(.status(.reading(message)))
                    session.generateParameters.maxTokens = maxTokens
                    session.generateParameters.prefillStepSize = self.settings.prefillStepSize
                    var info: LocalAIGenerationInfo?
                    for try await generation in session.streamDetails(to: message, images: [], videos: []) {
                        if stop.isSet { break }
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(.text(text))
                        case .info(let completion):
                            info = LocalAIGenerationInfo(promptTokens: completion.promptTokenCount,
                                                         generatedTokens: completion.generationTokenCount,
                                                         promptTime: completion.promptTime,
                                                         generateTime: completion.generateTime,
                                                         loadTime: loadTime)
                        default:
                            break
                        }
                    }
                    continuation.yield(.finished(info))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.previousReply = reply
            continuation.onTermination = { _ in stop.set() }
        }
        return stream
    }

    private func isReady() async -> Bool {
        guard session == nil else { return true }
        let modelID = await MainActor.run { store.selectedModel.id }
        return await holder.isLoaded(modelID: modelID)
    }

    /// The session, and how long this call waited for the model when it had to load (or finish loading) it.
    private func chatSession() async throws -> (ChatSession, TimeInterval?) {
        if let session {
            return (session, nil)
        }
        let (model, directory) = try await MainActor.run { () throws -> (LocalAIModel, URL) in
            let model = self.store.selectedModel
            guard let directory = self.store.directory(for: model) else { throw LocalAIEngineError.modelNotDownloaded }
            return (model, directory)
        }
        let loadStart = Date()
        let (container, wasLoaded) = try await holder.container(for: model, at: directory)
        let loadTime = wasLoaded ? nil : Date().timeIntervalSince(loadStart)
        let session = ChatSession(container,
                                  instructions: instructions,
                                  generateParameters: GenerateParameters(temperature: 0.3),
                                  additionalContext: ["enable_thinking": false])
        self.session = session
        return (session, loadTime)
    }
}

private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }
}

final class MLXGenerationSettings: @unchecked Sendable {
    var prefillStepSize = 512
}

/// Owns the loaded model. A load in progress is shared, so a preload and the first message don't load twice.
private actor ModelHolder {

    private let cacheLimitBytes: Int
    private var container: ModelContainer?
    private var modelID: String?
    private var loading: (modelID: String, task: Task<ModelContainer, Error>)?

    init(cacheLimitBytes: Int) {
        self.cacheLimitBytes = cacheLimitBytes
    }

    /// The model, loading and warming it up first if needed. `wasLoaded` is true when it was ready already.
    func container(for model: LocalAIModel, at directory: URL) async throws -> (container: ModelContainer, wasLoaded: Bool) {
        if let container, modelID == model.id {
            return (container, true)
        }
        if let loading, loading.modelID == model.id {
            return (try await loading.task.value, false)
        }
        unload()
        Memory.cacheLimit = cacheLimitBytes
        let task = Task { try await Self.loadAndWarmUp(model, at: directory) }
        loading = (model.id, task)
        do {
            let loaded = try await task.value
            if loading?.modelID == model.id {
                container = loaded
                modelID = model.id
                loading = nil
            }
            return (loaded, false)
        } catch {
            if loading?.modelID == model.id { loading = nil }
            throw error
        }
    }

    func isLoaded(modelID: String) -> Bool {
        container != nil && self.modelID == modelID
    }

    func unload() {
        loading?.task.cancel()
        loading = nil
        container = nil
        modelID = nil
        Memory.clearCache()
    }

    /// One throwaway token after loading compiles MLX's GPU kernels, which the first real reply would otherwise pay for.
    private static func loadAndWarmUp(_ model: LocalAIModel, at directory: URL) async throws -> ModelContainer {
        let configuration = ModelConfiguration(directory: directory, extraEOSTokens: model.extraEOSTokens)
        let container = try await LLMModelFactory.shared.loadContainer(from: LocalOnlyDownloader(),
                                                                       using: TransformersTokenizerLoader(),
                                                                       configuration: configuration)
        let warmUp = ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1),
                                 additionalContext: ["enable_thinking": false])
        for try await _ in warmUp.streamDetails(to: "Hi", images: [], videos: []) {}
        return container
    }
}

/// Models are fetched by `LocalAIModelStore`; MLX only ever reads a local directory.
private struct LocalOnlyDownloader: MLXLMCommon.Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw LocalAIEngineError.modelNotDownloaded
    }
}

/// Bridges swift-transformers' tokenizer to MLX's protocol. Same as `#huggingFaceTokenizerLoader()`,
/// written out so we don't link `MLXHuggingFace` and its macros.
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
