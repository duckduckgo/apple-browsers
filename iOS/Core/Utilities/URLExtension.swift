//
//  URLExtension.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import AppRouting
import Foundation
import JavaScriptCore
import BrowserServicesKit
import Common
import FoundationExtensions

extension URL {

    public func toDesktopUrl() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.host = components.host?.dropping(prefix: "m.")
        components.host = components.host?.dropping(prefix: "mobile.")
        return components.url ?? self
    }

    public func isCustomURLScheme() -> Bool {
        guard let navigationalScheme else { return false }
        return !NavigationalScheme.hypertextSchemes.contains(navigationalScheme)
    }

    // MARK: static

    public static func webUrl(from text: String) -> URL? {
        URLInputClassifier.webUrl(from: text)
    }

    /// Returns true when address bar text should be treated as a direct URL navigation input.
    /// This intentionally rejects whitespace-containing input to avoid converting search-like text into URLs.
    public static func isValidAddressBarURLInput(_ text: String) -> Bool {
        URLInputClassifier.isValidAddressBarURLInput(text)
    }

    public static func decode(query: String) -> String? {
        return query.removingPercentEncoding
    }

    /// Uses JavaScriptCore to determine if the bookmarklet is valid JavaScript
    public static func isValidBookmarklet(url: URL?) -> Bool {
        guard let url = url,
              let bookmarklet = url.toDecodedBookmarklet(),
              let context = JSContext() else { return false }

        context.evaluateScript(bookmarklet)
        if let exception = context.exception {
            // Allow ReferenceErrors since the bookmarklet will likely want to access
            // document or other variables which don't exist in this JSContext.  Consider
            // this bookmarklet invalid for all other exceptions.
            return exception.description.contains("ReferenceError")
        }
        return true
    }

    public func normalized() -> URL? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        components?.queryItems = nil
        components?.fragment = nil

        return components?.url
    }

}
