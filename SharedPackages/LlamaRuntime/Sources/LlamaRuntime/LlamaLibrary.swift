//
//  LlamaLibrary.swift
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
import DDGError
import Foundation
import os.log

public enum LlamaRuntimeError: DDGError, Sendable {
    /// llama.cpp can't run here: an Intel Mac, Rosetta, or an OS older than its build supports.
    case unsupportedSystem
    case libraryUnavailable(String)
    case modelLoadFailed
    case contextCreationFailed
    case templateFailed
    case tokenizationFailed
    /// The prompt doesn't leave room in the context window.
    case contextFull
    /// llama.cpp's own result code.
    case decodeFailed(Int32)

    public static let errorDomain = "com.duckduckgo.llamaRuntime"

    public var errorCode: Int {
        switch self {
        case .unsupportedSystem: return 1
        case .libraryUnavailable: return 2
        case .modelLoadFailed: return 3
        case .contextCreationFailed: return 4
        case .templateFailed: return 5
        case .tokenizationFailed: return 6
        case .contextFull: return 7
        case .decodeFailed: return 8
        }
    }

    /// Paths can appear in `libraryUnavailable`'s message, so it's left out.
    public var description: String {
        switch self {
        case .unsupportedSystem: return "LlamaRuntimeError.unsupportedSystem"
        case .libraryUnavailable: return "LlamaRuntimeError.libraryUnavailable"
        case .modelLoadFailed: return "LlamaRuntimeError.modelLoadFailed"
        case .contextCreationFailed: return "LlamaRuntimeError.contextCreationFailed"
        case .templateFailed: return "LlamaRuntimeError.templateFailed"
        case .tokenizationFailed: return "LlamaRuntimeError.tokenizationFailed"
        case .contextFull: return "LlamaRuntimeError.contextFull"
        case .decodeFailed(let code): return "LlamaRuntimeError.decodeFailed(\(code))"
        }
    }
}

/// llama.cpp, opened at runtime rather than linked, so systems it can't run on never load it.
/// The library stays open for the life of the process.
///
/// Temporary, for the internal release and evals: opening a prebuilt framework at runtime will be
/// refactored before an external release.
public final class LlamaLibrary: @unchecked Sendable {

    /// Filled by `cllama_load`, so every function is set. Immutable after that.
    let api: cllama_api

    private init(api: cllama_api) {
        self.api = api
    }

    /// Where the app's build step puts the framework.
    public static var bundledLibraryURL: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("llama.framework/llama")
    }

    /// The official llama.cpp build targets macOS 13.3 and iOS 16.4. Intel Macs are left out on
    /// purpose: llama.cpp's Metal code is built for Apple silicon, and on the CPU a summary is too slow.
    public static var isSupportedSystem: Bool {
#if arch(arm64)
        if #available(macOS 13.3, iOS 16.4, *) {
            return true
        }
#endif
        return false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded: [String: Result<LlamaLibrary, LlamaRuntimeError>] = [:]

    /// Opens the library once per path. Later calls return the same result, including a failure:
    /// the library ships with the app, so it can't appear later.
    public static func load(at url: URL, isSupportedSystem: Bool = LlamaLibrary.isSupportedSystem) throws -> LlamaLibrary {
        guard isSupportedSystem else {
            throw LlamaRuntimeError.unsupportedSystem
        }
        lock.lock()
        defer { lock.unlock() }
        if let result = loaded[url.path] {
            return try result.get()
        }

        var api = cllama_api()
        let result: Result<LlamaLibrary, LlamaRuntimeError>
        if let failure = cllama_load(url.path, &api) {
            let message = String(cString: failure)
            Logger.llamaRuntime.error("Loading llama.cpp failed: \(message, privacy: .private)")
            result = .failure(.libraryUnavailable(message))
        } else {
            api.llama_log_set!(logCallback, nil)
            api.llama_backend_init!()
            result = .success(LlamaLibrary(api: api))
        }
        loaded[url.path] = result
        return try result.get()
    }
}

/// Passes on llama.cpp's warnings and errors. They can include the model's path, so they stay private.
private let logCallback: ggml_log_callback = { level, text, _ in
    guard level == GGML_LOG_LEVEL_ERROR || level == GGML_LOG_LEVEL_WARN, let text else { return }
    let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    Logger.llamaRuntime.log("llama.cpp: \(message, privacy: .private)")
}

extension Logger {
    static let llamaRuntime = Logger(subsystem: "com.duckduckgo.llamaRuntime", category: "LlamaRuntime")
}
