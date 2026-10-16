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

    public func generate(_ prompt: LocalAIPrompt) -> AsyncThrowingStream<LocalAIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (model, directory) = try await MainActor.run { () throws -> (LocalAIModel, URL) in
                        let model = self.store.selectedModel
                        guard let directory = self.store.directory(for: model) else { throw LocalAIEngineError.modelNotDownloaded }
                        return (model, directory)
                    }
                    let container = try await self.holder.container(for: model, at: directory)
                    let session = ChatSession(
                        container,
                        instructions: prompt.instructions,
                        generateParameters: GenerateParameters(maxTokens: prompt.maxTokens, temperature: 0.3),
                        additionalContext: ["enable_thinking": false]
                    )
                    var info: LocalAIGenerationInfo?
                    for try await generation in session.streamDetails(to: prompt.message, images: [], videos: []) {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(.text(text))
                        case .info(let completion):
                            info = LocalAIGenerationInfo(promptTokens: completion.promptTokenCount,
                                                         generatedTokens: completion.generationTokenCount,
                                                         promptTime: completion.promptTime,
                                                         generateTime: completion.generateTime)
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func unload() {
        Task { await holder.unload() }
    }
}

/// Owns the loaded model so loads and unloads never overlap.
private actor ModelHolder {

    private let cacheLimitBytes: Int
    private var container: ModelContainer?
    private var modelID: String?

    init(cacheLimitBytes: Int) {
        self.cacheLimitBytes = cacheLimitBytes
    }

    func container(for model: LocalAIModel, at directory: URL) async throws -> ModelContainer {
        if let container, modelID == model.id {
            return container
        }
        unload()
        Memory.cacheLimit = cacheLimitBytes
        let configuration = ModelConfiguration(directory: directory, extraEOSTokens: model.extraEOSTokens)
        let loaded = try await LLMModelFactory.shared.loadContainer(from: LocalOnlyDownloader(),
                                                                    using: TransformersTokenizerLoader(),
                                                                    configuration: configuration)
        container = loaded
        modelID = model.id
        return loaded
    }

    func unload() {
        container = nil
        modelID = nil
        Memory.clearCache()
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
