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
import UserScript
import WebKit

protocol FaviconUserScriptDelegate: AnyObject {
    @MainActor
    func faviconUserScript(_ faviconUserScript: FaviconUserScript,
                           didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink],
                           for documentUrl: URL) async
}

final class FaviconUserScript: NSObject, Subfeature {

    struct FaviconsFoundPayload: Codable, Equatable {
        let documentUrl: URL
        let favicons: [FaviconLink]
    }

    struct FaviconLink: Codable, Equatable {
        let href: URL
        let rel: String

        /**
         * Returns a new `FaviconLink` with `href` upgraded to HTTPS, or nil if upgrading failed.
         *
         * Given that we use `URLSession` for fetching favicons, we can't fetch HTTP URLs, hence
         * upgrading to HTTPS.
         *
         * > `toHttps()` is safe for `data:` URLs.
         */
        func upgradedToHTTPS() -> Self? {
            guard let httpsHref = href.toHttps() else {
                return nil
            }
            return .init(href: httpsHref, rel: rel)
        }
    }

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "favicon"

    weak var broker: UserScriptMessageBroker?
    weak var delegate: FaviconUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case faviconFound
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .faviconFound:
            return { [weak self] in try await self?.faviconFound(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func faviconFound(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let faviconsPayload: FaviconsFoundPayload = DecodableHelper.decode(from: params)
        else {
            return nil
        }

        let faviconLinks = faviconsPayload.favicons.compactMap { $0.upgradedToHTTPS() }

        await delegate?.faviconUserScript(self, didFindFaviconLinks: faviconLinks, for: faviconsPayload.documentUrl)
        return nil
    }
}
