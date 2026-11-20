//
//  LlamaLibraryTests.swift
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

@Suite("LlamaLibrary")
struct LlamaLibraryTests {

    @available(iOS 16, macOS 13, *)
    @Test("An unsupported system never opens the library", .timeLimit(.minutes(1)))
    func unsupportedSystemNeverOpensTheLibrary() {
        #expect(throws: LlamaRuntimeError.unsupportedSystem) {
            try LlamaLibrary.load(at: URL(fileURLWithPath: "/usr/lib/libz.1.dylib"), isSupportedSystem: false)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A missing library reports it's unavailable", .timeLimit(.minutes(1)))
    func missingLibraryIsUnavailable() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)/llama")
        let error = try #require(throws: LlamaRuntimeError.self) {
            try LlamaLibrary.load(at: url, isSupportedSystem: true)
        }
        guard case .libraryUnavailable(let message) = error else {
            Issue.record("Expected libraryUnavailable, got \(error)")
            return
        }
        #expect(message.hasPrefix("dlopen failed"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A library without llama.cpp's functions reports which one is missing", .timeLimit(.minutes(1)))
    func libraryWithoutLlamaFunctionsNamesTheMissingSymbol() {
        #expect(throws: LlamaRuntimeError.libraryUnavailable("missing symbol: llama_backend_init")) {
            try LlamaLibrary.load(at: URL(fileURLWithPath: "/usr/lib/libz.1.dylib"), isSupportedSystem: true)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed load is remembered rather than retried", .timeLimit(.minutes(1)))
    func failedLoadIsRemembered() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)/llama")
        let first = Result { try LlamaLibrary.load(at: url, isSupportedSystem: true) }
        let second = Result { try LlamaLibrary.load(at: url, isSupportedSystem: true) }
        #expect(throws: LlamaRuntimeError.self) { try first.get() }
        #expect((first.error as? LlamaRuntimeError) == (second.error as? LlamaRuntimeError))
    }
}

private extension Result {
    var error: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
