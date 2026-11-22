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

import Common
import DDGError
import Foundation
import UserScript
import WebKit
import WebPageTranslation

/// Talks to C-S-S's `pageTranslation` bundle in the isolated world, injecting it once per document.
/// The bundle answers each push with a separate notification that carries no request id, so only one
/// request is in flight, and once a reply may still arrive late (timeout, cancel) the bridge asks
/// nothing more of that document.
final class PageTranslationBridge: NSObject, Subfeature {

    enum Error: DDGError {
        case timeout
        /// A request is already waiting for its reply.
        case busy
        /// A reply may still arrive for an abandoned request, so this document gets no more requests.
        case ended
        /// The bundle's reply didn't have the expected shape.
        case malformedReply

        static var errorDomain: String { "com.duckduckgo.pageTranslationBridge" }

        var errorCode: Int {
            switch self {
            case .timeout: return 1
            case .busy: return 2
            case .ended: return 3
            case .malformedReply: return 4
            }
        }

        var description: String {
            switch self {
            case .timeout: return "The page translation script didn't reply in time"
            case .busy: return "A page translation request is already in progress"
            case .ended: return "The page translation script may still reply to an abandoned request"
            case .malformedReply: return "The page translation script's reply didn't have the expected shape"
            }
        }
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
    private let inject: @MainActor () async throws -> Void
    private let customPush: ((String, Encodable) -> Void)?

    @MainActor private var isRequesting = false
    @MainActor private var pending: (reply: Reply, continuation: CheckedContinuation<Any, Swift.Error>)?
    @MainActor private var timeoutTask: Task<Void, Never>?
    @MainActor private var isEnded = false
    @MainActor private var isInjected = false
    /// Changes with every document, so a request can tell the page changed while it was injecting.
    @MainActor private var document = 0

    /// - Parameters:
    ///   - inject: puts the bundle into the current document.
    ///   - push: sends a message to the bundle; the broker's push into `webView` when `nil`.
    init(timeout: TimeInterval = 30,
         inject: @escaping @MainActor () async throws -> Void,
         push: ((String, Encodable) -> Void)? = nil) {
        self.timeout = timeout
        self.inject = inject
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

    /// Fails the request in progress with `CancellationError`. A reply may still come, so the bridge ends.
    @MainActor
    func cancelPending() {
        guard isRequesting else { return }
        finish(.failure(CancellationError()), ending: true)
    }

    /// A new document has no late replies to wait for, and doesn't have the bundle yet.
    @MainActor
    func documentDidChange() {
        finish(.failure(CancellationError()), ending: false)
        isEnded = false
        isInjected = false
        document += 1
    }

    @MainActor
    private func request(_ method: String, params: Encodable, reply: Reply) async throws -> Any {
        guard !isEnded else { throw Error.ended }
        guard !isRequesting else { throw Error.busy }
        isRequesting = true
        defer { isRequesting = false }

        if !isInjected {
            let document = document
            try await inject()
            // The bundle went into a page that's gone, or the request was cancelled meanwhile.
            guard document == self.document, !isEnded else { throw CancellationError() }
            isInjected = true
        }

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
        guard let decoded: T = CodableHelper.decode(from: params) else {
            throw Error.malformedReply
        }
        return decoded
    }
}
