//
//  FormFocusUserScript.swift
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

protocol FormFocusUserScriptDelegate: AnyObject {
    @MainActor func formFocusUserScript(_ script: FormFocusUserScript, didChangeFocus focused: Bool)
}

/// Injects a lightweight script that sends a one-way message whenever the user focuses or
/// blurs a form element (input, textarea, select, or contenteditable). Used to prevent
/// tab suspension while the user is actively filling a form.
final class FormFocusUserScript: NSObject, UserScript {

    // swiftlint:disable:next line_length
    var source: String = """
    (function () {
        'use strict';
        function isFormElement(el) {
            if (!el) return false;
            var tag = el.tagName;
            if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
            if (el.isContentEditable) return true;
            return false;
        }
        document.addEventListener('focusin', function (e) {
            if (isFormElement(e.target)) {
                window.webkit.messageHandlers.formFocusChanged.postMessage(true);
            }
        }, true);
        document.addEventListener('focusout', function (e) {
            if (isFormElement(e.target)) {
                window.webkit.messageHandlers.formFocusChanged.postMessage(false);
            }
        }, true);
    })();
    """

    var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    var forMainFrameOnly: Bool = false
    var messageNames: [String] = ["formFocusChanged"]

    weak var delegate: FormFocusUserScriptDelegate?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let focused = message.body as? Bool else { return }
        delegate?.formFocusUserScript(self, didChangeFocus: focused)
    }
}
