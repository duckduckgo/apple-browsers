//
//  LlamaModel.swift
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

import CLlama
import Foundation

public typealias LlamaToken = Int32

public struct LlamaChatMessage: Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// A GGUF model loaded into memory. llama.cpp isn't thread-safe for one model, so use a model and
/// its contexts from one thread or serial queue at a time.
public final class LlamaModel: @unchecked Sendable {

    let library: LlamaLibrary
    let pointer: OpaquePointer
    let vocab: OpaquePointer

    private var api: cllama_api { library.api }

    /// Maps the file instead of reading it, so the weights don't count fully against memory, and
    /// puts every layer on the GPU.
    public init(library: LlamaLibrary, fileURL: URL) throws {
        self.library = library
        let api = library.api
        var params = api.llama_model_default_params!()
        params.n_gpu_layers = -1
        params.load_mode = LLAMA_LOAD_MODE_MMAP
        guard let model = api.llama_model_load_from_file!(fileURL.path, params) else {
            throw LlamaRuntimeError.modelLoadFailed
        }
        guard let vocab = api.llama_model_get_vocab!(model) else {
            api.llama_model_free!(model)
            throw LlamaRuntimeError.modelLoadFailed
        }
        self.pointer = model
        self.vocab = vocab
    }

    deinit {
        api.llama_model_free!(pointer)
    }

    /// Formats `messages` with the chat template stored in the model file.
    /// - Parameter addAssistantStart: Ends with the opening of the assistant's turn, ready to generate.
    public func applyChatTemplate(_ messages: [LlamaChatMessage], addAssistantStart: Bool = true) throws -> String {
        let template = api.llama_model_chat_template!(pointer, nil)
        if let template, LlamaChatFormat.isGemma4(template: String(cString: template)) {
            return LlamaChatFormat.gemma4(messages, addAssistantStart: addAssistantStart)
        }
        let cStrings = messages.flatMap { [strdup($0.role), strdup($0.content)] }
        defer { cStrings.forEach { free($0) } }
        guard !cStrings.contains(where: { $0 == nil }) else {
            throw LlamaRuntimeError.templateFailed
        }
        let chat = stride(from: 0, to: cStrings.count, by: 2).map { index in
            llama_chat_message(role: cStrings[index], content: cStrings[index + 1])
        }

        var length = Int32(messages.reduce(0) { $0 + $1.role.utf8.count + $1.content.utf8.count } * 2 + 256)
        for _ in 0..<2 {
            var buffer = [CChar](repeating: 0, count: Int(length))
            let written = chat.withUnsafeBufferPointer { chatPointer in
                api.llama_chat_apply_template!(template, chatPointer.baseAddress, chatPointer.count, addAssistantStart, &buffer, length)
            }
            guard written >= 0 else {
                throw LlamaRuntimeError.templateFailed
            }
            if written <= length {
                guard let prompt = String(bytes: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, encoding: .utf8) else {
                    throw LlamaRuntimeError.templateFailed
                }
                return prompt
            }
            length = written
        }
        throw LlamaRuntimeError.templateFailed
    }

    /// - Parameters:
    ///   - addSpecial: Adds the tokens the model expects at the very start, such as BOS.
    ///   - parseSpecial: Reads control markers like `<|end_of_text|>` as control tokens. Leave it
    ///     off for text from a web page, so the page can't end a turn or start a new one.
    public func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) throws -> [LlamaToken] {
        let byteCount = Int32(text.utf8.count)
        var capacity = byteCount + 8
        for _ in 0..<2 {
            var tokens = [LlamaToken](repeating: 0, count: Int(capacity))
            let count = api.llama_tokenize!(vocab, text, byteCount, &tokens, capacity, addSpecial, parseSpecial)
            if count >= 0 {
                return Array(tokens.prefix(Int(count)))
            }
            capacity = -count
        }
        throw LlamaRuntimeError.tokenizationFailed
    }

    func isEndOfGeneration(_ token: LlamaToken) -> Bool {
        api.llama_vocab_is_eog!(vocab, token)
    }

    var vocabularySize: Int32 {
        api.llama_vocab_n_tokens!(vocab)
    }

    func bytes(of token: LlamaToken) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = api.llama_token_to_piece!(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = api.llama_token_to_piece!(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(count, 0))).map { UInt8(bitPattern: $0) }
    }

    /// - Parameters:
    ///   - size: The context window in tokens, prompt and answer together.
    ///   - batchSize: How many prompt tokens go to the GPU at once. Cancelling waits for the
    ///     current batch, because llama.cpp can't stop a Metal step halfway.
    public func makeContext(size: Int, batchSize: Int = 512) throws -> LlamaContext {
        try LlamaContext(model: self, size: size, batchSize: batchSize)
    }
}

public struct LlamaSampling: Equatable, Sendable {
    /// 1 turns the penalty off. Small models can repeat one line until they run out of tokens;
    /// a mild penalty stops that.
    public let repeatPenalty: Float
    /// How many recent tokens the penalty looks at.
    public let repeatPenaltyWindow: Int32

    public init(repeatPenalty: Float, repeatPenaltyWindow: Int32) {
        self.repeatPenalty = repeatPenalty
        self.repeatPenaltyWindow = repeatPenaltyWindow
    }

    public static let greedy = LlamaSampling(repeatPenalty: 1, repeatPenaltyWindow: 0)
}

/// One conversation's working memory. Each `generate` call starts from an empty context.
public final class LlamaContext: @unchecked Sendable {

    public let size: Int
    private let model: LlamaModel
    private let pointer: OpaquePointer
    private let batchSize: Int

    private var api: cllama_api { model.library.api }

    init(model: LlamaModel, size: Int, batchSize: Int) throws {
        self.model = model
        let api = model.library.api
        var params = api.llama_context_default_params!()
        params.n_ctx = UInt32(size)
        params.n_batch = UInt32(batchSize)
        params.n_ubatch = UInt32(batchSize)
        guard let context = api.llama_init_from_model!(model.pointer, params) else {
            throw LlamaRuntimeError.contextCreationFailed
        }
        self.pointer = context
        self.size = Int(api.llama_n_ctx!(context))
        self.batchSize = Int(api.llama_n_batch!(context))
    }

    deinit {
        api.llama_free!(pointer)
    }

    /// The last position the context's memory holds, or -1 when it holds nothing.
    var lastPositionInMemory: Int32 {
        api.llama_memory_seq_pos_max!(api.llama_get_memory!(pointer), 0)
    }

    /// Reads `prompt`, then writes up to `maxTokens` tokens. Text goes to `onText` as it's written,
    /// never split inside a character.
    /// - Parameter shouldStop: Checked between prompt batches and between tokens. Returning true
    ///   throws `CancellationError`.
    /// - Returns: How many tokens were written.
    @discardableResult
    public func generate(prompt: [LlamaToken],
                         maxTokens: Int,
                         sampling: LlamaSampling,
                         shouldStop: () -> Bool,
                         onText: (String) -> Void) throws -> Int {
        guard !prompt.isEmpty, prompt.count < size else {
            throw LlamaRuntimeError.contextFull
        }
        let memory = api.llama_get_memory!(pointer)
        api.llama_memory_clear!(memory, true)
        // The prompt is page text. Without this it would stay in memory, however the run ended,
        // until the next run or the model unloads.
        defer { api.llama_memory_clear!(memory, true) }

        var promptTokens = prompt
        var start = 0
        while start < promptTokens.count {
            if shouldStop() { throw CancellationError() }
            let length = min(batchSize, promptTokens.count - start)
            try promptTokens.withUnsafeMutableBufferPointer { buffer in
                try decode(api.llama_batch_get_one!(buffer.baseAddress! + start, Int32(length)))
            }
            start += length
        }

        let sampler = makeSampler(sampling)
        defer { api.llama_sampler_free!(sampler) }

        var text = UTF8PieceBuffer()
        var written = 0
        let limit = min(maxTokens, size - prompt.count)
        while written < limit {
            if shouldStop() { throw CancellationError() }
            var token = api.llama_sampler_sample!(sampler, pointer, -1)
            if model.isEndOfGeneration(token) { break }
            written += 1
            let piece = text.append(model.bytes(of: token))
            if !piece.isEmpty { onText(piece) }
            // The batch keeps the token's address until decode reads it, longer than `&token` would last.
            try withUnsafeMutablePointer(to: &token) { tokenPointer in
                try decode(api.llama_batch_get_one!(tokenPointer, 1))
            }
        }
        let rest = text.flush()
        if !rest.isEmpty { onText(rest) }
        return written
    }

    private func makeSampler(_ sampling: LlamaSampling) -> UnsafeMutablePointer<llama_sampler> {
        let chain = api.llama_sampler_chain_init!(api.llama_sampler_chain_default_params!())!
        if sampling.repeatPenalty != 1 {
            api.llama_sampler_chain_add!(chain, api.llama_sampler_init_penalties!(model.vocabularySize,
                                                                                   sampling.repeatPenaltyWindow,
                                                                                   sampling.repeatPenalty,
                                                                                   0,
                                                                                   0))
        }
        api.llama_sampler_chain_add!(chain, api.llama_sampler_init_greedy!())
        return chain
    }

    private func decode(_ batch: llama_batch) throws {
        let result = api.llama_decode!(pointer, batch)
        switch result {
        case 0: return
        // llama.h: 1 means no room was left in the context for the batch.
        case 1: throw LlamaRuntimeError.contextFull
        default: throw LlamaRuntimeError.decodeFailed(result)
        }
    }
}
