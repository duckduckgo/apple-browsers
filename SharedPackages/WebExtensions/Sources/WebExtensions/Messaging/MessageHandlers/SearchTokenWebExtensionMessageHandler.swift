//
//  SearchTokenWebExtensionMessageHandler.swift
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

@available(macOS 15.4, iOS 18.4, *)
public final class SearchTokenWebExtensionMessageHandler: WebExtensionMessageHandler {

    enum Method: String {
        case getToken
    }

    private weak var tokenProvider: SearchTokenProviding?

    public var handledFeatureName: String { "searchToken" }

    public init(tokenProvider: SearchTokenProviding) {
        self.tokenProvider = tokenProvider
    }

    public func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        guard let method = Method(rawValue: message.method) else {
            return .failure(WebExtensionMessageHandlerError.unknownMethod(message.method))
        }
        switch method {
        case .getToken:
            if let token = tokenProvider?.currentToken() {
                return .success(["token": token])
            }
            return .success([String: String]())
        }
    }
}
