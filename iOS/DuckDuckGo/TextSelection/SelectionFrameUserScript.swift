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
import os.log

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
final class SelectionFrameUserScript: NSObject, UserScript {

    private enum MessageName {
        static let selectionChanged = "selectionFrameChanged"
    }

    static let readSelectionScript = "window.__ddgSelectionFrame.readSelection()"

    /// An empty source leaves the feature inert rather than taking the app down with it.
    var source: String = {
        do {
            return try SelectionFrameUserScript.loadJS("selectionframe", from: .main)
        } catch {
            (error as? UserScriptError)?.fireLoadJSFailedPixelIfNeeded()
            Logger.aiChat.error("Failed to load selectionframe.js: \(error.localizedDescription)")
            return ""
        }
    }()

    var injectionTime: WKUserScriptInjectionTime = .atDocumentStart

    /// An iframe has to be able to report its own selection.
    var forMainFrameOnly: Bool = false

    var messageNames: [String] = [MessageName.selectionChanged]

    /// The frame holding the selection.
    private(set) var frameWithSelection: SelectionFrame?

    private var trackedFrameToken: String?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        update(with: message.body, from: message.frameInfo)
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
