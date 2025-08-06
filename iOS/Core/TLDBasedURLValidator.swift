//
//  TLDBasedURLValidator.swift
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

import Common
import Network

public struct TLDBasedURLValidator {

    private let tld: TLD

    public init(tld: TLD) {
        self.tld = tld
    }

    /// We are only interested in URLs of the form http(s)://host.name[.text]
    /// If the format is anything else we consider it valid (e.g ip addresses)
    /// If the host is not in TLD then it's not valid
    public func isValid(_ url: URL) -> Bool {
        guard let scheme = url.navigationalScheme,

                // We only want to do extra validation for http(s)
              URL.NavigationalScheme.hypertextSchemes.contains(scheme),

                // Removes scheme prefix and separate
              let nakedUrl = url.nakedString,

              // If the naked URL is the same as the host, means there's no path or query string so we should validate the host explicitly
              nakedUrl == url.host
        else {
            return true
        }

        if tld.eTLDplus1(nakedUrl) == nil,
            IPv4Address(nakedUrl) == nil,
            nakedUrl != .localhost,
            !nakedUrl.hasSuffix(".local") {
            return false
        }

        return true
    }

}
