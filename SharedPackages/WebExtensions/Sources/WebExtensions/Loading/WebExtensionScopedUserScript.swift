//
//  WebExtensionScopedUserScript.swift
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
import ObjectiveC
import WebKit

/// User scripts that only run in pages whose URL matches given patterns.
///
/// The public `WKUserScript` runs in every page of the user content controller it is added to. WebKit's
/// own initializer with match patterns is SPI (`WKUserScriptPrivate.h`, macOS 15.4+), as is removing a
/// single script (`WKUserContentControllerPrivate.h`), so both are looked up at runtime and skipped
/// when missing: the script is then not added, rather than added for every page.
@available(macOS 15.4, iOS 18.4, *)
enum WebExtensionScopedUserScript {

    private static let initializerSelector = NSSelectorFromString(
        "_initWithSource:injectionTime:forMainFrameOnly:includeMatchPatternStrings:excludeMatchPatternStrings:associatedURL:contentWorld:")
    private static let allocSelector = NSSelectorFromString("alloc")
    private static let removeSelector = NSSelectorFromString("_removeUserScript:")

    private typealias Alloc = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
    private typealias Initializer = @convention(c) (Unmanaged<AnyObject>, Selector, NSString, Int, Bool,
                                                    NSArray?, NSArray?, NSURL?, WKContentWorld?) -> Unmanaged<WKUserScript>?

    /// Returns a page-world user script that only runs in documents whose URL matches `includeMatchPatterns`,
    /// or `nil` when WebKit lacks the SPI.
    static func make(source: String,
                     injectionTime: WKUserScriptInjectionTime,
                     forMainFrameOnly: Bool,
                     includeMatchPatterns: [String]) -> WKUserScript? {
        guard let initializerMethod = class_getInstanceMethod(WKUserScript.self, initializerSelector),
              let metaclass = object_getClass(WKUserScript.self),
              let allocMethod = class_getInstanceMethod(metaclass, allocSelector) else {
            return nil
        }

        let alloc = unsafeBitCast(method_getImplementation(allocMethod), to: Alloc.self)
        let initializer = unsafeBitCast(method_getImplementation(initializerMethod), to: Initializer.self)

        // `alloc` returns +1 and the initializer consumes it, returning +1 in turn.
        let allocated = alloc(WKUserScript.self, allocSelector)
        let script = initializer(allocated, initializerSelector, source as NSString, injectionTime.rawValue, forMainFrameOnly,
                                 includeMatchPatterns as NSArray, nil, nil, nil)
        return script?.takeRetainedValue()
    }

    /// Removes one user script, leaving every other script on the controller in place.
    static func remove(_ script: WKUserScript, from userContentController: WKUserContentController) {
        guard userContentController.responds(to: removeSelector) else { return }
        userContentController.perform(removeSelector, with: script)
    }
}
