//
//  PageTranslationBridge.swift
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
import UserScript
import WebKit
import WebPageTranslation

/// Talks to C-S-S's `pageTranslation` bundle in the isolated world. The bundle answers each push
/// with a separate notification that carries no request id, so only one request is in flight, and
/// once a reply may still arrive late (timeout, cancel) the bridge asks nothing more of that document.
final class PageTranslationBridge: NSObject, Subfeature {

    enum Error: Swift.Error {
        case timeout
        /// A request is already waiting for its reply.
        case busy
        /// A reply may still arrive for an abandoned request, so this document gets no more requests.
        case ended
    }

    private enum Reply: String {
        case extractResult
        case applyResult
    }

    private struct ExtractResult: Decodable {
        let units: [PageTranslationUnit]
    }

    private struct ApplyResult: Decodable {
        let count: Int
    }

    private struct ApplyParams: Encodable {
        let sourceLanguage: String
        let targetLanguage: String
        let updates: [PageTranslationUpdate]
    }

    let featureName = "pageTranslation"
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?

    private let timeout: TimeInterval
    private let customPush: ((String, Encodable) -> Void)?

    @MainActor private var pending: (reply: Reply, continuation: CheckedContinuation<Any, Swift.Error>)?
    @MainActor private var timeoutTask: Task<Void, Never>?
    @MainActor private var isEnded = false

    /// - Parameter push: sends a message to the bundle; the broker's push into `webView` when `nil`.
    init(timeout: TimeInterval = 30, push: ((String, Encodable) -> Void)? = nil) {
        self.timeout = timeout
        self.customPush = push
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let reply = Reply(rawValue: methodName) else { return nil }
        return { [weak self] params, _ in
            await self?.receive(reply, params: params)
            return nil
        }
    }

    @MainActor
    func extract() async throws -> [PageTranslationUnit] {
        let params = try await request("extract", params: [String: String](), reply: .extractResult)
        return try Self.decode(ExtractResult.self, from: params).units
    }

    @MainActor
    func apply(_ updates: [PageTranslationUpdate], from source: String, to target: String) async throws -> Int {
        let params = try await request("apply",
                                       params: ApplyParams(sourceLanguage: source, targetLanguage: target, updates: updates),
                                       reply: .applyResult)
        return try Self.decode(ApplyResult.self, from: params).count
    }

    /// Fails the pending request with `CancellationError`. Its reply may still come, so the bridge ends.
    @MainActor
    func cancelPending() {
        guard pending != nil else { return }
        finish(.failure(CancellationError()), ending: true)
    }

    /// A new document has no late replies to wait for.
    @MainActor
    func documentDidChange() {
        finish(.failure(CancellationError()), ending: false)
        isEnded = false
    }

    @MainActor
    private func request(_ method: String, params: Encodable, reply: Reply) async throws -> Any {
        guard !isEnded else { throw Error.ended }
        guard pending == nil else { throw Error.busy }

        return try await withCheckedThrowingContinuation { continuation in
            pending = (reply, continuation)
            let timeout = timeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(Error.timeout), ending: true)
            }
            push(method, params)
        }
    }

    @MainActor
    private func push(_ method: String, _ params: Encodable) {
        if let customPush {
            customPush(method, params)
        } else if let webView {
            broker?.push(method: method, params: params, for: self, into: webView)
        }
    }

    @MainActor
    private func receive(_ reply: Reply, params: Any) {
        // A reply to a request that isn't pending is late or forged.
        guard pending?.reply == reply else { return }
        finish(.success(params), ending: false)
    }

    @MainActor
    private func finish(_ result: Result<Any, Swift.Error>, ending: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if ending {
            isEnded = true
        }
        let continuation = pending?.continuation
        pending = nil
        continuation?.resume(with: result)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from params: Any) throws -> T {
        // Serializing anything else raises an Objective-C exception, which crashes instead of throwing.
        guard JSONSerialization.isValidJSONObject(params) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Reply params aren't a JSON object"))
        }
        let data = try JSONSerialization.data(withJSONObject: params)
        return try JSONDecoder().decode(type, from: data)
    }
}
