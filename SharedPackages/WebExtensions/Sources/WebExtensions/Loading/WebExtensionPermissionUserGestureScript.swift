//
//  WebExtensionPermissionUserGestureScript.swift
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

/// Records genuine extension interaction from an isolated content world. The extension's page
/// scripts cannot call this world's native handler or forge a trusted DOM event.
public enum WebExtensionPermissionUserGestureScript {
    public static let messageHandlerName = "ddgWebExtensionPermissionUserGesture"

    public static let source = """
    (function() {
        "use strict";
        if (globalThis.location.protocol !== "webkit-extension:") { return; }
        var handler = globalThis.webkit.messageHandlers.\(messageHandlerName);
        var keyPressed = false;
        var modifierKeys = ["Alt", "AltGraph", "CapsLock", "Control", "Fn", "Meta", "Shift"];
        function record(event) {
            if (event.isTrusted && !event.repeat) { handler.postMessage(null); }
        }
        globalThis.addEventListener("pointerdown", record, true);
        globalThis.addEventListener("keydown", function(event) {
            // System/browser shortcuts, modifier keys, and dismissing UI do not authorize a prompt.
            if (event.metaKey || event.ctrlKey || event.key === "Escape" || modifierKeys.indexOf(event.key) !== -1) { return; }
            if (event.isTrusted) { keyPressed = true; }
            record(event);
        }, true);
        globalThis.addEventListener("keyup", function(event) {
            if (event.isTrusted) { setTimeout(function() { keyPressed = false; }, 0); }
        }, true);
        // Pointer and keyboard clicks were recorded at activation start. An accessibility click
        // has no preceding pointer/key event and still needs to authorize the request.
        globalThis.addEventListener("click", function(event) {
            if (event.detail === 0 && !keyPressed) { record(event); }
        }, true);
    })();
    """
}
