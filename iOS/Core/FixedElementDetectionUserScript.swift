//
//  FixedElementDetectionUserScript.swift
//  Core
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

import os.log
import UserScript
import WebKit

public struct FixedElementEdges: Equatable {
    public let top: Bool
    public let bottom: Bool

    public init(top: Bool, bottom: Bool) {
        self.top = top
        self.bottom = bottom
    }
}

public protocol FixedElementDetectionUserScriptDelegate: NSObjectProtocol {
    func fixedElementDetectionUserScript(_ script: FixedElementDetectionUserScript,
                                         didDetect edges: FixedElementEdges,
                                         in webView: WKWebView?)
}

public final class FixedElementDetectionUserScript: NSObject, UserScript {

    public lazy var source: String = {
        do {
            let source = try Self.loadJS("fixed-element-detection", from: Bundle.core)
            Logger.general.debug("[FixedElementEdgeBleed] Loaded detection script")
            return source
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to load JS for FixedElementDetectionUserScript: \(error)")
        }
    }()

    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public var forMainFrameOnly = true
    public var requiresRunInPageContentWorld = true
    public var messageNames = ["fixedElementEdgesDetected"]

    public weak var delegate: FixedElementDetectionUserScriptDelegate?

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else {
            Logger.general.debug("[FixedElementEdgeBleed] Ignored child-frame message")
            return
        }
        guard let body = message.body as? [String: Any] else {
            Logger.general.debug("[FixedElementEdgeBleed] Rejected non-dictionary payload")
            return
        }
        if body["stage"] as? String == "installed" {
            Logger.general.debug("[FixedElementEdgeBleed] JS installed in main frame")
            return
        }
        guard let top = body["top"] as? Bool,
              let bottom = body["bottom"] as? Bool else {
            Logger.general.debug("[FixedElementEdgeBleed] Rejected malformed detection payload")
            return
        }
        let elementsScanned = body["elementsScanned"] as? Int ?? -1
        let fixedElements = body["fixedElements"] as? Int ?? -1
        let visibleFixedElements = body["visibleFixedElements"] as? Int ?? -1
        let edgeSpanningFixedElements = body["edgeSpanningFixedElements"] as? Int ?? -1
        let backgroundPaintingFixedElements = body["backgroundPaintingFixedElements"] as? Int ?? -1
        let viewportHeight = body["viewportHeight"] as? Double ?? -1
        Logger.general.debug(
            """
            [FixedElementEdgeBleed] JS message received top=\(top, privacy: .public) bottom=\(bottom, privacy: .public) \
            scanned=\(elementsScanned, privacy: .public) fixed=\(fixedElements, privacy: .public) \
            visibleFixed=\(visibleFixedElements, privacy: .public) edgeSpanning=\(edgeSpanningFixedElements, privacy: .public) \
            paintsBackground=\(backgroundPaintingFixedElements, privacy: .public) \
            viewportHeight=\(viewportHeight, privacy: .public) \
            hasWebView=\(message.webView != nil, privacy: .public)
            """)
        guard delegate != nil else {
            Logger.general.debug("[FixedElementEdgeBleed] Detection message has no native delegate")
            return
        }
        delegate?.fixedElementDetectionUserScript(
            self,
            didDetect: FixedElementEdges(top: top, bottom: bottom),
            in: message.webView)
    }
}
