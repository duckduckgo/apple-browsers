//
//  HoverUserScript.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import WebKit
import UserScript

protocol HoverUserScriptDelegate: AnyObject {

    @MainActor
    func hoverUserScript(_ script: HoverUserScript, didChange url: URL?)

}

/// Receives `hoverChanged` notifications from the C-S-S `hover` feature
/// running in the isolated content world, keeping the WebKit message handler
/// out of the page's JavaScript context.
final class HoverUserScript: NSObject, Subfeature {

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "hover"

    weak var broker: UserScriptMessageBroker?
    weak var delegate: HoverUserScriptDelegate?

    private(set) var lastURL: URL?

    enum MessageNames: String, CaseIterable {
        case hoverChanged
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .hoverChanged:
            return { [weak self] in try await self?.hoverChanged(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func hoverChanged(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let dict = params as? [String: Any] else { return nil }

        let url: URL?
        if let href = dict["href"] as? String {
            url = URL(string: href)
        } else {
            url = nil
        }

        if url != lastURL {
            lastURL = url
            delegate?.hoverUserScript(self, didChange: url)
        }

        return nil
    }
}
