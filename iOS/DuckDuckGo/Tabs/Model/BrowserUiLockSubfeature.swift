//
//  BrowserUiLockSubfeature.swift
//  DuckDuckGo
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
import UserScript
import WebKit

protocol BrowserUiLockSubfeatureDelegate: AnyObject {
    @MainActor
    func browserUiLockSubfeature(_ subfeature: BrowserUiLockSubfeature, didChangeLocked isLocked: Bool)
}

/// Receives `uiLockChanged` from the content-scope-scripts `browserUiLock` feature, which reports
/// pages that handle their own vertical gestures (games, Shorts-style feeds) so browser gestures
/// such as pull-to-refresh don't fight them.
final class BrowserUiLockSubfeature: NSObject, Subfeature {

    static let featureNameValue = "browserUiLock"

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = BrowserUiLockSubfeature.featureNameValue
    weak var broker: UserScriptMessageBroker?
    weak var delegate: BrowserUiLockSubfeatureDelegate?

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "uiLockChanged" else { return nil }
        return uiLockChanged
    }

    @MainActor
    func reset() {
        delegate?.browserUiLockSubfeature(self, didChangeLocked: false)
    }

    @MainActor
    private func uiLockChanged(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard original.frameInfo.isMainFrame,
              let payload = params as? [String: Any],
              let isLocked = payload["locked"] as? Bool else { return nil }
        delegate?.browserUiLockSubfeature(self, didChangeLocked: isLocked)
        return nil
    }
}
