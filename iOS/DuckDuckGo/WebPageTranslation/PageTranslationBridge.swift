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

/// The page side of a translation: its text out, the translations back in.
@MainActor
protocol PageTranslationBridging: AnyObject {
    func extract() async throws -> (units: [PageTranslationUnit], documentID: UUID)
    func apply(_ updates: [PageTranslationUpdate], from source: String, to target: String, in documentID: UUID) async throws -> Int
}

/// Talks to C-S-S's `pageTranslation` bundle in the isolated world, injecting it once per document.
/// The bundle answers each push with a separate notification that echoes the push's `requestId`, so a
/// late reply to a request that timed out or was cancelled is ignored. One request is in flight at a time.
final class PageTranslationBridge: NSObject, Subfeature, PageTranslationBridging {

    enum Error: DDGError {
        case timeout
        /// A request is already waiting for its reply.
        case busy
        /// The bundle's reply didn't have the expected shape.
        case malformedReply

        static var errorDomain: String { "com.duckduckgo.pageTranslationBridge" }

        var errorCode: Int {
            switch self {
            case .timeout: return 1
            case .busy: return 2
            case .malformedReply: return 3
            }
        }

        var description: String {
            switch self {
            case .timeout: return "The page translation script didn't reply in time"
            case .busy: return "A page translation request is already in progress"
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

    private struct ExtractParams: Encodable {
        let requestId: String
    }

    private struct ApplyParams: Encodable {
        let requestId: String
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
    @MainActor private var pending: (reply: Reply, requestID: String, continuation: CheckedContinuation<Any, Swift.Error>)?
    @MainActor private var timeoutTask: Task<Void, Never>?
    @MainActor private var isInjected = false
    /// New for every document, so a request can tell the page changed while it was injecting.
    @MainActor private var documentID = UUID()

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

    /// - Returns: the units, and the document they belong to, for `apply`.
    @MainActor
    func extract() async throws -> (units: [PageTranslationUnit], documentID: UUID) {
        // Read before the request: the document can change after the reply, before this resumes.
        let documentID = documentID
        let params = try await request("extract", reply: .extractResult) { ExtractParams(requestId: $0) }
        return (try Self.decode(ExtractResult.self, from: params).units, documentID)
    }

    /// - Parameter documentID: from the `extract` the updates' units came from.
    @MainActor
    func apply(_ updates: [PageTranslationUpdate], from source: String, to target: String, in documentID: UUID) async throws -> Int {
        // Each document numbers its units from 0, so another document's updates would hit the wrong ones.
        guard documentID == self.documentID else { throw CancellationError() }
        let params = try await request("apply", reply: .applyResult) {
            ApplyParams(requestId: $0, sourceLanguage: source, targetLanguage: target, updates: updates)
        }
        return try Self.decode(ApplyResult.self, from: params).count
    }

    /// A new document doesn't have the bundle yet.
    @MainActor
    func documentDidChange() {
        finish(.failure(CancellationError()))
        isInjected = false
        documentID = UUID()
    }

    /// - Parameter params: the push's params for the request's id.
    @MainActor
    private func request(_ method: String, reply: Reply, params: (String) -> Encodable) async throws -> Any {
        guard !isRequesting else { throw Error.busy }
        isRequesting = true
        defer { isRequesting = false }

        if !isInjected {
            let documentID = documentID
            try await inject()
            // The bundle went into a page that's gone.
            guard documentID == self.documentID else { throw CancellationError() }
            isInjected = true
        }

        let requestID = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            pending = (reply, requestID, continuation)
            let timeout = timeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(Error.timeout))
            }
            push(method, params(requestID))
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
        // A reply to a request that isn't pending is late (timed out, cancelled) or forged.
        guard let pending, pending.reply == reply,
              (params as? [String: Any])?["requestId"] as? String == pending.requestID else { return }
        finish(.success(params))
    }

    @MainActor
    private func finish(_ result: Result<Any, Swift.Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
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
