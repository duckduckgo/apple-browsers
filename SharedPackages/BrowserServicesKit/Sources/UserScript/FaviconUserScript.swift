//
//  FaviconUserScript.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Foundation
import WebKit

/// Delegate protocol for receiving favicon link updates from pages
public protocol FaviconUserScriptDelegate: AnyObject {
    @MainActor
    func faviconUserScript(_ faviconUserScript: FaviconUserScript,
                           didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink],
                           for documentUrl: URL,
                           in webView: WKWebView?)
}

/// A subfeature that handles favicon link discovery from web pages via Content Scope Scripts.
/// This script receives notifications from the C-S-S favicon feature when favicon links are found.
public final class FaviconUserScript: NSObject, Subfeature {

    /// Payload received from the C-S-S favicon feature
    public struct FaviconsFoundPayload: Codable, Equatable {
        public let documentUrl: URL
        public let favicons: [FaviconLink]

        public init(documentUrl: URL, favicons: [FaviconLink]) {
            self.documentUrl = documentUrl
            self.favicons = favicons
        }
    }

    /// Represents a single favicon link element from the page
    public struct FaviconLink: Codable, Equatable {
        public let href: URL
        public let rel: String
        /// MIME type of the favicon (e.g., "image/png"). Used by C-S-S for SVG filtering on iOS.
        public let type: String?

        public init(href: URL, rel: String, type: String? = nil) {
            self.href = href
            self.rel = rel
            self.type = type
        }
    }

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = "favicon"

    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: FaviconUserScriptDelegate?

    public override init() {
        super.init()
    }

    public enum MessageNames: String, CaseIterable {
        case faviconFound
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .faviconFound:
            return { [weak self] in try await self?.faviconFound(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func faviconFound(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let faviconsPayload: FaviconsFoundPayload = DecodableHelper.decode(from: params) else { return nil }

        delegate?.faviconUserScript(self, didFindFaviconLinks: faviconsPayload.favicons, for: faviconsPayload.documentUrl, in: original.webView)
        return nil
    }
}
