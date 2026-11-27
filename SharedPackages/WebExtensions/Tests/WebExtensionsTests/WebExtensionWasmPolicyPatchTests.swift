//
//  WebExtensionWasmPolicyPatchTests.swift
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

import Testing
@testable import WebExtensions

@Suite("WebAssembly policy patch")
struct WebExtensionWasmPolicyPatchTests {

    /// The patched policy's directives by name, so assertions don't depend on their order.
    private func patchedDirectives(_ policy: String) throws -> [String: String] {
        let patched = try #require(WebExtensionWasmPolicyPatch.patchedPolicy(policy))
        return Dictionary(uniqueKeysWithValues: patched.split(separator: ";").map { entry in
            let tokens = entry.split(separator: " ")
            return (String(tokens[0]), tokens.dropFirst().joined(separator: " "))
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("A policy that doesn't ask for WebAssembly is left alone", .timeLimit(.minutes(1)),
          arguments: [
            "script-src 'self'; object-src 'self'",
            "object-src 'self'",
            "script-src 'self'; script-src 'self' 'wasm-unsafe-eval'"
          ])
    func policyWithoutWasm(policy: String) {
        #expect(WebExtensionWasmPolicyPatch.patchedPolicy(policy) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("script-src moves to the directives that fell back to it", .timeLimit(.minutes(1)))
    func scriptSrcIsReplaced() throws {
        let directives = try patchedDirectives("script-src 'self' 'wasm-unsafe-eval'; object-src 'self'")

        #expect(directives == [
            "object-src": "'self'",
            "script-src-elem": "'self'",
            "script-src-attr": "'self'",
            "worker-src": "'self'"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("default-src moves to the directives that fell back to it", .timeLimit(.minutes(1)))
    func defaultSrcIsReplaced() throws {
        let policy = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src https://example.com"
        let directives = try patchedDirectives(policy)

        #expect(directives["default-src"] == nil)
        #expect(directives["script-src"] == nil)
        #expect(directives["connect-src"] == "https://example.com")
        #expect(directives["worker-src"] == "'self'")
        let inheritedFromDefaultSrc = ["child-src", "frame-src", "font-src", "img-src",
                                       "manifest-src", "media-src", "object-src", "style-src"]
        for name in inheritedFromDefaultSrc {
            #expect(directives[name] == "'none'", "\(name)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("WebAssembly can be asked for in default-src", .timeLimit(.minutes(1)))
    func wasmInDefaultSrc() throws {
        let directives = try patchedDirectives("default-src 'self' 'wasm-unsafe-eval'")

        #expect(directives["default-src"] == nil)
        #expect(directives["script-src-elem"] == "'self'")
        #expect(directives["img-src"] == "'self'")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only the sources WebKit honored in script-src are carried over", .timeLimit(.minutes(1)))
    func restrictedSourcesAreDropped() throws {
        let policy = "script-src 'self' https://cdn.example.com 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'"
        let directives = try patchedDirectives(policy)

        #expect(directives["script-src-elem"] == "'self'")
        #expect(directives["script-src-attr"] == "'self'")
        #expect(directives["worker-src"] == "'self'")
    }

    @available(iOS 16, macOS 13, *)
    @Test("worker-src and frame-src keep falling back to child-src", .timeLimit(.minutes(1)))
    func childSrcIsInherited() throws {
        let directives = try patchedDirectives("script-src 'self' 'wasm-unsafe-eval'; child-src blob:")

        #expect(directives == [
            "child-src": "blob:",
            "script-src-elem": "'self'",
            "script-src-attr": "'self'"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keywords match regardless of case", .timeLimit(.minutes(1)))
    func keywordCase() throws {
        let directives = try patchedDirectives("SCRIPT-SRC 'SELF' 'WASM-UNSAFE-EVAL'")

        #expect(directives["script-src-elem"] == "'self'")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A patched policy is not patched again", .timeLimit(.minutes(1)))
    func patchingTwice() throws {
        let policy = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'"
        let patched = try #require(WebExtensionWasmPolicyPatch.patchedPolicy(policy))

        #expect(WebExtensionWasmPolicyPatch.patchedPolicy(patched) == nil)
    }
}
