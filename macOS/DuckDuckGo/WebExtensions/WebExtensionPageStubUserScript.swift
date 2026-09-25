//
//  WebExtensionPageStubUserScript.swift
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
import UserScript
import WebExtensions
import WebKit

/// Installs `WebExtensionAPIStubScript` in tab web views, so it reaches extension pages that a
/// website embeds as an iframe.
///
/// `WebExtensionManager` installs the stub script on the extension controller's web view
/// configuration, which covers the pages WebKit creates for an extension: its background page,
/// action popup, options page and the iframes inside them. An extension page loaded as an iframe
/// inside a website is different: that frame lives in the tab's `WKWebView`, which has its own
/// configuration and its own user scripts, so the controller's script never runs there. iCloud
/// Passwords' "Enable Password AutoFill" prompt under login fields is such a frame
/// (`completion_list.html`), and it needs the stub script to hide `action.openPopup`.
///
/// The script runs in every frame of every tab, but returns right away unless the frame is an
/// extension page (`webkit-extension:`), so ordinary web content is untouched.
@available(macOS 15.4, *)
final class WebExtensionPageStubUserScript: NSObject, UserScript {

    var source: String {
        WebExtensionAPIStubScript.source
    }

    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly: Bool = false

    /// The extension's own scripts run in the page world of an extension frame, and that is where
    /// `chrome` exists, so the stubs must be installed in that world. The isolated world
    /// DuckDuckGo uses for its own scripts would not be seen by the extension.
    let requiresRunInPageContentWorld: Bool = true

    let messageNames: [String] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}
