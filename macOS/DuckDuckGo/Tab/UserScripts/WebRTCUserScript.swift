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

import WebKit
import UserScript

protocol WebRTCUserScriptDelegate: AnyObject {
    @MainActor func webRTCUserScript(_ script: WebRTCUserScript, didChangeConnectionActive active: Bool)
}

/// Injects a lightweight script that intercepts `RTCPeerConnection` to detect active WebRTC sessions.
/// When a connection is created the native layer is notified; when all connections reach a terminal
/// state (`closed` or `failed`) or are explicitly closed, the native layer is notified that no
/// active connection remains. Used to prevent tab suspension while a page has an open peer connection.
final class WebRTCUserScript: NSObject, UserScript {

    // swiftlint:disable:next line_length
    var source: String = """
    (function () {
        'use strict';
        if (typeof RTCPeerConnection === 'undefined') return;
        var activeCount = 0;
        var OriginalRTC = window.RTCPeerConnection;
        function notifyHost() {
            window.webkit.messageHandlers.webRTCConnectionChanged.postMessage(activeCount > 0);
        }
        window.RTCPeerConnection = function RTCPeerConnection(config, constraints) {
            var pc = new OriginalRTC(config, constraints);
            activeCount++;
            notifyHost();
            pc.addEventListener('connectionstatechange', function () {
                var s = pc.connectionState;
                if (s === 'closed' || s === 'failed') {
                    activeCount = Math.max(0, activeCount - 1);
                    notifyHost();
                }
            });
            var origClose = pc.close.bind(pc);
            pc.close = function () {
                activeCount = Math.max(0, activeCount - 1);
                notifyHost();
                return origClose();
            };
            return pc;
        };
        window.RTCPeerConnection.prototype = OriginalRTC.prototype;
    })();
    """

    var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    var forMainFrameOnly: Bool = false
    var messageNames: [String] = ["webRTCConnectionChanged"]

    weak var delegate: WebRTCUserScriptDelegate?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let active = message.body as? Bool else { return }
        delegate?.webRTCUserScript(self, didChangeConnectionActive: active)
    }
}
