//
//  WebRTCUserScript.swift
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
import WebKit
import UserScript

protocol WebRTCUserScriptDelegate: AnyObject {
    @MainActor func webRTCUserScript(_ script: WebRTCUserScript, didChangeConnectionActive active: Bool)
}

/// Receives `webRTCConnectionChanged` notifications from the Content Scope Scripts `webRtcDetection` feature.
/// Used to prevent tab suspension while a page has an open peer connection.
final class WebRTCUserScript: NSObject, Subfeature {

    struct WebRTCConnectionPayload: Decodable {
        let isActive: Bool
    }

    let messageOriginPolicy: MessageOriginPolicy = .all

    static public let featureName: String = "webRtcDetection"
    var featureName: String {
        Self.featureName
    }

    weak var broker: UserScriptMessageBroker?
    weak var delegate: WebRTCUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case webRTCConnectionChanged
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .webRTCConnectionChanged:
            return { [weak self] in try await self?.webRTCConnectionChanged(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func webRTCConnectionChanged(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload: WebRTCConnectionPayload = DecodableHelper.decode(from: params) else { return nil }
        delegate?.webRTCUserScript(self, didChangeConnectionActive: payload.isActive)
        return nil
    }
}
