//
//  WebExtensionColorSchemeScript.swift
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

/// JavaScript injected at document start into every page an extension owns, which gives a page
/// that declares no color scheme the light defaults Chrome gives it.
///
/// Chrome renders a page whose `color-scheme` is `normal` with black text, a white canvas and
/// light form controls, whatever the system appearance. WebKit takes those defaults from the web
/// view's appearance instead, so in a dark app an extension built for Chrome that leaves some
/// text at the default color — LastPass does, on its own light backgrounds — renders it white.
///
/// The script adopts a stylesheet whose only rule is `:where(:root) { color-scheme: only light }`.
/// `:where()` has zero specificity, so any `color-scheme` the page sets itself wins, and a page
/// that declares one through a `<meta>` tag gets the stylesheet removed once it is parsed.
/// `prefers-color-scheme` still follows the app, as it does in Chrome. A constructed stylesheet is
/// not subject to the page's content security policy the way an injected `<style>` element is.
///
/// The script returns early when neither `chrome` nor `browser` is defined, so a page that is not
/// an extension page is left alone.
enum WebExtensionColorSchemeScript {

    static let source = """
    (function() {
        if (typeof globalThis.chrome === "undefined" && typeof globalThis.browser === "undefined") {
            return;
        }
        if (!document.adoptedStyleSheets || typeof CSSStyleSheet !== "function") {
            return;
        }

        var sheet = new CSSStyleSheet();
        try {
            sheet.replaceSync(":where(:root) { color-scheme: only light; }");
            document.adoptedStyleSheets = document.adoptedStyleSheets.concat([sheet]);
        } catch (error) {
            return;
        }

        document.addEventListener("DOMContentLoaded", function() {
            if (!document.querySelector('meta[name="color-scheme"]')) {
                return;
            }
            document.adoptedStyleSheets = document.adoptedStyleSheets.filter(function(adopted) {
                return adopted !== sheet;
            });
        }, { once: true });
    })();
    """
}
