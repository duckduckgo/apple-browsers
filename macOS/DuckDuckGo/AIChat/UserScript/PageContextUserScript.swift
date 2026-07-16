//
//  PageContextUserScript.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AIChat
import Combine
import Common
import ConcurrencyExtensions
import Foundation
import FoundationExtensions
import OSLog
import UserScript
import WebKit

struct PageContextCollectionPayload: Codable {
    let serializedPageData: String?
}

struct PageContextResponse: Codable {
    let pageContext: AIChatPageContextData?
}

struct SelectionContextResponse: Codable {
    let selections: [AIChatSelectionContextData]
}

final class PageContextUserScript: NSObject, Subfeature {
    public let collectionResultPublisher: AnyPublisher<AIChatPageContextData?, Never>
    static public let featureName: String = "pageContext"
    public var featureName: String {
        Self.featureName
    }
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?
    let messageOriginPolicy: MessageOriginPolicy = .all

    private let collectionResultSubject = PassthroughSubject<AIChatPageContextData?, Never>()
    private var cancellables: Set<AnyCancellable> = []

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    enum MessageName: String {
        case collect
        case collectionResult
    }

    override init() {
        collectionResultPublisher = collectionResultSubject.eraseToAnyPublisher()
    }

    /// Requests collecting page context (fire-and-forget, result via collectionResultPublisher)
    func collect() {
        guard let webView else {
            return
        }
        broker?.push(method: MessageName.collect.rawValue, params: nil, for: self, into: webView)
    }

    /// Requests page context collection and awaits the result with a timeout.
    ///
    /// Used by the tab picker to extract content from a specific tab. The page context
    /// collection is fire-and-forget (`collect()`), with results arriving asynchronously
    /// via `collectionResultSubject`. This method bridges that Combine publisher into
    /// structured concurrency by racing two tasks:
    ///
    /// 1. An `AsyncStream` that wraps the Combine publisher and completes on the first value
    /// 2. A sleep task that returns `nil` after the timeout
    ///
    /// Whichever finishes first wins — `group.next()` returns the first result,
    /// then `cancelAll()` cancels the loser. No shared mutable state is needed.
    ///
    /// - Parameter timeout: Maximum time in seconds to wait for the page script to respond. Defaults to 5 seconds.
    /// - Returns: The collected page context data, or `nil` if the timeout expires or collection fails.
    @MainActor
    func collectAndWait(timeout: TimeInterval = 5) async -> AIChatPageContextData? {
        collect()

        // Bridge the Combine subject into an AsyncStream so we can use it in a task group.
        // Takes only the first value, then finishes. Cancellation tears down the subscription.
        let stream = AsyncStream<AIChatPageContextData?> { continuation in
            var cancellable: AnyCancellable?
            cancellable = collectionResultSubject
                .first()
                .sink { result in
                    continuation.yield(result)
                    continuation.finish()
                    cancellable?.cancel()
                }
            continuation.onTermination = { _ in
                cancellable?.cancel()
            }
        }

        // Race the collection result against the timeout.
        // The first task to complete provides the return value; the other is cancelled.
        return await withTaskGroup(of: AIChatPageContextData?.self) { group in
            group.addTask {
                for await result in stream { return result }
                return nil
            }
            group.addTask {
                try? await Task.sleep(interval: timeout)
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .collectionResult:
            return { [weak self] in await self?.collectionResult(params: $0, message: $1) }
        default:
            return nil
        }
    }

    /// Receives collected page context
    private func collectionResult(params: Any, message: UserScriptMessage) async -> Encodable? {
        guard let payload: PageContextCollectionPayload = DecodableHelper.decode(from: params),
              let jsonString = payload.serializedPageData,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        let pageContextData: AIChatPageContextData? = DecodableHelper.decode(jsonData: jsonData)
        collectionResultSubject.send(pageContextData)

        return nil
    }
}
