//
//  PageContextUserScript.swift
//  DuckDuckGo
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
import FoundationExtensions
import Foundation
import os.log
import UserScript
import WebKit

private struct PageContextCollectionPayload: Codable {
    let serializedPageData: String?
    /// Set (with no `serializedPageData`) when collection threw in the page.
    let error: String?
}

final class PageContextUserScript: NSObject, Subfeature {

    let collectionResultPublisher: AnyPublisher<PageContextCollectionResult, Never>

    static let featureName: String = "pageContext"
    var featureName: String { Self.featureName }

    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?
    let messageOriginPolicy: MessageOriginPolicy = .all

    private let collectionResultSubject = PassthroughSubject<PageContextCollectionResult, Never>()

    private enum MessageName: String {
        case collect
        case collectionResult
    }

    override init() {
        collectionResultPublisher = collectionResultSubject.eraseToAnyPublisher()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    /// Requests collecting page context
    func collect() {
        guard let webView else {
            Logger.aiChat.debug("[PageContextUserScript] collect() failed - webView is nil")
            return
        }
        guard let broker else {
            Logger.aiChat.debug("[PageContextUserScript] collect() failed - broker is nil")
            return
        }
        Logger.aiChat.debug("[PageContextUserScript] collect() - pushing message to webView")
        broker.push(method: MessageName.collect.rawValue, params: nil, for: self, into: webView)
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .collectionResult:
            return { [weak self] in await self?.collectionResult(params: $0, message: $1) }
        default:
            return nil
        }
    }

    /// Receives collected page context. Every reply must publish a result, including failures —
    /// otherwise the caller's pending collection is only cleared by its timeout.
    private func collectionResult(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("[PageContextUserScript] collectionResult received")
        guard let payload: PageContextCollectionPayload = DecodableHelper.decode(from: params) else {
            Logger.aiChat.debug("[PageContextUserScript] collectionResult - failed to decode payload")
            collectionResultSubject.send(.decodeFailed)
            return nil
        }

        guard let jsonString = payload.serializedPageData,
              let jsonData = jsonString.data(using: .utf8) else {
            Logger.aiChat.debug("[PageContextUserScript] collectionResult - script error: \(payload.error ?? "unknown")")
            collectionResultSubject.send(.scriptError)
            return nil
        }

        guard let pageContextData: AIChatPageContextData = DecodableHelper.decode(jsonData: jsonData) else {
            Logger.aiChat.debug("[PageContextUserScript] collectionResult - failed to decode context")
            collectionResultSubject.send(.decodeFailed)
            return nil
        }

        Logger.aiChat.debug("[PageContextUserScript] collectionResult - decoded context: success")
        collectionResultSubject.send(.collected(pageContextData))

        return nil
    }
}
