//
//  AIChatLlamaRuntime.swift
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

/// What `AIChatLlamaEngine` needs from llama.cpp, so the engine can be tested without it.
public protocol AIChatLlamaRuntime: AnyObject {
    /// llama.cpp can run on this device and ships with the app.
    var isSupported: Bool { get }
    /// Throws `LlamaRuntimeError`.
    func loadModel(at fileURL: URL, contextSize: Int) throws -> AIChatLlamaLoadedModel
}

/// A model and its context, used from one queue at a time. Throws `LlamaRuntimeError`.
public protocol AIChatLlamaLoadedModel: AnyObject {
    var contextSize: Int { get }
    func applyChatTemplate(_ messages: [LlamaChatMessage]) throws -> String
    func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) throws -> [LlamaToken]
    func generate(prompt: [LlamaToken],
                  maxTokens: Int,
                  sampling: LlamaSampling,
                  shouldStop: () -> Bool,
                  onText: (String) -> Void) throws -> Int
}

/// llama.cpp from the framework the app's build step bundles.
public final class BundledLlamaRuntime: AIChatLlamaRuntime {

    private let libraryURL: URL?

    public init(libraryURL: URL? = LlamaLibrary.bundledLibraryURL) {
        self.libraryURL = libraryURL
    }

    public var isSupported: Bool {
        guard LlamaLibrary.isSupportedSystem, let libraryURL else { return false }
        return FileManager.default.fileExists(atPath: libraryURL.path)
    }

    public func loadModel(at fileURL: URL, contextSize: Int) throws -> AIChatLlamaLoadedModel {
        guard let libraryURL else {
            throw LlamaRuntimeError.libraryUnavailable("The app has no bundled llama.cpp")
        }
        let model = try LlamaModel(library: LlamaLibrary.load(at: libraryURL), fileURL: fileURL)
        return LoadedLlamaModel(model: model, context: try model.makeContext(size: contextSize))
    }
}

private final class LoadedLlamaModel: AIChatLlamaLoadedModel {

    private let model: LlamaModel
    private let context: LlamaContext

    init(model: LlamaModel, context: LlamaContext) {
        self.model = model
        self.context = context
    }

    var contextSize: Int { context.size }

    func applyChatTemplate(_ messages: [LlamaChatMessage]) throws -> String {
        try model.applyChatTemplate(messages)
    }

    func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) throws -> [LlamaToken] {
        try model.tokenize(text, addSpecial: addSpecial, parseSpecial: parseSpecial)
    }

    func generate(prompt: [LlamaToken], maxTokens: Int, sampling: LlamaSampling, shouldStop: () -> Bool, onText: (String) -> Void) throws -> Int {
        try context.generate(prompt: prompt, maxTokens: maxTokens, sampling: sampling, shouldStop: shouldStop, onText: onText)
    }
}
