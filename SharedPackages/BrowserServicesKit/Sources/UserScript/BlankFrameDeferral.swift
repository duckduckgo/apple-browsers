//
//  BlankFrameDeferral.swift
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

/// The JavaScript that holds a user script back in a blank subframe (see `BlankFrameStart`). It runs inside the
/// wrapper from `prepareScriptSource`, which defines `run`, `isLoaded` and `markLoaded`.
enum BlankFrameDeferral {

    /// Defines `isBlankSubframe`: a same-origin subframe with no `src` (or `about:blank`) and no `srcdoc`
    static let isBlankSubframe = #"""
    const isBlankSubframe = (() => {
        if (window === window.top) return false;
        let frame = null;
        try { frame = window.frameElement; } catch (e) { return false; }
        if (!frame || frame.hasAttribute('srcdoc')) return false;
        const src = (frame.getAttribute('src') || '').trim();
        return src === '' || src === 'about:blank';
    })();
    """#

    static func start(_ start: BlankFrameStart) -> String {
        switch start {
        case .immediately:
            return "run(); markLoaded();"
        case .onProtectedAPIAccess:
            return onProtectedAPIAccess
        case .onContent:
            return onDocument(ready: "document.body && document.body.firstElementChild")
        case .onFormField:
            return onDocument(ready: "document.querySelector('input, textarea, select, [contenteditable]')")
        }
    }

    /// Traps every API Content Scope Scripts protects in the frame, plus document.open/write so written content never
    /// runs first. The first trap removes them all, runs the script, then answers from the API the script just protected.
    /// Marked loaded straight away, so WebKit running user scripts again after document.open() doesn't trap twice.
    private static let onProtectedAPIAccess = #"""
    markLoaded();
    const undo = [];
    let started = false;
    const startNow = () => {
        if (started) return;
        started = true;
        for (let i = undo.length - 1; i >= 0; i--) undo[i]();
        run();
    };
    const trapGetter = (target, name) => {
        const descriptor = target && Object.getOwnPropertyDescriptor(target, name);
        if (descriptor && (!descriptor.configurable || !descriptor.get)) return;
        Object.defineProperty(target, name, {
            configurable: true,
            enumerable: descriptor ? descriptor.enumerable : false,
            get() { startNow(); return this[name]; },
            set: descriptor && descriptor.set ? function (value) { startNow(); this[name] = value; } : undefined,
        });
        undo.push(() => { if (descriptor) { Object.defineProperty(target, name, descriptor); } else { delete target[name]; } });
    };
    const trapMethod = (target, name) => {
        const descriptor = target && Object.getOwnPropertyDescriptor(target, name);
        if (!descriptor || typeof descriptor.value !== 'function' || !descriptor.configurable) return;
        Object.defineProperty(target, name, { ...descriptor, value: function (...args) { startNow(); return Reflect.apply(target[name], this, args); } });
        undo.push(() => Object.defineProperty(target, name, descriptor));
    };
    const trapAll = (target) => {
        if (!target) return;
        for (const name of Object.getOwnPropertyNames(target)) {
            if (name === 'constructor') continue;
            const descriptor = Object.getOwnPropertyDescriptor(target, name);
            if (descriptor.get) { trapGetter(target, name); } else if (typeof descriptor.value === 'function') { trapMethod(target, name); }
        }
    };
    trapAll(Navigator.prototype);
    for (const name of ['globalPrivacyControl', 'duckduckgo']) { if (!(name in Navigator.prototype)) trapGetter(Navigator.prototype, name); }
    trapAll(Screen.prototype);
    for (const name of ['screenX', 'screenY', 'screenLeft', 'screenTop', 'outerWidth', 'outerHeight', 'devicePixelRatio']) trapGetter(window, name);
    for (const name of ['toDataURL', 'toBlob', 'getContext']) trapMethod(HTMLCanvasElement.prototype, name);
    trapAll(window.OffscreenCanvas && OffscreenCanvas.prototype);
    for (const name of ['getImageData', 'isPointInPath', 'isPointInStroke']) trapMethod(CanvasRenderingContext2D.prototype, name);
    for (const context of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
        if (context) for (const name of ['readPixels', 'getParameter', 'getExtension', 'getSupportedExtensions']) trapMethod(context.prototype, name);
    }
    if (window.AudioBuffer) for (const name of ['getChannelData', 'copyFromChannel']) trapMethod(AudioBuffer.prototype, name);
    trapAll(window.AnalyserNode && AnalyserNode.prototype);
    trapGetter(Document.prototype, 'cookie');
    for (const name of ['open', 'write', 'writeln']) trapMethod(Document.prototype, name);
    """#

    /// Runs the script once `ready` holds for the document. Marked loaded only when it runs: WebKit runs user scripts
    /// again after document.open(), which can leave an earlier observer behind, so whichever fires first runs it once.
    private static func onDocument(ready: String) -> String {
        """
        const ready = () => \(ready);
        const startNow = () => {
            if (isLoaded()) return;
            markLoaded();
            run();
        };
        if (ready()) {
            startNow();
        } else {
            const observer = new MutationObserver(() => {
                if (ready()) {
                    observer.disconnect();
                    startNow();
                }
            });
            observer.observe(document, { childList: true, subtree: true });
        }
        """
    }
}
