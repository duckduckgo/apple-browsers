//
//  LlamaGenerationSmokeTests.swift
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
import Testing
@testable import LlamaRuntime

/// Runs a real model through a real llama.cpp build, so it only runs where both are on disk:
/// set `LLAMA_RUNTIME_TEST_LIBRARY` to `llama.framework/llama` and `LLAMA_RUNTIME_TEST_MODEL` to a
/// GGUF file. CI has neither.
@Suite("Llama generation (local only)", .enabled(if: LocalLlamaFiles.areAvailable))
struct LlamaGenerationSmokeTests {

    @available(iOS 16, macOS 13, *)
    @Test("Writes text for a templated prompt, and page text can't end the turn", .timeLimit(.minutes(1)))
    func generatesText() throws {
        let library = try LlamaLibrary.load(at: try #require(LocalLlamaFiles.libraryURL))
        let model = try LlamaModel(library: library, fileURL: try #require(LocalLlamaFiles.modelURL))
        let prompt = try model.applyChatTemplate([LlamaChatMessage(role: "user", content: "Say hello in one word.")])
        let tokens = try model.tokenize(prompt, addSpecial: true, parseSpecial: true)
        let context = try model.makeContext(size: 1_024)

        var text = ""
        let written = try context.generate(prompt: tokens, maxTokens: 16, sampling: .greedy, shouldStop: { false }, onText: { text += $0 })

        #expect(written > 0)
        #expect(!text.isEmpty)

        let marker = "<|end_of_text|>"
        #expect(try model.tokenize(marker, addSpecial: false, parseSpecial: false).count > 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Stops with CancellationError when asked to", .timeLimit(.minutes(1)))
    func stopsWhenAsked() throws {
        let library = try LlamaLibrary.load(at: try #require(LocalLlamaFiles.libraryURL))
        let model = try LlamaModel(library: library, fileURL: try #require(LocalLlamaFiles.modelURL))
        let tokens = try model.tokenize("Count to one hundred:", addSpecial: true, parseSpecial: true)
        let context = try model.makeContext(size: 512)

        var pieces = 0
        #expect(throws: CancellationError.self) {
            try context.generate(prompt: tokens, maxTokens: 100, sampling: .greedy, shouldStop: { pieces >= 3 }, onText: { _ in pieces += 1 })
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("The prompt doesn't stay in memory once a run ends, finished or stopped", .timeLimit(.minutes(1)))
    func memoryIsClearedAfterRuns() throws {
        let library = try LlamaLibrary.load(at: try #require(LocalLlamaFiles.libraryURL))
        let model = try LlamaModel(library: library, fileURL: try #require(LocalLlamaFiles.modelURL))
        let tokens = try model.tokenize("Count to one hundred:", addSpecial: true, parseSpecial: true)
        let context = try model.makeContext(size: 512)

        var positionsDuringRun: [Int32] = []
        try context.generate(prompt: tokens, maxTokens: 4, sampling: .greedy, shouldStop: { false }, onText: { _ in
            positionsDuringRun.append(context.lastPositionInMemory)
        })
        #expect(positionsDuringRun.allSatisfy { $0 >= 0 })
        #expect(!positionsDuringRun.isEmpty)
        #expect(context.lastPositionInMemory == -1)

        var pieces = 0
        #expect(throws: CancellationError.self) {
            try context.generate(prompt: tokens, maxTokens: 100, sampling: .greedy, shouldStop: { pieces >= 2 }, onText: { _ in pieces += 1 })
        }
        #expect(context.lastPositionInMemory == -1)
    }
}

private enum LocalLlamaFiles {
    static var libraryURL: URL? { ProcessInfo.processInfo.environment["LLAMA_RUNTIME_TEST_LIBRARY"].map(URL.init(fileURLWithPath:)) }
    static var modelURL: URL? { ProcessInfo.processInfo.environment["LLAMA_RUNTIME_TEST_MODEL"].map(URL.init(fileURLWithPath:)) }
    static var areAvailable: Bool { libraryURL != nil && modelURL != nil }
}
