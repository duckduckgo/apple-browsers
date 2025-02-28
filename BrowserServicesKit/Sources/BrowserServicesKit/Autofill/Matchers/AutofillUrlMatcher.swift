//
//  AutofillUrlMatcher.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common

public protocol AutofillUrlMatcher {
    func normalizeUrlForWeb(_ url: String) -> String
    func isMatchingForAutofill(currentSite: String, savedSite: String, tld: TLD) -> Bool
    func normalizeSchemeForAutofill(_ rawUrl: String) -> URLComponents?
}

public struct AutofillDomainNameUrlMatcher: AutofillUrlMatcher {

    public init() {}

    public func normalizeUrlForWeb(_ url: String) -> String {
        let trimmedUrl = url.trimmingWhitespace()

        guard let urlComponents = normalizeSchemeForAutofill(trimmedUrl), let host = urlComponents.host else {
            return url
        }

        if let port = urlComponents.port {
            return "\(host):\(port)"
        } else {
            return host
        }
    }

    public func isMatchingForAutofill(currentSite: String, savedSite: String, tld: TLD) -> Bool {

        guard let currentUrlComponents = normalizeSchemeForAutofill(currentSite),
              let savedUrlComponents = normalizeSchemeForAutofill(savedSite) else {
            return false
        }

        if currentUrlComponents.port != savedUrlComponents.port {
            return false
        }

        if currentUrlComponents.eTLDplus1(tld: tld) == savedUrlComponents.eTLDplus1(tld: tld) {
            return true
        }

        return false
    }

    public func normalizeSchemeForAutofill(_ rawUrl: String) -> URLComponents? {
        if !rawUrl.starts(with: URL.URLProtocol.https.scheme) &&
           !rawUrl.starts(with: URL.URLProtocol.http.scheme) &&
           rawUrl.contains("://") {
            // Contains some other protocol, so don't mess with it
            return nil
        }

        let noScheme = rawUrl.dropping(prefix: URL.URLProtocol.https.scheme).dropping(prefix: URL.URLProtocol.http.scheme)
        return URLComponents(string: "\(URL.URLProtocol.https.scheme)\(noScheme)")
    }

    public func extractTLD(domain: String, tld: TLD) -> String? {
        guard var urlComponents = normalizeSchemeForAutofill(domain) else { return nil }
        guard urlComponents.host != .localhost else { return domain }
        return urlComponents.eTLDplus1WithPort(tld: tld)

    }

}
