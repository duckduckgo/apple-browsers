//
//  DarkReaderWebExtensionMessageHandler.swift
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

public protocol DarkReaderExcludedDomainsProviding {
    var excludedDomains: [String] { get }
}

@available(macOS 15.4, iOS 18.4, *)
public final class DarkReaderWebExtensionMessageHandler: WebExtensionMessageHandler {

    enum Method: String {
        case isDomainExcluded
    }

    private let excludedDomainsProvider: DarkReaderExcludedDomainsProviding

    public var handledFeatureName: String { "darkReader" }

    public init(excludedDomainsProvider: DarkReaderExcludedDomainsProviding) {
        self.excludedDomainsProvider = excludedDomainsProvider
    }

    public func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        guard let method = Method(rawValue: message.method) else {
            return .failure(WebExtensionMessageHandlerError.unknownMethod(message.method))
        }

        switch method {
        case .isDomainExcluded:
            return handleIsDomainExcluded(message.params)
        }
    }

    private func handleIsDomainExcluded(_ params: [String: Any]?) -> WebExtensionMessageResult {
        guard let urlString = params?["url"] as? String,
              let url = URL(string: urlString),
              let host = url.host else {
            return .failure(WebExtensionMessageHandlerError.missingParameter("url"))
        }

        let excludedDomains = excludedDomainsProvider.excludedDomains
        let isExcluded = excludedDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }

        return .success(["isExcluded": isExcluded])
    }
}
