//
//  SelectionFrameUserScript.swift
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

import WebKit
import UserScript

/// A frame that can be evaluated in, without exposing the `WKFrameInfo` it wraps.
///
/// Reading `WKFrameInfo.request` terminates the app, so the value is kept unreachable rather than
/// documented as unsafe.
struct SelectionFrame {

    private let frameInfo: WKFrameInfo
    private let frameToken: String

    init(_ frameInfo: WKFrameInfo, frameToken: String) {
        self.frameInfo = frameInfo
        self.frameToken = frameToken
    }

    func evaluateJavaScript(_ script: String,
                            in webView: WKWebView,
                            contentWorld: WKContentWorld,
                            completionHandler: @escaping (Result<Any, Error>) -> Void) {
        webView.evaluateJavaScript(script, in: frameInfo, in: contentWorld, completionHandler: completionHandler)
    }

    func selectedText(from value: Any) -> String? {
        guard let result = value as? [String: Any],
              result["frameToken"] as? String == frameToken else { return nil }
        return result["selectedText"] as? String
    }
}

/// Tracks which frame holds the page's text selection, so a selection made inside an iframe can be read.
///
/// Reports only whether a selection exists, never its text.
final class SelectionFrameUserScript: NSObject, Subfeature {

    private enum MessageName: String {
        case isEnabled
        case selectionChanged = "selectionFrameChanged"
    }

    static let readSelectionScript = "window.__ddgSelectionFrame.readSelection()"

    let featureName = "textSelection"
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?

    /// The frame holding the selection.
    private(set) var frameWithSelection: SelectionFrame?

    private let isEnabled: Bool
    private var trackedFrameToken: String?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .isEnabled:
            return { [isEnabled] _, _ in SelectionFrameEnabledResponse(enabled: isEnabled) }
        case .selectionChanged:
            return { [weak self] params, original in
                await MainActor.run {
                    self?.update(with: params, from: original.frameInfo)
                }
                return nil
            }
        case nil:
            return nil
        }
    }

    /// Split from the handler for testing: `WKScriptMessage` cannot be constructed, `WKFrameInfo` can be mocked.
    func update(with body: Any, from frame: WKFrameInfo) {
        guard let body = body as? [String: Any],
              let hasSelection = body["hasSelection"] as? Bool,
              let frameToken = body["frameToken"] as? String else { return }

        if hasSelection {
            frameWithSelection = SelectionFrame(frame, frameToken: frameToken)
            trackedFrameToken = frameToken
        } else if frameToken == trackedFrameToken {
            // Only the tracked frame may release the claim: selecting in an iframe collapses the main
            // frame's selection, and its "empty" report can arrive last.
            frameWithSelection = nil
            trackedFrameToken = nil
        }
    }

    func reset() {
        frameWithSelection = nil
        trackedFrameToken = nil
    }
}

struct SelectionFrameEnabledResponse: Encodable, Equatable {
    let enabled: Bool
}
