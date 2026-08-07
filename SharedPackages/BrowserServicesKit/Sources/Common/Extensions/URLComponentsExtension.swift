//
//  URLComponentsExtension.swift
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
import FoundationExtensions
import WebKit

extension URLComponents {

    /// Parses a WebKit-origin `URL` into components using the original URL string.
    ///
    /// WebKit uses `WTF::URL` internally; delegate callbacks receive an `NSURL` conversion of it.
    /// Swift's `URL` (a re-implementation) correctly decomposes opaque URLs (about:, data:, …)
    /// into path/query/fragment, but NSURL does not: `.path` is always `""` for opaque URLs,
    /// so `URLComponents(url:)` ends up with empty path and query regardless of URL content.
    ///
    /// The private `_web_originalDataAsString` property — present on NSURL-backed values that
    /// came through WebKit — holds the original byte string. Parsing *that* with
    /// `URLComponents(string:)` bypasses the NSURL opaque URL limitation entirely.
    ///
    /// Falls back to `URLComponents(url:resolvingAgainstBaseURL:)` when the property is absent
    /// (`URL(string:)`-created values, all hierarchical URLs).
    init?(webKitUrl: URL) {
#if DEBUG && _ORIGINAL_DATA_AS_STRING_ENABLED
        // Ensure WebKit Framework is linked to test targets to make `_web_originalDataAsString` available.
        _=type(of: WKWebView.self)
#endif

#if _ORIGINAL_DATA_AS_STRING_ENABLED
        guard webKitUrl.isOpaque,
              let originalString = webKitUrl.originalWebKitString,
              let swiftNativeURLComponents = URLComponents(string: originalString) else {
            self.init(url: webKitUrl, resolvingAgainstBaseURL: false)
            return
        }
        self = swiftNativeURLComponents
#else
        self.init(url: webKitUrl, resolvingAgainstBaseURL: false)
#endif
    }

    public func eTLDplus1(tld: TLD) -> String? {
        return tld.eTLDplus1(self.host?.lowercased())
    }

    public func subdomain(tld: TLD) -> String? {
        return tld.extractSubdomain(from: self.host?.lowercased())
    }

    mutating public func eTLDplus1WithPort(tld: TLD) -> String? {
        guard let port = self.port else {
            return tld.eTLDplus1(self.host?.lowercased())
        }

        self.port = nil
        guard let etldPlus1 = tld.eTLDplus1(self.host?.lowercased()) else { return nil }

        return "\(etldPlus1):\(port)"
    }

    mutating public func addingSubdomain(from sourceURLComponents: URLComponents, tld: TLD) {
        guard let sourceURLSubdomain = sourceURLComponents.subdomain(tld: tld)?.droppingWwwPrefix(),
              !sourceURLSubdomain.isEmpty,
              sourceURLSubdomain != "www",
              let eTLDplus1 = eTLDplus1(tld: tld)
        else { return }

        host = [sourceURLSubdomain, eTLDplus1].joined(separator: ".")
    }

    mutating public func addingPort(from sourceURLComponents: URLComponents) {
        port = sourceURLComponents.port
    }

    mutating public func addingQueryItems(from sourceURLComponents: URLComponents) {
        guard let sourceQueryItems = sourceURLComponents.percentEncodedQueryItems else { return }
        percentEncodedQueryItems = (percentEncodedQueryItems ?? []) + sourceQueryItems
    }

    mutating public func addingFragment(from sourceURLComponents: URLComponents) {
        fragment = sourceURLComponents.fragment
    }
}
