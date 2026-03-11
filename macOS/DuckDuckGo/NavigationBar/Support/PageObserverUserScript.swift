//
//  PageObserverUserScript.swift
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

protocol PageObserverUserScriptDelegate: AnyObject {

    @MainActor
    func pageDOMLoaded()

}

/// Receives the `domLoaded` notification from the C-S-S `pageObserver` feature
/// running in the isolated content world, keeping the WebKit message handler
/// out of the page's JavaScript context.
final class PageObserverUserScript: NSObject, Subfeature {

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "pageObserver"

    weak var broker: UserScriptMessageBroker?
    weak var delegate: PageObserverUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case domLoaded
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .domLoaded:
            return { [weak self] in try await self?.domLoaded(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func domLoaded(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard original.frameInfo.isMainFrame else { return nil }
        delegate?.pageDOMLoaded()
        return nil
    }
}
