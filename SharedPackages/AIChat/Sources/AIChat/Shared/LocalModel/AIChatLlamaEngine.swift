//
//  AIChatLlamaEngine.swift
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
import LlamaRuntime
import os

/// Runs Duck.ai tasks with a downloaded GGUF model through llama.cpp, for devices without Apple Intelligence.
public final class AIChatLlamaEngine: AIChatLocalModelEngine {

    /// A page Duck.ai sends is at most 9,500 characters. With Gemma 4 E2B that's about 2,000 tokens in
    /// English and 7,000 in Chinese, so it fits with the answer. A model with a less efficient tokenizer
    /// gets the page cut.
    public static let contextSize = 8_192

    /// Free memory a load needs on iOS. The weights are mapped from the file and don't count toward
    /// iOS's limit. With this context Gemma 4 E2B peaked at about 500 MB on a Mac, and Granite 4.0 1B at
    /// about 760 MB on an iPhone. The rest leaves the app room to work.
    static let minimumAvailableMemory: UInt64 = 1_000_000_000

    /// The evals that picked Gemma 4 E2B ran with this mild penalty. Without it Gemma didn't loop on the
    /// 39 eval pages, but wrote about 15% more and once padded a summary with unrelated headlines from
    /// the page. Granite 4.0 1B needed it: on plain greedy decoding it repeated one bullet until it ran
    /// out of tokens.
    static let sampling = LlamaSampling(repeatPenalty: 1.1, repeatPenaltyWindow: 256)

    /// Stands in for the page while the chat template is applied, so the page text can be
    /// tokenized on its own, without control tokens.
    static let contentPlaceholder = "\u{E000}DDG-PAGE-CONTENT\u{E000}"

    public let model: AIChatLocalModelInfo

    private let runtime: AIChatLlamaRuntime
    private let modelFileURL: () -> URL?
    private let idleUnloadDelay: TimeInterval
    private let availableMemory: () -> UInt64?
    private let queue = DispatchQueue(label: "com.duckduckgo.aiChat.llamaEngine", qos: .userInitiated)
    private let memoryPressure: DispatchSourceMemoryPressure

    // Only touched on `queue`, which also runs every llama.cpp call, one at a time.
    private var loaded: (fileURL: URL, model: AIChatLlamaLoadedModel)?
    private var idleUnload: DispatchWorkItem?

    /// - Parameters:
    ///   - idleUnloadDelay: How long the model stays in memory after a run.
    ///   - availableMemory: How much more memory the app may use before the system ends it, or nil
    ///     where there's no such limit.
    ///   - modelFileURL: The installed model file, or nil when there is none. Called from `run`.
    public init(model: AIChatLocalModelInfo,
                runtime: AIChatLlamaRuntime,
                idleUnloadDelay: TimeInterval = 300,
                availableMemory: @escaping () -> UInt64? = AIChatLlamaEngine.availableMemory,
                modelFileURL: @escaping () -> URL?) {
        self.model = model
        self.runtime = runtime
        self.idleUnloadDelay = idleUnloadDelay
        self.availableMemory = availableMemory
        self.modelFileURL = modelFileURL
        memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        memoryPressure.setEventHandler { [weak self] in
            self?.unloadNow()
        }
        memoryPressure.resume()
    }

    deinit {
        memoryPressure.cancel()
    }

    public var availability: AIChatLocalModelAvailability {
        runtime.isSupported ? .available : .deviceNotEligible
    }

    /// How much more memory the app may use before iOS ends it. Nil on macOS, which has no such limit.
    public static func availableMemory() -> UInt64? {
#if os(iOS)
        UInt64(os_proc_available_memory())
#else
        nil
#endif
    }

    /// Opens llama.cpp ahead of the first run. The first open on a device compiles llama.cpp's GPU
    /// code, which took 18 s on an iPhone; later opens reuse it.
    public func prepare() {
        queue.async { [runtime] in
            do {
                try runtime.openLibrary()
            } catch {
                Logger.aiChat.error("[LocalModel] Opening llama.cpp failed")
            }
        }
    }

    /// Frees the model's memory once any run in progress ends, for example before the file is deleted.
    public func unloadModel() {
        queue.async { [weak self] in
            self?.unloadNow()
        }
    }

    var isModelLoaded: Bool {
        queue.sync { loaded != nil }
    }

    public func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        let fileURL = modelFileURL()
        return AsyncThrowingStream { continuation in
            let stop = StopFlag()
            continuation.onTermination = { _ in stop.set() }
            queue.async { [self] in
                do {
                    try generate(request, fileURL: fileURL, stop: stop, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Generation

    private func generate(_ request: AIChatLocalRunRequest,
                          fileURL: URL?,
                          stop: StopFlag,
                          continuation: AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.Continuation) throws {
        idleUnload?.cancel()
        defer { scheduleIdleUnload() }
        guard let fileURL else {
            throw AIChatLocalModelEngineError(code: .modelUnavailable)
        }

        do {
            let loadStart = DispatchTime.now()
            let model = try loadedModel(at: fileURL)
            let loadMs = Int((DispatchTime.now().uptimeNanoseconds - loadStart.uptimeNanoseconds) / 1_000_000)
            if stop.isSet { throw CancellationError() }

            let taskPrompt = AIChatLocalModelPrompt.taskPrompt(for: request.task)
            let prompt = try Self.fittedPrompt(for: request, taskPrompt: taskPrompt, model: model)
            let outputTokens = try model.generate(prompt: prompt.tokens,
                                                  maxTokens: taskPrompt.maximumResponseTokens,
                                                  sampling: Self.sampling,
                                                  shouldStop: { stop.isSet },
                                                  onText: { continuation.yield(.text($0)) })
            continuation.yield(.finished(AIChatLocalModelRunSummary(promptTokens: prompt.tokens.count,
                                                                    outputTokens: outputTokens,
                                                                    inputTruncated: prompt.truncated,
                                                                    loadMs: loadMs)))
        } catch let error as LlamaRuntimeError {
            if case .decodeFailed = error {
                // A failed GPU step can leave the context unusable; the next run starts fresh.
                unloadNow()
            }
            let code = Self.errorCode(for: error)
            Logger.aiChat.error("[LocalModel] llama.cpp run failed: \(code.rawValue, privacy: .public)")
            throw AIChatLocalModelEngineError(code: code)
        }
    }

    private func loadedModel(at fileURL: URL) throws -> AIChatLlamaLoadedModel {
        if let loaded, loaded.fileURL == fileURL {
            return loaded.model
        }
        // Free the old model before mapping another, so two never share memory.
        loaded = nil
        if let available = availableMemory(), available < Self.minimumAvailableMemory {
            Logger.aiChat.error("[LocalModel] Not enough memory to load the model")
            throw AIChatLocalModelEngineError(code: .outOfMemory)
        }
        let model = try runtime.loadModel(at: fileURL, contextSize: Self.contextSize)
        loaded = (fileURL, model)
        return model
    }

    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        let unload = DispatchWorkItem { [weak self] in
            self?.unloadNow()
        }
        idleUnload = unload
        queue.asyncAfter(deadline: .now() + idleUnloadDelay, execute: unload)
    }

    private func unloadNow() {
        idleUnload?.cancel()
        idleUnload = nil
        loaded = nil
    }

    // MARK: - Prompt

    struct FittedPrompt: Equatable {
        let tokens: [LlamaToken]
        let truncated: Bool
    }

    /// The templated prompt as tokens, with the page cut to leave room for the answer.
    static func fittedPrompt(for request: AIChatLocalRunRequest,
                             taskPrompt: AIChatLocalModelPrompt.TaskPrompt,
                             model: AIChatLlamaLoadedModel) throws -> FittedPrompt {
        let user = AIChatLocalModelPrompt.prompt(instruction: request.instruction, content: contentPlaceholder, tag: taskPrompt.contentTag)
        let templated = try model.applyChatTemplate([LlamaChatMessage(role: "system", content: taskPrompt.instructions),
                                                     LlamaChatMessage(role: "user", content: user)])
        guard let placeholder = templated.range(of: contentPlaceholder) else {
            throw LlamaRuntimeError.templateFailed
        }
        let head = try model.tokenize(String(templated[..<placeholder.lowerBound]), addSpecial: true, parseSpecial: true)
        let tail = try model.tokenize(String(templated[placeholder.upperBound...]), addSpecial: false, parseSpecial: true)
        // Without special parsing, a "<|end_of_text|>" written on the page stays plain text.
        let content = try model.tokenize(AIChatLocalModelPrompt.removingTags(taskPrompt.contentTag, from: request.content),
                                         addSpecial: false,
                                         parseSpecial: false)

        let budget = model.contextSize - head.count - tail.count - taskPrompt.maximumResponseTokens
        guard budget > 0 else {
            throw LlamaRuntimeError.contextFull
        }
        return FittedPrompt(tokens: head + content.prefix(budget) + tail, truncated: content.count > budget)
    }

    static func errorCode(for error: LlamaRuntimeError) -> AIChatLocalRunChunk.ErrorCode {
        switch error {
        case .unsupportedSystem, .libraryUnavailable, .modelLoadFailed: return .modelUnavailable
        case .contextCreationFailed: return .outOfMemory
        case .contextFull: return .contextExceeded
        case .templateFailed, .tokenizationFailed, .decodeFailed: return .unknown
        }
    }
}

/// Set from the consuming task when it's cancelled, read between llama.cpp steps on the engine's queue.
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
