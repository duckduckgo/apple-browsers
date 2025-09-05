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
import Foundation
import OSLog
import UserScript
import WebKit

struct PageContextPayload: Codable {
    let serializedPageData: AIChatPageContextData
}

final class PageContextUserScript: NSObject, Subfeature {
    public let collectionResultPublisher: AnyPublisher<String, Never>
    public let featureName: String = "pageContext"
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?
    let messageOriginPolicy: MessageOriginPolicy = .all

    private let collectionResultSubject = PassthroughSubject<String, Never>()
    private var cancellables: Set<AnyCancellable> = []

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    enum MessageName: String {
        case collect
        case collectionResult
        case collectionError
    }

    override init() {
        collectionResultPublisher = collectionResultSubject.eraseToAnyPublisher()
    }

    /// Requests collecting page context
    func collect() {
        guard let webView else {
            return
        }
        broker?.push(method: MessageName.collect.rawValue, params: nil, for: self, into: webView)
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .collectionResult:
            return { [weak self] in await self?.collectionResult(params: $0, message: $1) }
        case .collectionError:
            return { [weak self] in await self?.collectionError(params: $0, message: $1) }
        default:
            return nil
        }
    }

    /// Receives collected page context
    private func collectionResult(params: Any, message: UserScriptMessage) async -> Encodable? {
        guard let payload: PageContextPayload = DecodableHelper.decode(from: params) else {
            return nil
        }
        collectionResultSubject.send(payload.serializedPageData)
        return nil
    }

    private func collectionError(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.error("\(#function): \(String(reflecting: params))")
        return nil
    }
}
