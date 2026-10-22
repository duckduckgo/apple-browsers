//
//  MLXProvider.swift
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

import DuckAIChatCore
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

public final class MLXProvider: ChatProvider, Sendable {
    public let descriptor: ProviderDescriptor
    private let model: Model
    private let store: ModelStore
    private let worker = ModelWorker()

    public init(model: Model = ModelCatalog.recommended(physicalMemory: ProcessInfo.processInfo.physicalMemory), store: ModelStore) {
        self.model = model
        self.store = store
        descriptor = ProviderDescriptor(id: ProviderID(rawValue: model.id), displayName: "MLX",
                                        modelName: model.displayName, supportsReasoning: false,
                                        supportsImages: false, contextWindowTokens: model.contextWindowTokens)
    }

    public var availability: ProviderAvailability {
        #if targetEnvironment(simulator)
        return .unsupported(reason: "MLX requires a device.")
        #else
        return store.availability(for: model)
        #endif
    }

    public func availabilityUpdates() -> AsyncStream<ProviderAvailability> {
        #if targetEnvironment(simulator)
        return AsyncStream { _ in }
        #else
        return store.availabilityUpdates(for: model)
        #endif
    }

    public func download() async throws {
        try await store.download(model)
    }

    public func prepare() async {
        guard availability == .ready, let directory = store.directory(for: model) else { return }
        _ = try? await worker.load(model, at: directory)
    }

    public func unload() {
        Task { await worker.unload() }
    }

    public func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await worker.acquire()
                do {
                    guard !stop.isRaised else {
                        continuation.finish()
                        await worker.release()
                        return
                    }
                    #if targetEnvironment(simulator)
                    throw ChatError.modelUnavailable(reason: "MLX requires a device.")
                    #else
                    guard let directory = store.directory(for: model) else { throw ChatError.modelNotDownloaded }
                    let started = ContinuousClock.now
                    let wasLoaded = await worker.isLoaded
                    if !wasLoaded { continuation.yield(.stage(.loadingModel(fraction: nil))) }
                    let container = try await worker.load(model, at: directory)
                    let loadTime = wasLoaded ? Duration.zero : started.duration(to: .now)
                    guard !stop.isRaised else {
                        continuation.finish()
                        await worker.release()
                        return
                    }
                    continuation.yield(.stage(.readingInput(estimatedTokens: turn.estimatedInputTokens, fraction: nil)))
                    let stats = try await Self.generate(container: container, turn: turn, stop: stop,
                                                        continuation: continuation, loadTime: loadTime)
                    continuation.yield(.finished(stats))
                    continuation.finish()
                    #endif
                } catch {
                    let mapped = (error as? ChatError) ?? .unknown(error.localizedDescription)
                    continuation.finish(throwing: mapped)
                }
                await worker.release()
            }
            // A consumer disappearing must also drain prefill before stopping MLX.
            continuation.onTermination = { _ in stop.raise() }
        }
    }

    private static func generate(container: ModelContainer, turn: ProviderTurn, stop: StopSignal,
                                 continuation: AsyncThrowingStream<ProviderEvent, Error>.Continuation,
                                 loadTime: Duration?) async throws -> GenerationStats {
        try await container.perform { context in
            let history: [Chat.Message] = turn.history.map {
                $0.role == .user ? .user($0.text) : .assistant($0.text)
            }
            let messages = [Chat.Message.system(turn.instructions)] + history + [.user(turn.input)]
            let input = try await context.processor.prepare(input: UserInput(chat: messages, additionalContext: ["enable_thinking": false]))
            let parameters = GenerateParameters(maxTokens: turn.maxOutputTokens, temperature: 0.3)
            let iterator = try TokenIterator(input: input, model: context.model, parameters: parameters)
            let (stream, task) = generateTask(promptTokenCount: input.text.tokens.size,
                                              modelConfiguration: context.configuration,
                                              tokenizer: context.tokenizer, iterator: iterator)
            var info: GenerateCompletionInfo?
            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    // The first chunk proves prefill has ended; cancellation is safe from here.
                    if stop.isRaised { task.cancel() } else { continuation.yield(.textDelta(text)) }
                case .info(let completion): info = completion
                default: break
                }
            }
            await task.value
            return GenerationStats(promptTokens: info?.promptTokenCount, generatedTokens: info?.generationTokenCount ?? 0,
                                   loadTime: loadTime, promptTime: info.map { .seconds($0.promptTime) },
                                   generateTime: info.map { .seconds($0.generateTime) })
        }
    }
}

private actor ModelWorker {
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var unloadRequested = false

    var isLoaded: Bool { container != nil }

    func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    func release() {
        busy = false
        if unloadRequested { unload() }
        if !waiters.isEmpty {
            busy = true
            waiters.removeFirst().resume()
        }
    }

    func load(_ model: Model, at directory: URL) async throws -> ModelContainer {
        if let container { return container }
        if let loading { return try await loading.value }
        MLX.Memory.cacheLimit = 20 * 1024 * 1024
        let task = Task {
            let configuration = ModelConfiguration(directory: directory, extraEOSTokens: model.extraEOSTokens)
            let container = try await LLMModelFactory.shared.loadContainer(from: LocalOnlyDownloader(),
                                                                           using: TransformersTokenizerLoader(),
                                                                           configuration: configuration)
            let warmUp = MLXLMCommon.ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1),
                                                 additionalContext: ["enable_thinking": false])
            for try await _ in warmUp.streamDetails(to: "Hi", images: [], videos: []) {}
            return container
        }
        loading = task
        do {
            let loaded = try await task.value
            container = loaded
            loading = nil
            if unloadRequested && !busy { unload() }
            return loaded
        } catch {
            loading = nil
            if unloadRequested && !busy { unload() }
            throw error
        }
    }

    func unload() {
        guard !busy && loading == nil else {
            unloadRequested = true
            return
        }
        container = nil
        unloadRequested = false
        MLX.Memory.clearCache()
    }
}

private struct LocalOnlyDownloader: MLXLMCommon.Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw ChatError.modelNotDownloaded
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
