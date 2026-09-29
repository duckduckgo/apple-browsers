//
//  PageSignalModels.swift
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
import FoundationExtensions

public struct ContentRuleListAction {
    private enum Keys {
        static let blockedLoad = "blockedLoad"
        static let blockedCookies = "blockedCookies"
        static let modifiedHeaders = "modifiedHeaders"
    }

    // nil means this WebKit version does not expose the field.
    public let blockedLoad: Bool?
    public let blockedCookies: Bool?
    public let modifiedHeaders: Bool?

    public init(blockedLoad: Bool?, blockedCookies: Bool?, modifiedHeaders: Bool?) {
        self.blockedLoad = blockedLoad
        self.blockedCookies = blockedCookies
        self.modifiedHeaders = modifiedHeaders
    }

    /// Decodes _WKContentRuleListAction without requiring private WebKit headers.
    public init(webKitAction: NSObject) {
#if PRIVATE_PAGE_SIGNALS_ENABLED
        blockedLoad = webKitAction.ddgValueIfAvailable(forKey: Keys.blockedLoad)
        blockedCookies = webKitAction.ddgValueIfAvailable(forKey: Keys.blockedCookies)
        modifiedHeaders = webKitAction.ddgValueIfAvailable(forKey: Keys.modifiedHeaders)
#else
        self.init(blockedLoad: nil, blockedCookies: nil, modifiedHeaders: nil)
#endif
    }
}

public enum PageResourceLoadError: Error, Hashable {
    case dns
    case certificate
    case connection
    /// HTTP 4xx response.
    case client
    /// HTTP 5xx response.
    case server

    /// Returns nil for successful or unclassified loads.
    init?(error: NSError?, response: URLResponse?) {
        if let error {
            self.init(error: error)
            return
        }

        guard let response = response as? HTTPURLResponse else {
            return nil
        }

        switch response.statusCode {
        case 400...499:
            self = .client
        case 500...599:
            self = .server
        default:
            return nil
        }
    }

    private init?(error: NSError) {
        guard error.domain == NSURLErrorDomain else { return nil }
        switch URLError.Code(rawValue: error.code) {
        case .cannotFindHost, .dnsLookupFailed:
            self = .dns
        case .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .dataNotAllowed, .internationalRoamingOff:
            self = .connection
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            self = .certificate
        default:
            return nil
        }
    }
}
