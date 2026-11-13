//
//  WebExtensionWebViewConfiguration.swift
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

/// Lets Manifest V3 extension pages use WebAssembly on WebKit before macOS 26.
///
/// That WebKit ignores `'wasm-unsafe-eval'` in a Manifest V3 extension's Content Security Policy
/// (https://bugs.webkit.org/show_bug.cgi?id=290153), so WebAssembly is disabled and extensions
/// built on it, like Bitwarden, never start. WebKit builds each extension page's configuration by
/// copying the controller's, which keeps this class, then sets the page's CSP mode. The mode only
/// decides which CSP keywords are honored, and the Manifest V2 mode honors `'wasm-unsafe-eval'`.
@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionWebViewConfiguration: WKWebViewConfiguration {

    private enum ContentSecurityPolicyMode {
        static let manifestV2: UInt = 1
        static let manifestV3: UInt = 2
    }

    @objc(_setContentSecurityPolicyModeForExtension:)
    func setContentSecurityPolicyModeForExtension(_ mode: UInt) {
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        let selector = #selector(setContentSecurityPolicyModeForExtension(_:))
        guard let implementation = class_getMethodImplementation(WKWebViewConfiguration.self, selector) else { return }
        let superSetter = unsafeBitCast(implementation, to: Setter.self)
        superSetter(self, selector, mode == ContentSecurityPolicyMode.manifestV3 ? ContentSecurityPolicyMode.manifestV2 : mode)
    }
}
