//
//  ContextMenuSubfeature.swift
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
import UserScript
import WebKit

@MainActor
protocol ContextMenuUserScriptDelegate: AnyObject {
    func willShowContextMenu(withSelectedText selectedText: String?, linkURL: String?)
}

/// C-S-S isolated-world subfeature that receives context menu metadata from JS.
///
/// Replaces the legacy `ContextMenuUserScript` (which injected raw JS into
/// the page world and exposed `window.webkit`).  The JS side is implemented
/// in `injected/src/features/context-menu.js`.
final class ContextMenuSubfeature: NSObject, Subfeature {

    struct ContextMenuEventPayload: Codable {
        let selectedText: String?
        let linkUrl: String?
        let imageSrc: String?
        let imageAlt: String?
        let title: String?
        let elementTag: String?
    }

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "contextMenu"

    weak var broker: UserScriptMessageBroker?
    weak var delegate: ContextMenuUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case contextMenuEvent
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .contextMenuEvent:
            return { [weak self] in try await self?.contextMenuEvent(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func contextMenuEvent(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload: ContextMenuEventPayload = DecodableHelper.decode(from: params) else { return nil }

        delegate?.willShowContextMenu(withSelectedText: payload.selectedText, linkURL: payload.linkUrl)
        return nil
    }
}
